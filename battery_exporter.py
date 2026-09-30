#!/usr/bin/env python3
"""Laptop battery & hardware Prometheus exporter.

Portable: reads sysfs (no distro-specific tools). Exposes /metrics on
port 9835. Runs as a user systemd service.
"""
import glob
import os
from prometheus_client import start_http_server, Gauge

PS = "/sys/class/power_supply"

g = {
    "capacity_pct": Gauge("laptop_battery_capacity_pct", "Battery charge percent", ["battery"]),
    "energy_wh": Gauge("laptop_battery_energy_wh", "Battery energy Wh", ["battery", "type"]),
    "health_pct": Gauge("laptop_battery_health_pct", "Battery full/design capacity percent", ["battery"]),
    "power_w": Gauge("laptop_battery_power_w", "Battery charge/discharge power W", ["battery"]),
    "voltage_v": Gauge("laptop_battery_voltage_v", "Battery bus voltage V", ["battery"]),
    "cycles": Gauge("laptop_battery_cycles", "Battery cycle count", ["battery"]),
    "ac_online": Gauge("laptop_ac_online", "1 if AC connected", []),
    "cpu_temp_c": Gauge("laptop_cpu_temp_c", "CPU package temperature C", []),
    "fan_rpm": Gauge("laptop_fan_rpm", "Fan speed rpm", ["fan"]),
}


def read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except (OSError, ValueError):
        return None


def num(path, scale=1.0):
    v = read(path)
    if v is None:
        return None
    try:
        return int(v) * scale
    except ValueError:
        try:
            return float(v) * scale
        except ValueError:
            return None


def collect():
    for bat in glob.glob(PS + "/BAT*"):
        b = os.path.basename(bat)
        full = num(bat + "/energy_full", 1e-6) or num(bat + "/charge_full", 1e-3)
        design = num(bat + "/energy_full_design", 1e-6) or num(bat + "/charge_full_design", 1e-3)
        now = num(bat + "/energy_now", 1e-6) or num(bat + "/charge_now", 1e-3)
        if full and design:
            g["health_pct"].labels(b).set(round(full / design * 100, 1))
        if full:
            g["energy_wh"].labels(b, "full").set(round(full, 3))
        if design:
            g["energy_wh"].labels(b, "design").set(round(design, 3))
        if now:
            g["energy_wh"].labels(b, "now").set(round(now, 3))
        if (p := num(bat + "/power_now", 1e-6)) is not None:
            g["power_w"].labels(b).set(round(p, 2))
        if (v := num(bat + "/voltage_now", 1e-6)) is not None:
            g["voltage_v"].labels(b).set(round(v, 3))
        if (c := num(bat + "/cycle_count")) is not None:
            g["cycles"].labels(b).set(c)
        if (cap := num(bat + "/capacity")) is not None:
            g["capacity_pct"].labels(b).set(cap)

    for ac in glob.glob(PS + "/A*"):
        if (v := num(ac + "/online")) is not None and v > 0:
            g["ac_online"].set(v)

    # CPU package temp
    for f in glob.glob("/sys/class/hwmon/hwmon*/temp*_label"):
        label = read(f)
        if label and ("Package id 0" in label or label == "Tctl"):
            inp = f.rsplit("_label", 1)[0] + "_input"
            if (t := num(inp := inp_path(f), 1e-3)) is not None:
                g["cpu_temp_c"].set(round(t, 1))
            break


def inp_path(label_file):
    return label_file.rsplit("_label", 1)[0] + "_input"


def num2(path, scale=1.0):
    v = read(path)
    if v is None:
        return None
    try:
        return int(v) * scale
    except ValueError:
        try:
            return float(v) * scale
        except ValueError:
            return None


def collect_cpu_temp():
    for f in glob.glob("/sys/class/hwmon/hwmon*/temp*_label"):
        label = read(f)
        if label and "Package id 0" in label:
            t = num2(inp_path(f), 1e-3)
            if t is not None:
                g["cpu_temp_c"].set(round(t, 1))
            return


def collect_fans():
    for i, f in enumerate(glob.glob("/sys/class/hwmon/hwmon*/fan*_input")):
        if (r := num2(f)) is not None:
            g["fan_rpm"].labels(f"fan{i}").set(r)


def main():
    start_http_server(9835)
    while True:
        collect()
        collect_cpu_temp()
        collect_fans()
        import time
        time.sleep(10)


if __name__ == "__main__":
    main()
