
 
 bash -lc "source /home/ubuntu/unitree_g1_vibes/.venv_rl/bin/activate && fuser -k 8080/tcp 2>/dev/null || true && python3 /home/ubuntu/unitree_g1_vibes/RL-shenanigans/g1_arm_web_controller.py --robot --iface eth0 --host 0.0.0.0 --port 8080 --model /home/ubuntu/unitree_g1_vibes/RL-shenanigans/models/ppo_g1_left_53178k.zip"
 
 
 
 1890  python3 zcapture_cloud.py -m peer -e tcp/164.52.221.34:7447 -k demo/cams/0 &



 source /home/ubuntu/unitree_g1_vibes/.venv_rl/bin/activate
python3 /home/ubuntu/unitree_g1_vibes/RL-shenanigans/g1_arm_web_controller.py --robot --iface enp68s0f1 --domain 0 --host 0.0.0.0 --port 8080 --model models/ppo_g1_left_53178k.zip





 python3 zcapture_rs.py -e tcp/164.52.221.34:7447 -k demo/cams/0   --cam-width 640 --cam-height 480 --fps 30   --width 320 --height 180 --quality 40 --pub-fps 8 &

