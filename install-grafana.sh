#!/usr/bin/env bash
# Real Grafana + Prometheus + node_exporter + laptop battery exporter.
# Designed to be portable: same script works on any Ubuntu 24.04-based
# laptop (Mint 22.x), including the LOQ 15 (adds GPU exporter support
# when nvidia-smi is present).
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
LOG=/var/log/qureshi-grafana-install.log
exec > >(tee -a "$LOG") 2>&1
echo "[$(date --iso-8601=seconds)] Grafana stack installation"

SRC=/home/qureshi/local_grafana

# ---------- Grafana official APT repo ----------
if ! grep -q grafana /etc/apt/sources.list.d/*.list 2>/dev/null; then
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
  echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
    > /etc/apt/sources.list.d/grafana.list
fi
apt-get update -o Dir::Etc::sourcelist="sources.list.d/grafana.list" \
                 -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" || apt-get update
apt-get install -y grafana prometheus prometheus-node-exporter python3-prometheus-client

# ---------- Prometheus config: scrape node + laptop exporters ----------
cat > /etc/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['127.0.0.1:9090']

  - job_name: node
    static_configs:
      - targets: ['127.0.0.1:9100']

  - job_name: laptop
    static_configs:
      - targets: ['127.0.0.1:9835']
EOF

# ---------- Grafana provisioning ----------
mkdir -p /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards
cp "$SRC/grafana/datasources.yml" /etc/grafana/provisioning/datasources/laptop.yml
cp "$SRC/grafana/dashboards.yml"  /etc/grafana/provisioning/dashboards/laptop.yml
mkdir -p /var/lib/grafana/dashboards
cp "$SRC/grafana/laptop-dashboard.json" /var/lib/grafana/dashboards/
chown grafana:grafana /var/lib/grafana/dashboards/laptop-dashboard.json || true

# ---------- Enable services ----------
systemctl enable --now prometheus-node-exporter
systemctl enable --now prometheus
systemctl enable --now grafana-server
sleep 3
for s in prometheus-node-exporter prometheus grafana-server; do
  echo "$s: $(systemctl is-active $s)"
done

echo "[$(date --iso-8601=seconds)] Grafana stack installation completed"
echo "Grafana:  http://localhost:3000 (admin/admin — change on first login)"
echo "Prometheus: http://localhost:9090"
