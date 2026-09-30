#!/usr/bin/env bash
# Fedora edition of install-grafana.sh — rootless Podman + user systemd services.
# Grafana + Prometheus + node_exporter as user containers (host networking),
# battery + NVIDIA GPU exporter as a native Python user service. No sudo needed.
set -Eeuo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA="$SRC/data"
BIN="$HOME/.local/bin"
mkdir -p "$DATA/grafana/provisioning/datasources" \
         "$DATA/grafana/provisioning/dashboards" \
         "$DATA/grafana/dashboards" \
         "$DATA/prometheus" \
         "$BIN" \
         ~/.config/systemd/user

cp -f "$SRC/grafana/datasources.yml"       "$DATA/grafana/provisioning/datasources/laptop.yml"
cp -f "$SRC/grafana/dashboards.yml"        "$DATA/grafana/provisioning/dashboards/laptop.yml"
cp -f "$SRC/grafana/laptop-dashboard.json" "$DATA/grafana/dashboards/"

# ---------- Prometheus scrape config ----------
# All containers run with --network=host in the user's network namespace, and the
# native exporter binds localhost too, so every target is plain 127.0.0.1.
cat > "$DATA/prometheus/prometheus.yml" <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['localhost:9090']

  - job_name: node
    static_configs:
      - targets: ['localhost:9100']

  - job_name: laptop
    static_configs:
      - targets: ['localhost:9835']
EOF

# ---------- systemd user units ----------
cat > ~/.config/systemd/user/node-exporter.service <<'EOF'
[Unit]
Description=Prometheus node_exporter (Podman, user)
After=network-online.target

[Service]
ExecStart=/usr/bin/podman run --rm --replace --name node-exporter \
  --pid=host \
  --network=host \
  -v /:/host:ro,rslave \
  quay.io/prometheus/node-exporter:latest \
  --path.rootfs=/host \
  --web.listen-address=127.0.0.1:9100
ExecStop=/usr/bin/podman stop --time 10 node-exporter
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

cat > ~/.config/systemd/user/prometheus.service <<EOF
[Unit]
Description=Prometheus (Podman, user)
After=network-online.target

[Service]
ExecStart=/usr/bin/podman run --rm --replace --name prometheus \
  --network=host \
  -v $DATA/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro,Z \
  docker.io/prom/prometheus:latest \
  --config.file=/etc/prometheus/prometheus.yml \
  --web.listen-address=127.0.0.1:9090
ExecStop=/usr/bin/podman stop --time 10 prometheus
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

cat > ~/.config/systemd/user/grafana.service <<EOF
[Unit]
Description=Grafana (Podman, user)
After=network-online.target

[Service]
ExecStart=/usr/bin/podman run --rm --replace --name grafana \
  --network=host \
  -e GF_SECURITY_ADMIN_USER=admin \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  -v $DATA/grafana/provisioning:/etc/grafana/provisioning:ro,Z \
  -v $DATA/grafana/dashboards:/var/lib/grafana/dashboards:ro,Z \
  docker.io/grafana/grafana:latest
ExecStop=/usr/bin/podman stop --time 10 grafana
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

# ---------- battery + GPU exporter (native python) ----------
cp -f "$SRC/battery_exporter.py" "$BIN/battery_exporter.py"
cat > "$BIN/battery_gpu_exporter.py" <<EOF
#!/usr/bin/env python3
"""Runs the repo battery exporter on :9835 and adds NVIDIA GPU gauges."""
import sys, threading, time
sys.path.insert(0, "$SRC")
import battery_exporter  # noqa: E402  (provides gauges + main loop)

threading.Thread(target=battery_exporter.main, daemon=True).start()

try:
    import pynvml
    pynvml.nvmlInit()
    from prometheus_client import Gauge
    devs = [pynvml.nvmlDeviceGetHandleByIndex(i) for i in range(pynvml.nvmlDeviceGetCount())]
    g_pow  = Gauge("nvidia_gpu_power_w", "GPU power draw W", ["gpu"])
    g_temp = Gauge("nvidia_gpu_temp_c", "GPU temperature C", ["gpu"])
    g_util = Gauge("nvidia_gpu_util_pct", "GPU utilization %", ["gpu"])
    g_memu = Gauge("nvidia_gpu_mem_used_bytes", "GPU memory used", ["gpu"])
    g_memt = Gauge("nvidia_gpu_mem_total_bytes", "GPU memory total", ["gpu"])
    while True:
        for i, d in enumerate(devs):
            if (p := pynvml.nvmlDeviceGetPowerUsage(d)) is not None:
                g_pow.labels(f"gpu{i}").set(round(p / 1000.0, 2))
            g_temp.labels(f"gpu{i}").set(pynvml.nvmlDeviceGetTemperature(d, pynvml.NVML_TEMPERATURE_GPU))
            u = pynvml.nvmlDeviceGetUtilizationRates(d)
            g_util.labels(f"gpu{i}").set(u.gpu)
            mu = pynvml.nvmlDeviceGetMemoryInfo(d)
            g_memu.labels(f"gpu{i}").set(mu.used)
            g_memt.labels(f"gpu{i}").set(mu.total)
        time.sleep(10)
except Exception as e:
    print("GPU exporter disabled:", e, flush=True)
    while True:
        time.sleep(60)
EOF
chmod +x "$BIN/battery_gpu_exporter.py"

cat > ~/.config/systemd/user/battery-gpu-exporter.service <<EOF
[Unit]
Description=Laptop battery + NVIDIA GPU Prometheus exporter (:9835)
After=network-online.target

[Service]
ExecStart=$BIN/battery_gpu_exporter.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now node-exporter prometheus grafana battery-gpu-exporter

sleep 5
echo "Service status:"
for s in node-exporter prometheus grafana battery-gpu-exporter; do
  printf "  %-26s %s\n" "$s" "$(systemctl --user is-active $s)"
done

echo
echo "Grafana:    http://localhost:3000  (admin/admin)"
echo "Prometheus: http://localhost:9090"
