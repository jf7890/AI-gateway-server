#!/bin/sh

set -e

# Wait for network interface to come up fully
sleep 10

# Ensure community repository matches current Alpine version
ALPINE_BRANCH="$(. /etc/os-release && echo "$VERSION_ID" | awk -F. '{print $1"."$2}')"
COMMUNITY_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/community"
if ! grep -qF "$COMMUNITY_URL" /etc/apk/repositories; then
  echo "$COMMUNITY_URL" >> /etc/apk/repositories
fi

apk update
apk upgrade

# Install python3 and required libs for FastAPI + SQLite
apk add --no-cache python3 py3-pip sqlite doas curl bash sqlite-dev gcc g++ python3-dev linux-headers musl-dev libffi-dev

# Create gateway group and user
addgroup -S gateway >/dev/null 2>&1 || true
if ! id -u gateway >/dev/null 2>&1; then
  # Avoid home creation errors; we do not rely on home for venv paths
  adduser -S -D -G gateway gateway >/dev/null 2>&1 || true
fi

# Ensure app directory exists and is a directory
if [ -e /opt/gateway-app ] && [ ! -d /opt/gateway-app ]; then
  rm -f /opt/gateway-app
fi
mkdir -p /opt/gateway-app
chown -R gateway:gateway /opt/gateway-app

# If Packer uploaded into a nested folder, normalize it
if [ ! -f /opt/gateway-app/requirements.txt ] && [ -f /opt/gateway-app/gateway-app/requirements.txt ]; then
  cp -a /opt/gateway-app/gateway-app/. /opt/gateway-app/
  rm -rf /opt/gateway-app/gateway-app
fi

echo "Installing Python dependencies..."
# We will use venv
RUN_USER="gateway"
if ! id -u gateway >/dev/null 2>&1; then
  echo "WARN: gateway user missing; using root for venv install" >&2
  RUN_USER="root"
fi
if [ "$RUN_USER" = "root" ]; then
  python3 -m venv /opt/gateway-app/venv
  /opt/gateway-app/venv/bin/pip install --upgrade pip
  if [ -f /opt/gateway-app/requirements.txt ]; then
    /opt/gateway-app/venv/bin/pip install -r /opt/gateway-app/requirements.txt
  else
    echo "WARN: /opt/gateway-app/requirements.txt missing; skipping pip install" >&2
  fi
  chown -R gateway:gateway /opt/gateway-app/venv || true
else
  su -s /bin/sh "$RUN_USER" -c "python3 -m venv /opt/gateway-app/venv"
  su -s /bin/sh "$RUN_USER" -c "/opt/gateway-app/venv/bin/pip install --upgrade pip"
  if [ -f /opt/gateway-app/requirements.txt ]; then
    su -s /bin/sh "$RUN_USER" -c "/opt/gateway-app/venv/bin/pip install -r /opt/gateway-app/requirements.txt"
  else
    echo "WARN: /opt/gateway-app/requirements.txt missing; skipping pip install" >&2
  fi
fi

# Install openrc init script for gateway
cp /opt/gateway-app/gateway.initd /etc/init.d/gateway
chmod +x /etc/init.d/gateway

# Add gateway service to default runlevel so it starts on boot
rc-update add gateway default

# Ensure SQLite data folder exists with correct permissions
mkdir -p /opt/gateway-app/data
chown -R gateway:gateway /opt/gateway-app/data

echo "Gateway provisioning complete!"
