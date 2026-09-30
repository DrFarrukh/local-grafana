#!/usr/bin/env bash
# Limit Ollama to loading ONE model at a time and keep the 4b resident.
set -Eeuo pipefail
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<'EOF'
[Service]
# Only one request/model slot; a second concurrent request waits.
Environment=OLLAMA_NUM_PARALLEL=1
# Remember at most one model in RAM (the last one used).
Environment=OLLAMA_MAX_LOADED_MODELS=1
# Keep the resident model alive for an hour instead of 5 minutes.
Environment=OLLAMA_KEEP_ALIVE=1h
EOF
systemctl daemon-reload
systemctl restart ollama.service
sleep 2
systemctl is-active ollama.service
systemctl show ollama.service -p Environment | tr ' ' '\n' | grep OLLAMA
