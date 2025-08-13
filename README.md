
 
 bash -lc "source /home/ubuntu/unitree_g1_vibes/.venv_rl/bin/activate && fuser -k 8080/tcp 2>/dev/null || true && python3 /home/ubuntu/unitree_g1_vibes/RL-shenanigans/g1_arm_web_controller.py --robot --iface eth0 --host 0.0.0.0 --port 8080 --model /home/ubuntu/unitree_g1_vibes/RL-shenanigans/models/ppo_g1_left_53178k.zip"
 
 
 
 1890  python3 zcapture_cloud.py -m peer -e tcp/164.52.221.34:7447 -k demo/cams/0 &
