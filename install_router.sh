#!/bin/bash

set -e

echo "🚀 Complete Zenoh Router Setup for RealSense Camera Streaming"
echo "=============================================================="

# === STEP 1: System Updates ===
echo "🛠️ Updating package index..."
apt update -y

echo "📦 Installing required packages..."
apt install -y unzip curl wget

# === STEP 2: Download Zenoh Core ZIP ===
ZENOHPKG="zenoh-1.5.0-x86_64-unknown-linux-gnu-debian.zip"
if [ ! -f "$ZENOHPKG" ]; then
    echo "⬇️ Downloading Zenoh package..."
    wget https://download.eclipse.org/zenoh/zenoh/latest/$ZENOHPKG
fi

# === STEP 3: Unzip Core ===
if [ ! -f "zenohd_1.5.0_amd64.deb" ]; then
    echo "📦 Unzipping Zenoh packages..."
    unzip -o "$ZENOHPKG"
fi

# === STEP 4: Download Webserver Plugin ZIP ===
WEBPKG="zenoh-plugin-webserver-1.5.0-x86_64-unknown-linux-gnu-debian.zip"
if [ ! -f "$WEBPKG" ]; then
    echo "⬇️ Downloading Webserver plugin..."
    wget https://download.eclipse.org/zenoh/zenoh-plugin-webserver/1.5.0/$WEBPKG
fi

# === STEP 5: Unzip Webserver Plugin ===
if [ ! -f "zenoh-plugin-webserver_1.5.0_amd64.deb" ]; then
    echo "📦 Unzipping Webserver plugin..."
    unzip -o "$WEBPKG"
fi

# === STEP 6: Install All .deb Packages ===
echo "📥 Installing Zenoh components..."
dpkg -i zenoh_1.5.0_amd64.deb || true
dpkg -i zenohd_1.5.0_amd64.deb || true
dpkg -i zenoh-plugin-rest_1.5.0_amd64.deb || true
dpkg -i zenoh-plugin-storage-manager_1.5.0_amd64.deb || true
dpkg -i zenoh-plugin-webserver_1.5.0_amd64.deb || true

echo "🔧 Fixing missing dependencies..."
apt --fix-broken install -y

# === STEP 7: Create Fixed zenohd.json5 Config ===
CONFIG_FILE="zenohd.json5"
echo "📝 Creating fixed zenohd.json5 config..."
cat <<'EOF' > "$CONFIG_FILE"
{
  // Basic router configuration
  "mode": "router",
  
  // Network configuration
  "listen": {
    "endpoints": [
      "tcp/0.0.0.0:7447"
    ]
  },
  
  // Plugins configuration
  "plugins": {
    // REST API plugin (optional)
    "rest": {
      "http_port": 8000
    },
    
    // Storage manager plugin (optional)  
    "storage_manager": {
      "storages": {}
    },
    
    // Webserver plugin (main one we need)
    "webserver": {
      "http_port": 8080,
      "http_interface": "0.0.0.0",
      "cors": {
        "allow_origin": "*",
        "allow_headers": "*",
        "allow_methods": "GET,POST,PUT,DELETE,OPTIONS"
      }
    }
  }
}
EOF

# === STEP 8: Create Alternative Simple Config ===
SIMPLE_CONFIG="zenohd_simple.json5"
echo "📝 Creating alternative simple config..."
cat <<'EOF' > "$SIMPLE_CONFIG"
{
  "plugins": {
    "webserver": {}
  }
}
EOF

# === STEP 9: Create REST-based Config (Alternative approach) ===
REST_CONFIG="zenohd_rest.json5"
echo "📝 Creating REST-based config..."
cat <<'EOF' > "$REST_CONFIG"
{
  "plugins": {
    "rest": {
      "http_port": 8080
    }
  }
}
EOF

