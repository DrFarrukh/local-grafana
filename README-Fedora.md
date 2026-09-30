# Running on Fedora (rootless Podman)

`install-grafana.sh` is written for Ubuntu 24.04 / Mint 22.x. On Fedora, use this instead:

```bash
./install-fedora.sh
```

What it does **without sudo**:

- Runs Grafana, Prometheus, and node_exporter as **rootless Podman** containers
  managed by your **user systemd** (`~/.config/systemd/user/*.service`, enabled at login).
- Runs `battery_gpu_exporter.py` natively as a user service on `:9835`:
  the repo's sysfs battery exporter **plus NVIDIA GPU metrics** (power/temp/util/VRAM via NVML)
  and, in this fork, all per-core CPU temps, NVMe SSD temps.
- Provisions the Prometheus datasource + "Laptop Health" dashboard from `grafana/`.

Requires: `podman` (Fedora ships it) and `python3-pip` libs:
`pip install --user prometheus_client nvidia-ml-py`.

## Differences vs Ubuntu script

| Ubuntu script | Install-fedora.sh |
|---|---|
| apt packages, system services | podman containers, user services |
| scrapes `127.0.0.1:*` | scrapes `localhost:*` (same, IPv6-safe) |
| battery exporter only | battery + NVIDIA GPU + core/NVMe temps |
| data in `/etc`, `/var/lib` | all under `./data/` |

`battery_exporter.py` was extended here with `collect_core_temps()` and
`collect_nvme_temps()` (and two new gauge families), so it still works
unchanged on the Mint/Ubuntu target of the original script.

## Manage

```bash
systemctl --user status grafana prometheus node-exporter battery-gpu-exporter
journalctl --user -u grafana -f
podman ps
```
