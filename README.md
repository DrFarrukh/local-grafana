# local-grafana

Portable laptop health monitoring stack: **Grafana + Prometheus + node_exporter + a tiny sysfs battery exporter**.

Built for Linux Mint 22.x / Ubuntu 24.04 laptops. Works unchanged on machines with or without a discrete GPU; on NVIDIA machines (e.g. Lenovo LOQ 15 RTX 5050) add `nvidia_gpu_exporter` for GPU/fan metrics.

## What's inside

| File | Purpose |
|---|---|
| `install-grafana.sh` | Installs Grafana (official apt repo), Prometheus, node_exporter; writes scrape config; provisions datasource + dashboard; enables services |
| `battery_exporter.py` | Prometheus exporter on `:9835` reading sysfs: battery charge/health/Wh/power/voltage/cycles, AC state, CPU package temp, PCH/ACPI temps, fans |
| `grafana/datasources.yml` | Provisions the Prometheus datasource |
| `grafana/dashboards.yml` | Provisions the "Laptop" dashboard folder |
| `grafana/laptop-dashboard.json` | "Laptop Health" dashboard: battery gauges, temps, power, CPU/RAM/load, disk & network throughput |
| `install-sensors.sh` | Optional: lm-sensors detect + fan exposure check |
| `open-dashboard.sh`, `dashboard.py` | Lightweight HTML fallback dashboard regenerated from the minute-log JSONL |

## Install (any Ubuntu 24.04-based laptop)

```bash
git clone https://github.com/DrFarrukh/local-grafana.git
cd local-grafana
sudo ./install-grafana.sh
```

Then:

- Grafana: http://localhost:3000 — log in `admin`/`admin`
- Dashboard "Laptop Health" is pre-provisioned under the **Laptop** folder
- Prometheus: http://localhost:9090

## Services

| Service | Port | Level |
|---|---|---|
| grafana-server | 3000 | system |
| prometheus | 9090 | system |
| prometheus-node-exporter | 9100 | system |
| battery_exporter | 9835 | user (`systemctl --user`) |

Enable the exporter as a login service:

```bash
cp battery-exporter.service ~/.config/systemd/user/   # adjust ExecStart path if needed
systemctl --user daemon-reload && systemctl --user enable --now battery-exporter
```

## Notes

- Some consumer laptops (e.g. IdeaPad 110) do not expose fan RPM via ACPI; the exporter still collects all `fan*_input` nodes when the kernel provides them.
- Battery `energy_full` on a brand-new pack can be inaccurate until 2–3 full charge cycles have taught the fuel gauge.
- NVIDIA add-on (LOQ/RTX): install `nvidia_gpu_exporter` or DCGM-Exporter and append a scrape job to `/etc/prometheus/prometheus.yml`.
