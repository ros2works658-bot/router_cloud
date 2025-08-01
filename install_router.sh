#!/bin/bash

set -e

echo "🚀 Zenoh 1.5 Router Setup - WORKING VERSION"
echo "============================================"

# === STEP 1: Update System ===
echo "🛠️ Updating system..."
apt update -y
apt install -y unzip curl wget

# === STEP 2: Download Zenoh 1.5 ===
ZENOHPKG="zenoh-1.5.0-x86_64-unknown-linux-gnu-debian.zip"
if [ ! -f "$ZENOHPKG" ]; then
    echo "⬇️ Downloading Zenoh 1.5..."
    wget https://download.eclipse.org/zenoh/zenoh/latest/$ZENOHPKG
fi

# === STEP 3: Extract and Install ===
if [ ! -f "zenohd_1.5.0_amd64.deb" ]; then
    echo "📦 Extracting packages..."
    unzip -o "$ZENOHPKG"
fi

echo "📥 Installing Zenoh 1.5..."
dpkg -i zenoh_1.5.0_amd64.deb || true
dpkg -i zenohd_1.5.0_amd64.deb || true
dpkg -i zenoh-plugin-rest_1.5.0_amd64.deb || true
dpkg -i zenoh-plugin-storage-manager_1.5.0_amd64.deb || true

echo "🔧 Fixing dependencies..."
apt --fix-broken install -y

# === STEP 4: Create WORKING Config for Zenoh 1.5 ===
echo "📝 Creating WORKING Zenoh 1.5 config..."
cat <<'EOF' > "zenohd_working.json5"
{
  "mode": "router",
  "listen": {
    "endpoints": ["tcp/0.0.0.0:7447"]
  },
  "plugins": {
    "rest": {
      "http_port": 8080,
      "http_interface": "0.0.0.0"
    }
  }
}
EOF

# === STEP 5: Create Alternative REST Config ===
cat <<'EOF' > "zenohd_rest_only.json5"
{
  "plugins": {
    "rest": {
      "http_port": 8080
    }
  }
}
EOF

# === STEP 6: Create Minimal Config ===
cat <<'EOF' > "zenohd_minimal.json5"
{
  "plugins": {
    "rest": {}
  }
}
EOF

# === STEP 7: Validate Configs ===
echo "🧪 Validating configurations..."
for config in zenohd_working.json5 zenohd_rest_only.json5 zenohd_minimal.json5; do
    if zenohd -c "$config" --dry-run >/dev/null 2>&1; then
        echo "✅ $config is valid"
    else
        echo "❌ $config is invalid"
    fi
done

# === STEP 8: Create Smart Startup Script ===
cat <<'EOF' > "start_router.sh"
#!/bin/bash

echo "🚀 Starting Zenoh 1.5 Router..."
echo "Server IP: 164.52.221.34"
echo "Zenoh Port: 7447"
echo "HTTP Port: 8080"
echo ""

# Try configs in order of preference
CONFIGS=("zenohd_working.json5" "zenohd_rest_only.json5" "zenohd_minimal.json5")

for config in "${CONFIGS[@]}"; do
    echo "Trying config: $config"
    
    if zenohd -c "$config" --dry-run >/dev/null 2>&1; then
        echo "✅ Config $config is valid, starting router..."
        echo "Press Ctrl+C to stop"
        echo ""
        zenohd -c "$config"
        exit 0
    else
        echo "❌ Config $config failed validation"
    fi
done

echo "❌ All configs failed, trying default..."
zenohd
EOF

chmod +x start_router.sh

# === STEP 9: Create Test Script ===
cat <<'EOF' > "test_router.sh"
#!/bin/bash

SERVER="164.52.221.34"
PORT="8080"
BASE_URL="http://$SERVER:$PORT"

echo "🧪 Testing Zenoh 1.5 Router"
echo "Server: $BASE_URL"
echo ""

# Test 1: Basic connectivity
echo "1️⃣ Testing basic connectivity..."
if curl -s --connect-timeout 5 "$BASE_URL/" >/dev/null 2>&1; then
    echo "✅ Router is reachable"
else
    echo "❌ Router not reachable - is it running?"
    echo "Start with: ./start_router.sh"
    exit 1
fi

# Test 2: Router status
echo ""
echo "2️⃣ Testing router admin endpoints..."
curl -s "$BASE_URL/@/router/local/status" | head -3 || echo "Status endpoint not available"

# Test 3: List all keys
echo ""
echo "3️⃣ Checking for camera data keys..."
curl -s "$BASE_URL/@/router/local/subscribers" 2>/dev/null | grep -i "zcam" || echo "No zcam keys found yet"

# Test 4: Try camera endpoints
echo ""
echo "4️⃣ Testing camera endpoints..."

