# Network Keepalive (systemd)

A lightweight, single-command installer that configures a Linux **systemd service** to continuously ping a configurable list of IP addresses. The service starts automatically after reboot and restarts if its main process exits.

This can help maintain periodic network traffic to devices that may otherwise sit idle.

## Features
- Supports adding or removing targets without modifying the service file.
- Runs a separate, continuous `ping` process for each address (in parallel).
- Automatically enables the service at boot through `systemctl enable`.
- Restarts the service after unexpected process exits.
- Retries an individual ping process after five seconds if it exits.
- Preserves your configured IP list if you run the installer again.

## Requirements

- Linux with **systemd**
- **Bash**, **systemctl**, and the Linux **ping** utility supporting `-O` (usually from `iputils`)
- Root or `sudo` privileges to install the service
- Network access to the target addresses (ICMP may be blocked by firewalls)

## Installation

Clone or download this repository, then run the installer from the repository directory:

```bash
chmod +x install-network-keepalive.sh
sudo ./install-network-keepalive.sh
```

Alternatively:

```bash
sudo bash install-network-keepalive.sh
```

The installer automatically:

1. Creates `/etc/network-keepalive/ips` with the default IPs **only if the file does not already exist**.
2. Installs the worker script at `/usr/local/bin/network-keepalive`.
3. Creates `/etc/systemd/system/network-keepalive.service`.
4. Reloads systemd, enables the service for boot, and starts (or restarts) it.

No additional `systemctl enable` command is needed after a successful installation.

## Default IP addresses

The following targets are included out of the box:

```text
10.225.0.134
10.225.0.179
10.225.0.53
10.225.0.117
10.225.0.51
10.121.130.87
10.225.0.115
```

The Linux `ping` utility sends approximately one request per second to each address by default. Each target runs in its own continuous process.

## Configuration

Edit the target list:

```bash
sudo vi /etc/network-keepalive/ips
```

Put **one IP address per line**. Add as many targets as your system resources and network permit. Blank lines and `#` comments are allowed:

```text
# Production devices
10.225.0.134
10.225.0.179
10.225.0.53

# Additional devices
10.225.0.117
10.225.0.51
10.121.130.87
10.225.0.115
# 10.225.0.200  # Temporarily disabled
```

Save the file and restart the service to load the updated list:

```bash
sudo systemctl restart network-keepalive.service
```

**Important:** Changes to the IP list are not picked up until you restart the service. Re-running the installer preserves an existing `/etc/network-keepalive/ips` file but replaces the installed worker and systemd unit with the versions supplied by the installer.

## Surviving a reboot

The installer runs:

```bash
systemctl enable network-keepalive.service
systemctl restart network-keepalive.service
```

The unit uses `WantedBy=multi-user.target`, so systemd starts it automatically on subsequent boots. It is also ordered after `network-online.target`, and `Restart=always` with `RestartSec=5` restarts the main service process if it exits. Each ping process also retries if it exits.

Confirm that the service is enabled and running:

```bash
systemctl is-enabled network-keepalive.service
systemctl is-active network-keepalive.service
```

Expected output:

```text
enabled
active
```

To verify after a reboot, reboot during an appropriate maintenance window:

```bash
sudo reboot
```

After reconnecting to the server, run:

```bash
systemctl status network-keepalive.service
systemctl is-enabled network-keepalive.service
```

The service will keep trying to ping the configured addresses even when individual targets are temporarily unavailable. Starting after `network-online.target` does **not** guarantee that remote targets are reachable.

## Service management

| Task | Command |
| --- | --- |
| Check status | `systemctl status network-keepalive.service` |
| Verify boot enablement | `systemctl is-enabled network-keepalive.service` |
| Start | `sudo systemctl start network-keepalive.service` |
| Stop | `sudo systemctl stop network-keepalive.service` |
| Restart / apply IP changes | `sudo systemctl restart network-keepalive.service` |
| Enable at boot | `sudo systemctl enable network-keepalive.service` |
| Disable and stop | `sudo systemctl disable --now network-keepalive.service` |
| View service logs | `journalctl -u network-keepalive.service --no-pager` |

## Troubleshooting

**Service will not start**

Check the service and systemd logs:

```bash
sudo systemctl status network-keepalive.service
sudo journalctl -u network-keepalive.service -n 50 --no-pager
```

Confirm the target file exists and contains at least one uncommented IP address:

```bash
cat /etc/network-keepalive/ips
```

**Want to see whether ping processes are running?**

```bash
pgrep -af 'ping -n -O'
```

The installed worker discards normal ping output to avoid filling the journal. An active service therefore does not prove every target is responding. Test a target directly when needed:

```bash
ping -n -c 3 10.225.0.134
```

**System uses a different `ping` implementation**

The service is written for Linux `ping` supporting the `-O` option. On distributions without it, install the appropriate `iputils` package or adjust the worker script.

## How it works

```text
/etc/network-keepalive/ips
          |
          v
/usr/local/bin/network-keepalive
          |
          +-- ping -n -O 10.225.0.134
          +-- ping -n -O 10.225.0.179
          +-- ping -n -O 10.225.0.53
          +-- ... one process per target
          |
          v
network-keepalive.service (systemd)
          |
          +-- automatically starts at boot
          +-- automatically restarts on exit
```

## Important notes

- Ping generates **ICMP network traffic**. It may help with some idle-related network behaviors, but it is **not a substitute for configuring NIC power management, interface state, or driver settings**.
- `ping` does not stop just because a target fails to respond; it continues transmitting. A firewall may block ICMP even when the remote device is healthy.
- The script launches one long-running ping process per target, so very large target lists increase process count and network traffic.
- The worker sends ping output to `/dev/null`, so no historical success/failure statistics are captured by default.

## Uninstallation

```bash
sudo systemctl disable --now network-keepalive.service
sudo rm -f /etc/systemd/system/network-keepalive.service
sudo rm -f /usr/local/bin/network-keepalive
sudo systemctl daemon-reload
```

To also remove your saved IP configuration, optionally run:

```bash
sudo rm -rf /etc/network-keepalive
```
