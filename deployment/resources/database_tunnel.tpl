#!/bin/bash

sudo -i

echo "Installing socat..."
yum -y install socat

echo "Creating socat service to access the database..."

cat >> /etc/systemd/system/socat.database.tunnel.service << EOF
[Unit]
Description=Forwards localhost:${FORWARD_PORT} to ${DATABASE_URL}

[Service]
ExecStart=/usr/bin/socat TCP4-LISTEN:${FORWARD_PORT},fork TCP4:${DATABASE_URL}

[Install]
WantedBy=multi-user.target
EOF

echo "socat service created."
echo "Starting socat service..."

systemctl start socat.database.tunnel.service

echo "socat service status..."
systemctl status socat.database.tunnel.service