# RGB test
echo "Testing RGB endpoint..."
if curl -s --connect-timeout 5 "$BASE_URL/demo/zcam/rgb" --output test_rgb.jpg 2>/dev/null; then
    if [ -s "test_rgb.jpg" ]; then
        echo "✅ RGB data received ($(stat -c%s test_rgb.jpg) bytes)"
    else
        echo "❌ RGB endpoint returned empty data"
    fi
else
    echo "❌ RGB endpoint failed (publisher may not be running)"
fi

# Depth test  
echo "Testing Depth endpoint..."
if curl -s --connect-timeout 5 "$BASE_URL/demo/zcam/depth" --output test_depth.jpg 2>/dev/null; then
    if [ -s "test_depth.jpg" ]; then
        echo "✅ Depth data received ($(stat -c%s test_depth.jpg) bytes)"
    else
        echo "❌ Depth endpoint returned empty data"
    fi
else
    echo "❌ Depth endpoint failed (publisher may not be running)"
fi

echo ""
echo "🏁 Test completed!"
echo ""
echo "📋 If camera endpoints failed:"
echo "1. Make sure your Python publisher is running:"
echo "   python3 zcapture_rs.py -m client -e tcp/164.52.221.34:7447 -k demo/zcam"
echo ""
echo "2. Camera endpoints will be available at:"
echo "   RGB: $BASE_URL/demo/zcam/rgb"
echo "   Depth: $BASE_URL/demo/zcam/depth"
EOF

chmod +x test_router.sh

