#!/usr/bin/env python3.10
"""g1_arm_web_controller.py – minimal web UI to steer the G-1 arm goal.

- Launches the same MuJoCo env and frozen PPO policy as `g1_arm_policy_controller.py`
- Serves a tiny HTML page with buttons to nudge the Cartesian goal (x/y/z)
- Exposes JSON endpoints for status, nudges and directly setting the goal

Usage:
    python3 g1_arm_web_controller.py --sim-only --host 0.0.0.0 --port 8080

Notes:
- Robot output is disabled by default; enable with `--iface` if you have SDK-2.
- The MuJoCo viewer opens for visual feedback. Close the browser or hit Ctrl-C to exit.
"""

from __future__ import annotations

import argparse
import json
import signal
import threading
import time
from typing import Any, Dict, Tuple

import numpy as np

# Reuse env/policy helpers and optional robot bridge
from g1_arm_policy_controller import make_env, load_policy, RobotBridge  # type: ignore


_HTML = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>G-1 Arm Web Controller</title>
  <style>
    body { font-family: sans-serif; margin: 20px; max-width: 720px; }
    h1 { font-size: 20px; }
    .row { display: flex; gap: 8px; align-items: center; margin: 8px 0; }
    .stat { padding: 8px 12px; background: #f2f2f2; border-radius: 6px; }
    button { padding: 10px 14px; font-size: 14px; cursor: pointer; }
    input[type=number] { width: 120px; padding: 6px; }
    input[type=range] { width: 240px; }
    .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; max-width: 360px; }
    .pill { border: 1px solid #ddd; border-radius: 6px; padding: 8px; }
    .ok { color: #0a7f00; }
    .warn { color: #d97706; }
    .err { color: #b91c1c; }
    .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
  </style>
</head>
<body>
  <h1>G-1 RL Reach – Web Controller</h1>
  <div class="row" style="gap:16px; align-items:center;">
    <div id="status" class="stat">Loading…</div>
    <label style="display:flex; align-items:center; gap:6px;">
      <input id="robotToggle" type="checkbox" onchange="setRobot(this.checked)">
      <span>Robot</span>
    </label>
    <button id="goBtn" onclick="goNow()">Go To Goal</button>
  </div>

  <div class="row"><strong>Step (m):</strong>
    <input id="step" type="range" min="0.005" max="0.10" step="0.005" value="0.02" oninput="stepVal.textContent=this.value" />
    <span id="stepVal" class="mono">0.02</span>
  </div>

  <div class="pill">
    <div style="margin:6px 0"><strong>Controls</strong> (W A S D)</div>
    <div class="grid">
      <button onclick="doKey('w')">W</button>
      <button onclick="doKey('a')">A</button>
      <button onclick="doKey('s')">S</button>
      <button onclick="doKey('d')">D</button>
    </div>
    <div class="row"><small>Tip: press W/A/S/D on your keyboard to jog the goal.</small></div>
  </div>

  <div class="pill" style="margin-top:10px;">
    <div style="margin:6px 0"><strong>Set absolute goal</strong> (meters):</div>
    <div class="row">
      <label>x <input id="gx" type="number" step="0.001" readonly /></label>
      <label>y <input id="gy" type="number" step="0.001" readonly /></label>
      <label>z <input id="gz" type="number" step="0.001" readonly /></label>
      <button id="editBtn" onclick="toggleEdit()">Edit</button>
      <button onclick="setGoal()">Set</button>
    </div>
  </div>

  <script>
    const statusEl = document.getElementById('status');
    const stepEl = document.getElementById('step');
    const gx = document.getElementById('gx');
    const gy = document.getElementById('gy');
    const gz = document.getElementById('gz');
    let editing = false;

    function toggleEdit(){
      editing = !editing;
      [gx, gy, gz].forEach(inp => inp.readOnly = !editing);
      document.getElementById('editBtn').textContent = editing ? 'Done' : 'Edit';
      if(editing){ gx.focus(); gx.select(); }
    }

    // Keyboard support (disabled while editing fields)
    window.addEventListener('keydown', (e) => {
      if(editing) return;
      if(['w','a','s','d','W','A','S','D'].includes(e.key)) {
        e.preventDefault();
        doKey(e.key.toLowerCase());
      }
    });

    async function fetchStatus() {
      try {
        const r = await fetch('/status');
        const s = await r.json();
        statusEl.innerHTML = `Goal: <span class=\"mono\">x=${s.goal[0].toFixed(3)}  y=${s.goal[1].toFixed(3)}  z=${s.goal[2].toFixed(3)}</span> (m) &nbsp; mode: <strong>${s.mode}</strong> &nbsp; sim:<strong>${s.out_sim?'on':'off'}</strong> robot:<strong>${s.out_robot?'on':'off'}</strong> ${s.robot_ok?'':'<span class=\\'err\\'>(SDK-2 not connected)</span>'}`;
        document.getElementById('robotToggle').checked = s.out_robot;
        if(!editing){
          gx.value = s.goal[0].toFixed(3);
          gy.value = s.goal[1].toFixed(3);
          gz.value = s.goal[2].toFixed(3);
        }
      } catch (e) {
        statusEl.textContent = 'Disconnected';
        statusEl.className = 'stat err';
      }
    }

    function doKey(key){
      const map = { w: {axis:'z', sgn:+1}, s: {axis:'z', sgn:-1}, a: {axis:'y', sgn:+1}, d: {axis:'y', sgn:-1} };
      const m = map[key];
      if(!m) return;
      const step = parseFloat(stepEl.value);
      fetch('/nudge', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({axis: m.axis, delta: m.sgn*step})});
    }

    async function setGoal() {
      const x = parseFloat(gx.value); const y = parseFloat(gy.value); const z = parseFloat(gz.value);
      await fetch('/set_goal', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({x, y, z})});
      // keep user-entered values and leave edit mode
      editing = false;
      [gx, gy, gz].forEach(inp => inp.readOnly = true);
      document.getElementById('editBtn').textContent = 'Edit';
    }

    async function setRobot(enabled){
      await fetch('/set_robot', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({enabled})});
      fetchStatus();
    }

    async function goNow(){
      const x = parseFloat(gx.value); const y = parseFloat(gy.value); const z = parseFloat(gz.value);
      await fetch('/set_goal', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({x,y,z})});
      await fetch('/go', {method:'POST'});
      fetchStatus();
    }

    setInterval(fetchStatus, 500);
    fetchStatus();
  </script>
