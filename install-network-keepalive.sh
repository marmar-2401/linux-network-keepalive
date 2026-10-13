#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
  echo "Run this installer with sudo: sudo bash $0" >&2
  exit 1
fi

command -v systemctl >/dev/null || { echo 'systemd is required.' >&2; exit 1; }
command -v ping >/dev/null || { echo 'ping is required (install iputils).' >&2; exit 1; }

# Create the target list once; leave existing lists unchanged on reinstall.
install -d -m 755 /etc/network-keepalive
if [[ ! -e /etc/network-keepalive/ips ]]; then
  cat > /etc/network-keepalive/ips <<'IPS'
10.225.0.134
10.225.0.179
10.225.0.53
10.225.0.117
10.225.0.51
10.121.130.87
10.225.0.115
IPS
  chmod 644 /etc/network-keepalive/ips
fi

# Run an independent, continuous ping for every configured address.
cat > /usr/local/bin/network-keepalive <<'WORKER'
#!/usr/bin/env bash
set -euo pipefail

count=0
while IFS= read -r ip || [[ -n "$ip" ]]; do
  ip="${ip%%#*}"              # Allow comments
  ip="${ip//[[:space:]]/}"   # Ignore whitespace
  [[ -z "$ip" ]] && continue

  (
    while true; do
      ping -n -O "$ip" >/dev/null 2>&1 || true
      sleep 5                 # Retry if ping ever exits
    done
  ) &
  count=$((count + 1))
done < /etc/network-keepalive/ips

if (( count == 0 )); then
  echo 'No IPs configured in /etc/network-keepalive/ips' >&2
  exit 1
fi
wait
WORKER
chmod 755 /usr/local/bin/network-keepalive

cat > /etc/systemd/system/network-keepalive.service <<'SERVICE'
[Unit]
Description=Continuous ping keepalive for configured IP addresses
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/network-keepalive
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable network-keepalive.service
systemctl restart network-keepalive.service

echo 'Installed and enabled network-keepalive.service'
echo 'Edit /etc/network-keepalive/ips to add or remove IPs, one per line.'
echo 'After editing: sudo systemctl restart network-keepalive.service'
echo 'Check status: systemctl status network-keepalive.service'