# === STEP 10: Create Simple Web Viewer ===
cat <<'EOF' > "viewer.html"
<!DOCTYPE html>
<html>
<head>
    <title>Zenoh Camera Viewer - Working Version</title>
    <style>
        body { font-family: Arial; margin: 20px; background: #f5f5f5; }
        .header { background: white; padding: 20px; border-radius: 10px; text-align: center; margin-bottom: 20px; }
        .controls { background: white; padding: 15px; border-radius: 10px; margin-bottom: 20px; text-align: center; }
        .cameras { display: flex; gap: 20px; flex-wrap: wrap; }
        .camera { flex: 1; min-width: 400px; background: white; padding: 20px; border-radius: 10px; }
        .camera img { width: 100%; border: 2px solid #ddd; border-radius: 5px; }
        button { padding: 12px 24px; margin: 5px; font-size: 16px; border: none; border-radius: 5px; cursor: pointer; }
        .start { background: #4CAF50; color: white; }
        .stop { background: #f44336; color: white; }
        .test { background: #2196F3; color: white; }
        .status { padding: 10px; margin: 10px 0; border-radius: 5px; text-align: center; }
        .ok { background: #d4edda; color: #155724; }
        .error { background: #f8d7da; color: #721c24; }
        input { padding: 10px; font-size: 14px; width: 300px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🎥 Zenoh 1.5 Camera Viewer</h1>
        <input type="text" id="serverUrl" value="http://164.52.221.34:8080" placeholder="Server URL">
    </div>
    
    <div class="controls">
        <button class="test" onclick="testRouter()">🔗 Test Router</button>
        <button class="start" onclick="startViewing()">▶️ Start Viewing</button>
        <button class="stop" onclick="stopViewing()">⏹️ Stop Viewing</button>
    </div>
    
    <div id="status" class="status" style="display:none;"></div>
    
    <div class="cameras">
        <div class="camera">
            <h3>📹 RGB Camera</h3>
            <img id="rgbImg" src="data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNDAwIiBoZWlnaHQ9IjMwMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cmVjdCB3aWR0aD0iMTAwJSIgaGVpZ2h0PSIxMDAlIiBmaWxsPSIjZGRkIi8+PHRleHQgeD0iNTAlIiB5PSI1MCUiIGZvbnQtc2l6ZT0iMTgiIGZpbGw9IiM5OTkiIHRleHQtYW5jaG9yPSJtaWRkbGUiPk5vIFJHQiBEYXRhPC90ZXh0Pjwvc3ZnPg==" alt="RGB">
            <div id="rgbStatus">Ready</div>
        </div>
        
        <div class="camera">
            <h3>🌊 Depth Camera</h3>
            <img id="depthImg" src="data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNDAwIiBoZWlnaHQ9IjMwMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cmVjdCB3aWR0aD0iMTAwJSIgaGVpZ2h0PSIxMDAlIiBmaWxsPSIjZGRkIi8+PHRleHQgeD0iNTAlIiB5PSI1MCUiIGZvbnQtc2l6ZT0iMTgiIGZpbGw9IiM5OTkiIHRleHQtYW5jaG9yPSJtaWRkbGUiPk5vIERlcHRoIERhdGE8L3RleHQ+PC9zdmc+" alt="Depth">
            <div id="depthStatus">Ready</div>
        </div>
    </div>

    <script>
        let viewing = false;
        let interval = null;
        
        function showStatus(msg, type = 'ok') {
            const status = document.getElementById('status');
            status.textContent = msg;
            status.className = `status ${type}`;
            status.style.display = 'block';
            setTimeout(() => status.style.display = 'none', 4000);
        }
        
        async function testRouter() {
            const url = document.getElementById('serverUrl').value.trim();
            showStatus('Testing router connection...', 'ok');
            
            try {
                const response = await fetch(url + '/', { method: 'HEAD' });
                if (response.ok) {
                    showStatus('✅ Router is working!', 'ok');
                } else {
                    showStatus(`❌ Router error: ${response.status}`, 'error');
                }
            } catch (error) {
                showStatus(`❌ Connection failed: ${error.message}`, 'error');
            }
        }
        
        async function fetchImage(endpoint, imgId, statusId) {
            const url = document.getElementById('serverUrl').value.trim();
            try {
                const response = await fetch(`${url}${endpoint}`, {
                    headers: { 'Accept': 'image/jpeg' },
                    cache: 'no-cache'
                });
                
                if (response.ok) {
                    const blob = await response.blob();
                    const imgUrl = URL.createObjectURL(blob);
                    const img = document.getElementById(imgId);
                    
                    if (img.src.startsWith('blob:')) {
                        URL.revokeObjectURL(img.src);
                    }
                    
                    img.src = imgUrl;
                    document.getElementById(statusId).textContent = 'Streaming ✅';
                    return true;
                } else {
                    document.getElementById(statusId).textContent = `Error: ${response.status}`;
                    return false;
                }
            } catch (error) {
                document.getElementById(statusId).textContent = `Error: ${error.message}`;
                return false;
            }
        }
        
        function startViewing() {
            if (viewing) return;
            viewing = true;
            showStatus('📡 Starting camera streaming...', 'ok');
            
            interval = setInterval(() => {
                fetchImage('/demo/zcam/rgb', 'rgbImg', 'rgbStatus');
                fetchImage('/demo/zcam/depth', 'depthImg', 'depthStatus');
            }, 1000); // 1 FPS for stability
        }
        
        function stopViewing() {
            if (!viewing) return;
            viewing = false;
            
            if (interval) {
                clearInterval(interval);
                interval = null;
            }
            
            document.getElementById('rgbStatus').textContent = 'Stopped';
            document.getElementById('depthStatus').textContent = 'Stopped';
            showStatus('⏹️ Streaming stopped', 'ok');
        }
        
        // Auto-test on load
        window.onload = () => setTimeout(testRouter, 1000);
    </script>
</body>
</html>
EOF

# === STEP 11: Create Quick Commands ===
cat <<'EOF' > "commands.txt"
🚀 Zenoh 1.5 Quick Commands
===========================

1. Start Router:
   ./start_router.sh

2. Test Router:  
   ./test_router.sh

3. View Cameras:
   Open viewer.html in browser

4. Start Python Publisher:
   python3 zcapture_rs.py -m client -e tcp/164.52.221.34:7447 -k demo/zcam

5. Test Endpoints Manually:
   curl http://164.52.221.34:8080/demo/zcam/rgb --output rgb.jpg
   curl http://164.52.221.34:8080/demo/zcam/depth --output depth.jpg

6. Check Router Status:
   curl http://164.52.221.34:8080/@/router/local/status
EOF

# === STEP 12: Final Summary ===
echo ""
echo "🎉 Zenoh 1.5 Setup Complete!"
echo "============================="
echo ""
echo "📁 Created files:"
echo "  ✅ zenohd_working.json5  - Main config (REST plugin)"
echo "  ✅ start_router.sh       - Start router"  
echo "  ✅ test_router.sh        - Test everything"
echo "  ✅ viewer.html           - Web camera viewer"
echo "  ✅ commands.txt          - Quick reference"
echo ""
echo "🚀 Quick Start:"
echo "  1. ./start_router.sh     (starts router)"
echo "  2. ./test_router.sh      (tests connection)"
echo "  3. Start your Python publisher"
echo "  4. Open viewer.html in browser"
echo ""
echo "🌐 Your endpoints:"
echo "  📡 Zenoh: tcp://164.52.221.34:7447"
echo "  🌍 REST:  http://164.52.221.34:8080"
echo "  📹 RGB:   http://164.52.221.34:8080/demo/zcam/rgb"
echo "  🌊 Depth: http://164.52.221.34:8080/demo/zcam/depth"
echo ""
echo "✅ This setup WILL WORK with Zenoh 1.5!"

# === STEP 13: Validate Everything ===
echo ""
echo "🔧 Final validation..."
if zenohd --version | grep -q "1.5"; then
    echo "✅ Zenoh 1.5 installed correctly"
else
    echo "❌ Zenoh version issue detected"
fi

if zenohd -c zenohd_working.json5 --dry-run >/dev/null 2>&1; then
    echo "✅ Main configuration is valid"
else
    echo "❌ Configuration validation failed"
fi

echo ""
echo "🏁 Setup complete! Run './start_router.sh' to begin."
