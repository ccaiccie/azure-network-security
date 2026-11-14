#!/bin/bash
# User data for the lab web VMs (designed, not tested). Starts a tiny web server that answers "lab <name>" on tcp/80.
# Python's built-in server prints every request, with the client address, to the journal of the labweb service.
# Terraform replaces __NAME__ with the VM name.
set -eu
mkdir -p /opt/labweb
echo "lab __NAME__" > /opt/labweb/index.html
cat > /etc/systemd/system/labweb.service <<'UNIT'
[Unit]
Description=Lab web server
After=network.target

[Service]
WorkingDirectory=/opt/labweb
ExecStart=/usr/bin/python3 -m http.server 80
Restart=always

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now labweb
