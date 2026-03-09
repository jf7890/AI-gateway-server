#!/bin/sh

set -e

# Wait for network interface to come up fully
sleep 10

# Add community repository for pip and python if necessary
cat >> /etc/apk/repositories <<EOF
http://dl-cdn.alpinelinux.org/alpine/v3.20/community
EOF

apk update
apk upgrade

# Install python3 and required libs for FastAPI + SQLite
apk add --no-cache python3 py3-pip sqlite doas curl bash sqlite-dev gcc g++ python3-dev linux-headers musl-dev libffi-dev

# Create gateway group and user
addgroup -S gateway
adduser -S -D -h /opt/gateway-app -G gateway gateway

mkdir -p /opt/gateway-app
chown -R gateway:gateway /opt/gateway-app

echo "Installing Python dependencies..."
# We will use venv
su - gateway -c "python3 -m venv /opt/gateway-app/venv"
su - gateway -c "/opt/gateway-app/venv/bin/pip install --upgrade pip"
su - gateway -c "/opt/gateway-app/venv/bin/pip install -r /opt/gateway-app/requirements.txt"

# Install openrc init script for gateway
cp /opt/gateway-app/gateway.initd /etc/init.d/gateway
chmod +x /etc/init.d/gateway

# Add gateway service to default runlevel so it starts on boot
rc-update add gateway default

# Ensure SQLite data folder exists with correct permissions
mkdir -p /opt/gateway-app/data
chown -R gateway:gateway /opt/gateway-app/data

echo "Gateway provisioning complete!"
