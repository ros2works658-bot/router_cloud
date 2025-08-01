#!/bin/bash

set -e

echo "🛠️ Updating package index..."
apt update -y

echo "📦 Installing required packages..."
apt install -y unzip curl wget

# === STEP 1: Download Zenoh Core ZIP ===
ZENOHPKG="zenoh-1.5.0-x86_64-unknown-linux-gnu-debian.zip"
if [ ! -f "$ZENOHPKG" ]; then
    echo "⬇️ Downloading Zenoh package..."
    wget https://download.eclipse.org/zenoh/zenoh/latest/$ZENOHPKG
fi

# === STEP 2: Unzip Core ===
if [ ! -f "zenohd_1.5.0_amd64.deb" ]; then
    echo "📦 Unzipping Zenoh packages..."
    unzip "$ZENOHPKG"
fi

# === STEP 3: Download Webserver Plugin ZIP ===
WEBPKG="zenoh-plugin-webserver-1.5.0-x86_64-unknown-linux-gnu-debian.zip"
if [ ! -f "$WEBPKG" ]; then
    echo "⬇️ Downloading Webserver plugin..."
    wget https://download.eclipse.org/zenoh/zenoh-plugin-webserver/1.5.0/$WEBPKG
fi

# === STEP 4: Unzip Webserver Plugin ===
if [ ! -f "zenoh-plugin-webserver_1.5.0_amd64.deb" ]; then
    echo "📦 Unzipping Webserver plugin..."
    unzip "$WEBPKG"
fi

# === STEP 5: Install All .deb Packages ===
echo "📥 Installing Zenoh components..."
dpkg -i zenoh_1.5.0_amd64.deb || true
dpkg -i zenohd_1.5.0_amd64.deb || true
dpkg -i zenoh-plugin-rest_1.5.0_amd64.deb || true
dpkg -i zenoh-plugin-storage-manager_1.5.0_amd64.deb || true
dpkg -i zenoh-plugin-webserver_1.5.0_amd64.deb || true

echo "🔧 Fixing missing dependencies..."
apt --fix-broken install -y

# === STEP 6: Create zenohd.json5 Config ===
CONFIG_FILE="zenohd.json5"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "📝 Creating zenohd.json5 config..."
    cat <<EOF > "$CONFIG_FILE"
{
  "mode": "router",
  "listen": {
    "endpoints": ["tcp/0.0.0.0:7447"]
  },
  "plugins": {
    "webserver": {
      "http_port": 8080,
      "work_thread_num": 4,
      "max_block_thread_num": 8
    }
  }
}
EOF
fi

# === STEP 7: Run Zenoh Router ===
echo "🚀 Launching Zenoh Router..."
zenohd -c "$CONFIG_FILE"