</body>
</html>
"""


class Shared:
    def __init__(self, init_goal: Tuple[float, float, float]):
        self._lock = threading.Lock()
        self.goal_xyz = np.array(init_goal, dtype=np.float32)
        self.out_sim = True
        self.out_robot = False
        self.hold_mode = False
        self.collision_freeze = False
        self.mode_text = "HOLD"
        self.stop = False
        self.manual_until = 0.0

    def with_lock(self):  # context manager for brevity
        return self._lock


def run_control_loop(env, policy, robot: RobotBridge, shared: Shared, rate_s: float) -> None:  # noqa: D401
    """Background loop: apply goal to env, run policy steps, optional robot stream."""
    import numpy as _np

    # Reset and initialise observation
    obs, _ = env.reset()

    # Clamp helper and bounds (match original script)
    low = _np.array([-0.1, -0.6, 0.4], dtype=_np.float32)
    high = _np.array([0.6, 0.6, 1.4], dtype=_np.float32)

    last_safe_qpos = None
    last_robot_send = 0.0

    while not shared.stop:
        time.sleep(max(0.005, rate_s))

        with shared.with_lock():
            p_goal = _np.clip(shared.goal_xyz, low, high)
            shared.goal_xyz[:] = p_goal
            out_sim = shared.out_sim
            out_robot = shared.out_robot and robot.ok

        # Apply new goal to env if it changed
        env.p_goal[:] = p_goal
        if getattr(env, "_goal_mid", -1) != -1:
            env.data.mocap_pos[env._goal_mid] = env.p_goal

        # 2. Decide next action (collision/hold logic mirrors original)
        collided = False
        if hasattr(env, "_arm_gids") and hasattr(env, "_protect_gids"):
            mj = getattr(env, "_mujoco", None)
            for i in range(env.data.ncon):
                c = env.data.contact[i]
                if mj is not None:
                    b1 = mj.mj_id2name(env.model, mj.mjtObj.mjOBJ_BODY, int(env.model.geom_bodyid[c.geom1]))
                    b2 = mj.mj_id2name(env.model, mj.mjtObj.mjOBJ_BODY, int(env.model.geom_bodyid[c.geom2]))
                    if (b1 and "hand" in b1) or (b2 and "hand" in b2):
                        continue
                arm_gids = env._arm_gids  # type: ignore[attr-defined]
                prot_gids = env._protect_gids  # type: ignore[attr-defined]
                if (c.geom1 in arm_gids and c.geom2 in prot_gids) or (c.geom2 in arm_gids and c.geom1 in prot_gids):
                    penetration = max(0.0, -c.dist)
                    if penetration < 0.002:
                        continue
                    collided = True
                    break

        # Update mode per distance & collisions
        dist = float(np.linalg.norm(env.p_goal - env._fk())) if hasattr(env, "_fk") else 1e9  # type: ignore[arg-type]
        if collided:
            shared.collision_freeze = True
        if shared.collision_freeze:
            shared.hold_mode = True
        else:
            if not shared.hold_mode and dist < 0.03:
                shared.hold_mode = True
            elif shared.hold_mode and dist > 0.05:
                shared.hold_mode = False
                shared.collision_freeze = False

        # If user just set a goal, force RUN for 0.5 s regardless of distance
        now = time.time()
        if now < shared.manual_until:
            shared.hold_mode = False
            shared.collision_freeze = False

        if shared.hold_mode or not (out_sim or out_robot):
            with shared.with_lock():
                obs, _, _, _, _ = env.step(_np.zeros(env.action_space.shape, dtype=_np.float32))
            env._step_count = 0  # type: ignore[attr-defined]
        else:
            action, _ = policy.predict(obs, deterministic=True)
            with shared.with_lock():
                obs, _, done, _, _info = env.step(action)
            if not collided:
                last_safe_qpos = env.data.qpos.copy()
            if done:
                with shared.with_lock():
                    obs, _ = env.reset()
                    if last_safe_qpos is not None:
                        env.data.qpos[:] = last_safe_qpos
                        env.data.qvel[:] = 0.0
                        env._mujoco.mj_forward(env.model, env.data)  # type: ignore[attr-defined]
                env.p_goal[:] = p_goal
                if getattr(env, "_goal_mid", -1) != -1:
                    env.data.mocap_pos[env._goal_mid] = env.p_goal

        # Optional robot streaming (≤50 Hz)
        now = time.time()
        if out_robot and robot.ok and (now - last_robot_send) > 0.02:
            # Lazy map motor index → qpos adr cache
            if not hasattr(env, "_motor_qadr"):
                import mujoco as _mj
                qadr: Dict[int, int] = {}
                # Left 15..21, Right 22..28 per original mapping
                names = [
                    "left_shoulder_pitch_joint",
                    "left_shoulder_roll_joint",
                    "left_shoulder_yaw_joint",
                    "left_elbow_joint",
                    "left_wrist_roll_joint",
                    "left_wrist_pitch_joint",
                    "left_wrist_yaw_joint",
                    "right_shoulder_pitch_joint",
                    "right_shoulder_roll_joint",
                    "right_shoulder_yaw_joint",
                    "right_elbow_joint",
                    "right_wrist_roll_joint",
                    "right_wrist_pitch_joint",
                    "right_wrist_yaw_joint",
                ]
                indices = list(range(15, 22)) + list(range(22, 29))
                for idx, nm in zip(indices, names):
                    jid = _mj.mj_name2id(env.model, _mj.mjtObj.mjOBJ_JOINT, nm)
                    if jid != -1:
                        qadr[idx] = int(env.model.jnt_qposadr[jid])
                env._motor_qadr = qadr  # type: ignore[attr-defined]
            qpos = {idx: float(env.data.qpos[adr]) for idx, adr in env._motor_qadr.items()}  # type: ignore[attr-defined]
            robot.send_qpos(qpos)
            last_robot_send = now

        # Update UI text
        shared.mode_text = "HOLD" if shared.hold_mode else ("COLL" if shared.collision_freeze else "RUN ")


def main() -> None:  # noqa: D401
    ap = argparse.ArgumentParser(description="Web UI for G-1 RL reach controller")
    ap.add_argument("--model", default="models/ppo_g1_left_53178k.zip", help="Path to trained .zip model")
    ap.add_argument("--right-arm", action="store_true", help="Use RIGHT arm policy")
    ap.add_argument("--iface", default="", help="DDS network interface (robot)")
    ap.add_argument("--domain", type=int, default=0, help="DDS domain ID")
    ap.add_argument("--rate", type=float, default=0.04, help="Control loop dt (s)")
    ap.add_argument("--host", default="0.0.0.0", help="HTTP host")
    ap.add_argument("--port", type=int, default=8080, help="HTTP port")
    ap.add_argument("--sim-only", action="store_true", help="Disable robot output entirely")
    ap.add_argument("--robot", action="store_true", help="Enable robot streaming (requires unitree_sdk2py)")

    args = ap.parse_args()

    # 1) Load policy & env
    import pathlib

    script_dir = pathlib.Path(__file__).resolve().parent
    raw_path = pathlib.Path(args.model).expanduser()
    model_path = raw_path if raw_path.is_absolute() else (script_dir / raw_path)
    if not model_path.exists():
        raise SystemExit(
            f"Model file not found: {model_path}\n"
            f"Hint: pass --model /full/path/to/ppo.zip or place it under {script_dir/'models'}"
        )

    policy = load_policy(model_path)
    env = make_env(render=True, right_arm=args.right_arm)

    # Start with goal at current wrist position
    if hasattr(env, "_fk"):
        p0 = tuple(np.asarray(env._fk(), dtype=np.float32))  # type: ignore[attr-defined]
    else:
        p0 = (0.2, 0.0, 0.8)

    robot = RobotBridge(args.iface, args.domain) if (args.robot and not args.sim_only) else RobotBridge("", 0)
    shared = Shared(init_goal=p0)
    shared.out_robot = bool(args.robot and robot.ok)


    # 2) Background control loop
    ctrl_thread = threading.Thread(target=run_control_loop, args=(env, policy, robot, shared, args.rate), daemon=True)
    ctrl_thread.start()

    # --- Automatically run poses on startup ---
    def run_poses_on_startup():
        poses = [
            {"x": 0.297, "y": 0.152, "z": 0.888},      #Intial Position
            {"x": 0.297, "y": 0.172, "z": 0.988},      
            {"x": 0.297, "y": 0.132, "z": 1.008},     #Right Move
            {"x": 0.297, "y": 0.092, "z": 1.008},     #Right Move
            {"x": 0.297, "y": 0.112, "z": 0.728},     #Picking Pose
        ]
        for pose in poses:
            print(f"[startup] Setting goal to: {pose}")
            with shared.with_lock():
                shared.goal_xyz[:] = (pose["x"], pose["y"], pose["z"])
                shared.collision_freeze = False
                shared.hold_mode = False
                shared.manual_until = time.time() + 0.5
            time.sleep(1)  # Wait 1 second between poses

    threading.Thread(target=run_poses_on_startup, daemon=True).start()

    # 3) Minimal Flask app
    from flask import Flask, request, Response

    app = Flask(__name__)

    @app.get("/")
    def root() -> Response:  # type: ignore[override]
        return Response(_HTML, mimetype="text/html")

    @app.get("/status")
    def status() -> Response:  # type: ignore[override]
        with shared.with_lock():
            data = {
                "goal": [float(shared.goal_xyz[0]), float(shared.goal_xyz[1]), float(shared.goal_xyz[2])],
                "mode": shared.mode_text,
                "out_sim": bool(shared.out_sim),
                "out_robot": bool(shared.out_robot and robot.ok),
                "robot_ok": bool(robot.ok),
            }
        return Response(json.dumps(data), mimetype="application/json")

    @app.post("/nudge")
    def nudge() -> Response:  # type: ignore[override]
        body = request.get_json(force=True) or {}
        axis = str(body.get("axis", "")).lower()
        delta = float(body.get("delta", 0.0))
        with shared.with_lock():
            if axis == "x":
                shared.goal_xyz[0] += delta
            elif axis == "y":
                shared.goal_xyz[1] += delta
            elif axis == "z":
                shared.goal_xyz[2] += delta
        return Response("{}", mimetype="application/json")

    @app.post("/set_goal")
    def set_goal() -> Response:  # type: ignore[override]
        body = request.get_json(force=True) or {}
        x = float(body.get("x", 0.0))
        y = float(body.get("y", 0.0))
        z = float(body.get("z", 0.0))
        with shared.with_lock():
            shared.goal_xyz[:] = (x, y, z)
            # Clear hold/collision flags so policy can act, and force RUN shortly
            shared.collision_freeze = False
            shared.hold_mode = False
            shared.manual_until = time.time() + 0.5
        return Response("{}", mimetype="application/json")

    @app.post("/go")
    def go() -> Response:  # type: ignore[override]
        # Explicitly trigger RUN now
        with shared.with_lock():
            shared.collision_freeze = False
            shared.hold_mode = False
        return Response("{}", mimetype="application/json")

    @app.post("/set_robot")
    def set_robot() -> Response:  # type: ignore[override]
        body = request.get_json(force=True) or {}
        enabled = bool(body.get("enabled", False))
        with shared.with_lock():
            shared.out_robot = bool(enabled and robot.ok)
        return Response(json.dumps({"out_robot": shared.out_robot, "robot_ok": robot.ok}), mimetype="application/json")

    # Graceful shutdown
    def _sigint(_sig, _frm):
        shared.stop = True
        try:
            env.close()
        except Exception:
            pass
        # give background thread a moment
        time.sleep(0.1)
        raise SystemExit(0)

    signal.signal(signal.SIGINT, _sigint)

    # 4) Serve
    print(f"[web] Serving on http://{args.host}:{args.port}  (Ctrl-C to stop)")
    app.run(host=args.host, port=args.port, threaded=True)


if __name__ == "__main__":
    main() 
