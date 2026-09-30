#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y lm-sensors
yes | sensors-detect --auto || true
echo '--- hwmon chips after detect ---'
for h in /sys/class/hwmon/hwmon*; do
  echo "$h: $(cat "$h/name" 2>/dev/null)"
done
echo '--- fan inputs found ---'
ls /sys/class/hwmon/hwmon*/fan*_input 2>/dev/null || echo 'NO fan*_input exposed by kernel'
sensors