# === STEP 10: Create HTML Frontend ===
echo "📝 Creating HTML frontend..."
cat <<'EOF' > "camera_viewer.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Zenoh RealSense Camera Viewer</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: white;
        }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        .header {
            text-align: center; margin-bottom: 30px;
            background: rgba(255, 255, 255, 0.1);
            padding: 20px; border-radius: 15px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        .controls {
            background: rgba(255, 255, 255, 0.1);
            padding: 20px; border-radius: 15px; margin-bottom: 20px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        .control-group {
            display: flex; align-items: center; gap: 15px;
            margin-bottom: 15px; flex-wrap: wrap;
        }
        .btn {
            padding: 10px 20px; border: none; border-radius: 8px;
            cursor: pointer; font-weight: 600; font-size: 14px;
            transition: all 0.3s ease; margin: 5px;
        }
        .btn-primary { background: linear-gradient(45deg, #4CAF50, #45a049); color: white; }
        .btn-secondary { background: linear-gradient(45deg, #2196F3, #1976D2); color: white; }
        .btn-danger { background: linear-gradient(45deg, #f44336, #d32f2f); color: white; }
        .btn:hover { transform: translateY(-2px); box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2); }
        .camera-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(600px, 1fr));
            gap: 20px; margin-top: 20px;
        }
        .camera-feed {
            background: rgba(255, 255, 255, 0.1);
            border-radius: 15px; padding: 20px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        .camera-container {
            position: relative; background: #000;
            border-radius: 10px; overflow: hidden;
            aspect-ratio: 4/3; display: flex;
            align-items: center; justify-content: center;
        }
        .camera-image {
            max-width: 100%; max-height: 100%;
            object-fit: contain; border-radius: 10px;
        }
        .status { padding: 10px; margin: 10px 0; border-radius: 8px; }
        .status.connected { background: rgba(76, 175, 80, 0.2); color: #4caf50; }
        .status.error { background: rgba(244, 67, 54, 0.2); color: #f44336; }
        input { padding: 8px 12px; border: none; border-radius: 8px; background: rgba(255, 255, 255, 0.9); color: #333; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎥 Zenoh RealSense Camera Viewer</h1>
            <p>Real-time RGB and Depth camera streaming</p>
        </div>

        <div class="controls">
            <div class="control-group">
                <label>Server URL:</label>
                <input type="text" id="serverUrl" value="http://164.52.221.34:8080" style="width: 300px;">
                <button class="btn btn-primary" onclick="testConnection()">🔗 Test Connection</button>
            </div>
            
            <div class="control-group">
                <button class="btn btn-primary" onclick="startStreaming()">▶️ Start Streaming</button>
                <button class="btn btn-danger" onclick="stopStreaming()">⏹️ Stop Streaming</button>
                <button class="btn btn-secondary" onclick="testEndpoints()">🧪 Test Endpoints</button>
            </div>

            <div id="status" class="status" style="display: none;"></div>
        </div>

        <div class="camera-grid">
            <div class="camera-feed">
                <h3>📹 RGB Camera</h3>
                <div class="camera-container">
                    <img id="rgbImage" class="camera-image" style="display: none;">
                    <div id="rgbPlaceholder">Click "Test Endpoints" first</div>
                </div>
            </div>

            <div class="camera-feed">
                <h3>🌊 Depth Camera</h3>
                <div class="camera-container">
                    <img id="depthImage" class="camera-image" style="display: none;">
                    <div id="depthPlaceholder">Click "Test Endpoints" first</div>
                </div>
            </div>
        </div>
    </div>

    <script>
        let isStreaming = false;
        let streamInterval = null;

        function updateStatus(message, type = 'connected') {
            const status = document.getElementById('status');
            status.textContent = message;
            status.className = `status ${type}`;
            status.style.display = 'block';
        }

        async function testConnection() {
            const serverUrl = document.getElementById('serverUrl').value.trim();
            updateStatus('Testing connection...', 'connecting');
            
            try {
                const response = await fetch(`${serverUrl}/`, { method: 'GET' });
                if (response.ok) {
                    updateStatus('✅ Server is reachable!', 'connected');
                } else {
                    updateStatus(`❌ Server responded with: ${response.status}`, 'error');
                }
            } catch (error) {
                updateStatus(`❌ Connection failed: ${error.message}`, 'error');
            }
        }

        async function testEndpoints() {
            const serverUrl = document.getElementById('serverUrl').value.trim();
            updateStatus('Testing camera endpoints...', 'connecting');
            
            // Test REST API endpoints
            const endpoints = [
                '/demo/zcam/rgb',
                '/demo/zcam/depth',
                '/@/router/local/config', // Admin endpoint
                '/@/router/local/status'   // Status endpoint
            ];
            
            for (const endpoint of endpoints) {
                try {
                    console.log(`Testing: ${serverUrl}${endpoint}`);
                    const response = await fetch(`${serverUrl}${endpoint}`, {
                        method: 'GET',
                        headers: { 'Accept': 'application/json,image/jpeg,*/*' }
                    });
                    
                    console.log(`${endpoint}: ${response.status} ${response.statusText}`);
                    
                    if (response.ok && endpoint.includes('rgb')) {
                        const blob = await response.blob();
                        const url = URL.createObjectURL(blob);
                        document.getElementById('rgbImage').src = url;
                        document.getElementById('rgbImage').style.display = 'block';
                    }
                    
                    if (response.ok && endpoint.includes('depth')) {
                        const blob = await response.blob();
                        const url = URL.createObjectURL(blob);
                        document.getElementById('depthImage').src = url;
                        document.getElementById('depthImage').style.display = 'block';
                    }
                } catch (error) {
                    console.error(`Error testing ${endpoint}:`, error);
                }
            }
            
            updateStatus('✅ Check browser console for endpoint test results', 'connected');
        }

        async function fetchCameraImage(endpoint, imageId) {
            const serverUrl = document.getElementById('serverUrl').value.trim();
            try {
                const response = await fetch(`${serverUrl}${endpoint}`, {
                    method: 'GET',
                    headers: { 'Accept': 'image/jpeg' },
                    cache: 'no-cache'
                });
                
                if (response.ok) {
                    const blob = await response.blob();
                    const url = URL.createObjectURL(blob);
                    const img = document.getElementById(imageId);
                    
                    // Clean up previous URL
                    if (img.src.startsWith('blob:')) {
                        URL.revokeObjectURL(img.src);
                    }
                    
                    img.src = url;
                    img.style.display = 'block';
                    return true;
                }
            } catch (error) {
                console.error(`Error fetching ${endpoint}:`, error);
            }
            return false;
        }

        function startStreaming() {
            if (isStreaming) return;
            
            isStreaming = true;
            updateStatus('🔄 Starting stream...', 'connected');
            
            streamInterval = setInterval(async () => {
                await Promise.all([
                    fetchCameraImage('/demo/zcam/rgb', 'rgbImage'),
                    fetchCameraImage('/demo/zcam/depth', 'depthImage')
                ]);
            }, 200); // 5 FPS
            
            updateStatus('🎥 Streaming active', 'connected');
        }

        function stopStreaming() {
            if (!isStreaming) return;
            
            isStreaming = false;
            if (streamInterval) {
                clearInterval(streamInterval);
                streamInterval = null;
            }
            
            updateStatus('⏹️ Streaming stopped', 'connected');
        }

        // Auto-test connection on load
        window.addEventListener('load', () => {
            setTimeout(testConnection, 1000);
        });
    </script>
</body>
</html>
EOF

# === STEP 11: Create Test Scripts ===
echo "📝 Creating test scripts..."

# Test script for REST API
cat <<'EOF' > "test_rest.sh"
#!/bin/bash
echo "🧪 Testing REST API endpoints..."
SERVER="http://164.52.221.34:8080"

echo "Testing server status..."
curl -v "$SERVER/" 2>&1 | head -20

echo -e "\nTesting admin endpoint..."
curl -v "$SERVER/@/router/local/status" 2>&1 | head -10

echo -e "\nTesting camera endpoints..."
curl -v "$SERVER/demo/zcam/rgb" --output test_rgb.jpg 2>&1 | head -10
curl -v "$SERVER/demo/zcam/depth" --output test_depth.jpg 2>&1 | head -10

echo -e "\nDone! Check test_rgb.jpg and test_depth.jpg if downloaded successfully."
EOF

chmod +x test_rest.sh

# === STEP 12: Create Startup Script ===
cat <<'EOF' > "start_zenoh.sh"
#!/bin/bash

echo "🚀 Starting Zenoh Router with multiple configuration attempts..."

# Try configuration 1: Full webserver config
echo "Attempt 1: Using full webserver configuration..."
timeout 10s zenohd -c zenohd.json5 &
PID1=$!
sleep 5
if kill -0 $PID1 2>/dev/null; then
    echo "✅ Success with full webserver config!"
    wait $PID1
    exit 0
else
    echo "❌ Failed with full webserver config"
    kill $PID1 2>/dev/null || true
fi

# Try configuration 2: Simple webserver config
echo "Attempt 2: Using simple webserver configuration..."
timeout 10s zenohd -c zenohd_simple.json5 &
PID2=$!
sleep 5
if kill -0 $PID2 2>/dev/null; then
    echo "✅ Success with simple webserver config!"
    wait $PID2
    exit 0
else
    echo "❌ Failed with simple webserver config"
    kill $PID2 2>/dev/null || true
fi

# Try configuration 3: REST-only config
echo "Attempt 3: Using REST-only configuration..."
timeout 10s zenohd -c zenohd_rest.json5 &
PID3=$!
sleep 5
if kill -0 $PID3 2>/dev/null; then
    echo "✅ Success with REST-only config!"
    echo "📝 Note: Using REST API at port 8080 instead of webserver plugin"
    wait $PID3
    exit 0
else
    echo "❌ Failed with REST-only config"
    kill $PID3 2>/dev/null || true
fi

# Try configuration 4: Default config
echo "Attempt 4: Using default configuration..."
zenohd

EOF

chmod +x start_zenoh.sh

# === STEP 13: Final Instructions ===
echo ""
echo "🎉 Setup Complete!"
echo "=================="
echo ""
echo "📁 Files created:"
echo "  - zenohd.json5          (Main webserver config)"
echo "  - zenohd_simple.json5   (Simple webserver config)"
echo "  - zenohd_rest.json5     (REST-only config)"
echo "  - camera_viewer.html    (Web frontend)"
echo "  - start_zenoh.sh        (Smart startup script)"
echo "  - test_rest.sh          (Test script)"
echo ""
echo "🚀 To start Zenoh router:"
echo "  ./start_zenoh.sh"
echo ""
echo "🧪 To test the setup:"
echo "  ./test_rest.sh"
echo ""
echo "🌐 To view cameras:"
echo "  Open camera_viewer.html in your browser"
echo ""
echo "📋 Architecture:"
echo "  RealSense Camera → Zenoh Publisher → Zenoh Router → Web Frontend"
echo "  Port 7447: Zenoh protocol"
echo "  Port 8080: HTTP/REST API"
echo ""
echo "✅ All configurations and fallbacks are ready!"
EOF
