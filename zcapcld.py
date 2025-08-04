import zenoh
import cv2
import numpy as np
import pyrealsense2 as rs
import argparse
import json
import time

# Argument settings
parser = argparse.ArgumentParser(
    prog='zrs_capture_cloud',
    description='Zenoh RealSense RGB capture for cloud streaming')
parser.add_argument('-m', '--mode', type=str, choices=['peer', 'client'],
                    help='The zenoh session mode.')
parser.add_argument('-e', '--connect', type=str, metavar='ENDPOINT', action='append',
                    help='Zenoh endpoints to connect to.')
parser.add_argument('-l', '--listen', type=str, metavar='ENDPOINT', action='append',
                    help='Zenoh endpoints to listen on.')
parser.add_argument('-k', '--key', type=str, default='demo/cams/0',
                    help='Key expression')
parser.add_argument('-c', '--config', type=str, metavar='FILE',
                    help='A Zenoh configuration file.')
args = parser.parse_args()

# Zenoh configuration for cloud connection
conf = zenoh.Config()

# Use peer mode to connect to cloud router
conf.insert_json5("mode", json.dumps("peer"))

# Connect to cloud router
if args.connect is not None:
    if len(args.connect) == 1:
        conf.insert_json5("connect", json.dumps({"endpoints": [args.connect[0]]}))
    else:
        conf.insert_json5("connect", json.dumps({"endpoints": args.connect}))

print(f"[INFO] Connecting to cloud Zenoh router: {args.connect}")

z = zenoh.open(conf)

# RealSense pipeline configuration - RGB only
pipeline = rs.pipeline()
config = rs.config()
config.enable_stream(rs.stream.color, 640, 480, rs.format.bgr8, 30)  # RGB only

pipeline.start(config)

print("[INFO] Open RealSense camera for cloud streaming...")

# Publish frames to Zenoh
def publish_frames():
    frame_count = 0
    while True:
        try:
            # Wait for frames
            frames = pipeline.wait_for_frames()
            color_frame = frames.get_color_frame()

            if not color_frame:
                print("[WARNING] No color frame received")
                continue

            # Get RGB image
            rgb_image = np.asanyarray(color_frame.get_data())
            
            # Encode as JPEG
            encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), 80]
            _, jpeg_data = cv2.imencode('.jpg', rgb_image, encode_param)
            
            # Publish RGB data to cloud
            key = args.key + "/rgb"
            z.put(key, jpeg_data.tobytes())
            
            frame_count += 1
            if frame_count % 30 == 0:  # Log every 30 frames
                print(f"[INFO] Published {frame_count} RGB frames to cloud at {key}")
            
            time.sleep(0.033)  # ~30 FPS
            
        except Exception as e:
            print(f"[ERROR] Exception in publish_frames: {e}")
            time.sleep(1)

# Send frames
try:
    publish_frames()
except KeyboardInterrupt:
    print("[INFO] Stopping camera capture...")
finally:
    pipeline.stop()
    z.close() 
