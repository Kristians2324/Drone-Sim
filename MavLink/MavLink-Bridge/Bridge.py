"""Two-way MAVLink <-> Godot bridge.

This bridge:
  1. Listens for MAVLink telemetry from ArduPilot on udpin:127.0.0.1:14550
  2. Forwards selected telemetry packets to Godot over UDP on 127.0.0.1:14551
  3. Listens for JSON control inputs from Godot on a non-blocking UDP socket
  4. Converts Godot axes (Throttle, Yaw, Pitch, Roll) from -1.0..1.0 to PWM
     values and sends RC channel overrides back to the vehicle

Usage:
  python Bridge.py --mavlink-bind 127.0.0.1 --mavlink-port 14550 --godot-host 127.0.0.1 --godot-port 14551
  python Bridge.py --control-port 14552

Install dependency:
  pip install pymavlink
"""

from __future__ import annotations

import argparse
import json
import socket
import time
from typing import Any, Dict, Optional

from pymavlink import mavutil


DEFAULT_MAVLINK_PORT = 14550
DEFAULT_GODOT_PORT = 14551
DEFAULT_CONTROL_PORT = 14552
DEFAULT_MAVLINK_BIND = "127.0.0.1"
DEFAULT_MAVLINK_FALLBACK_BIND = "0.0.0.0"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Two-way MAVLink bridge for Godot")
    parser.add_argument(
        "--mavlink-bind",
        default=DEFAULT_MAVLINK_BIND,
        help="Local IP/interface to bind for MAVLink UDP input (use 0.0.0.0 in Docker or if localhost bind fails)",
    )
    parser.add_argument("--mavlink-port", type=int, default=DEFAULT_MAVLINK_PORT, help="UDP port to listen for MAVLink")
    parser.add_argument("--godot-host", default="127.0.0.1", help="Godot UDP host")
    parser.add_argument("--godot-port", type=int, default=DEFAULT_GODOT_PORT, help="Godot UDP port for telemetry")
    parser.add_argument(
        "--control-port",
        type=int,
        default=DEFAULT_CONTROL_PORT,
        help="UDP port to listen for Godot control JSON (use a separate port from telemetry)",
    )
    return parser.parse_args()


def connect_mavlink(bind: str, port: int) -> Any:
    """Connect to MAVLink with a Windows-safe UDP fallback.

    pymavlink's built-in ``udpin:host:port`` helper creates and binds the socket internally.
    On some Windows setups that bind can fail with WinError 10013 even when the port looks free.
    We try pymavlink first, then fall back to constructing a UDP socket ourselves and handing it
    to MAVLink if the environment supports it.
    """
    candidates = []
    for candidate in (bind, DEFAULT_MAVLINK_FALLBACK_BIND):
        if candidate not in candidates:
            candidates.append(candidate)

    last_error: Optional[BaseException] = None
    for candidate in candidates:
        try:
            print(f"Waiting for MAVLink on udpin:{candidate}:{port} ...")
            return mavutil.mavlink_connection(f"udpin:{candidate}:{port}")
        except PermissionError as exc:
            last_error = exc
            print(f"Could not bind MAVLink on {candidate}:{port}: {exc}")
        except Exception as exc:
            last_error = exc
            print(f"Could not open MAVLink on {candidate}:{port}: {exc}")

    # Final fallback: create the UDP socket ourselves and give pymavlink an already-bound socket.
    # This helps when the failure is in pymavlink's internal socket setup rather than UDP itself.
    print(f"Trying manual UDP socket bind on {DEFAULT_MAVLINK_FALLBACK_BIND}:{port} ...")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((DEFAULT_MAVLINK_FALLBACK_BIND, port))
        try:
            return mavutil.mavlink_connection("", input=True, source_system=1, source_component=1, fd=sock)
        except TypeError:
            # Older pymavlink versions may not support fd=socket directly.
            sock.close()
            raise RuntimeError(
                "pymavlink in this environment does not support passing a pre-bound socket. "
                "Please try a different MAVLink port or check whether the port is reserved by Windows."
            ) from last_error
    except Exception:
        sock.close()
        raise


def clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def axis_to_pwm(value: float) -> int:
    """Map normalized axis input (-1.0..1.0) to PWM (1000..2000)."""
    value = clamp(float(value), -1.0, 1.0)
    pwm = 1500 + (value * 500)
    return int(round(clamp(pwm, 1000, 2000)))


def parse_control_packet(data: bytes) -> Optional[Dict[str, Any]]:
    try:
        decoded = data.decode("utf-8").strip()
        if not decoded:
            return None
        payload = json.loads(decoded)
        if not isinstance(payload, dict):
            return None
        return payload
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None


def setup_vehicle(mav: Any) -> None:
    """Perform the basic arming / mode setup after heartbeat."""
    # Try to set a sensible guided/manual-capable mode before arming.
    # If the vehicle rejects a mode, we continue and still allow overrides.
    try:
        mav.set_mode_apm("GUIDED")
    except Exception:
        try:
            mav.set_mode_apm("STABILIZE")
        except Exception:
            pass

    try:
        mav.arducopter_arm()
        mav.motors_armed_wait()
    except Exception as exc:
        print(f"Warning: arming sequence failed or timed out: {exc}")


def send_rc_override(mav: Any, channels: Dict[int, int]) -> None:
    chan1 = channels.get(1, 65535)
    chan2 = channels.get(2, 65535)
    chan3 = channels.get(3, 65535)
    chan4 = channels.get(4, 65535)
    chan5 = channels.get(5, 65535)
    chan6 = channels.get(6, 65535)
    chan7 = channels.get(7, 65535)
    chan8 = channels.get(8, 65535)
    mav.mav.rc_channels_override_send(
        mav.target_system,
        mav.target_component,
        chan1,
        chan2,
        chan3,
        chan4,
        chan5,
        chan6,
        chan7,
        chan8,
    )


def safe_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def safe_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def main() -> None:
    args = parse_args()

    telemetry_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    godot_addr = (args.godot_host, args.godot_port)

    control_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    control_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    control_socket.bind(("0.0.0.0", args.control_port))
    control_socket.setblocking(False)

    mav: Any = connect_mavlink(args.mavlink_bind, args.mavlink_port)

    mav.wait_heartbeat()
    print(
        f"Connected to system {mav.target_system}, component {mav.target_component}. "
        f"Forwarding telemetry to {args.godot_host}:{args.godot_port} and controls from 0.0.0.0:{args.control_port}"
    )

    setup_vehicle(mav)

    last_status = 0.0
    last_override = 0.0
    current_channels: Dict[int, int] = {1: 1500, 2: 1500, 3: 1000, 4: 1500}

    while True:
        # Drain any inbound Godot control packets without blocking telemetry.
        while True:
            try:
                data, _addr = control_socket.recvfrom(4096)
            except BlockingIOError:
                break
            except OSError as exc:
                print(f"Control socket error: {exc}")
                break

            print(f"Raw control packet from Godot: {data!r}")

            control = parse_control_packet(data)
            if not control:
                continue

            throttle = safe_float(control.get("Throttle", 0.0))
            yaw = safe_float(control.get("Yaw", 0.0))
            pitch = safe_float(control.get("Pitch", 0.0))
            roll = safe_float(control.get("Roll", 0.0))

            current_channels[3] = axis_to_pwm(throttle)
            current_channels[4] = axis_to_pwm(yaw)
            current_channels[2] = axis_to_pwm(pitch)
            current_channels[1] = axis_to_pwm(roll)

            send_rc_override(mav, current_channels)
            last_override = time.time()

        msg = mav.recv_match(blocking=False)
        if msg is None:
            if time.time() - last_override > 0.25:
                # Keep overrides alive so the sim continues honoring the latest controls.
                send_rc_override(mav, current_channels)
                last_override = time.time()
            time.sleep(0.005)
            continue

        msg_type = msg.get_type()
        payload: Dict[str, Any] = {"type": msg_type, "timestamp": time.time()}

        if msg_type == "HEARTBEAT":
            payload.update(
                {
                    "base_mode": safe_int(getattr(msg, "base_mode", 0)),
                    "system_status": safe_int(getattr(msg, "system_status", 0)),
                }
            )
        elif msg_type == "ATTITUDE":
            payload.update(
                {
                    "roll": safe_float(getattr(msg, "roll", 0.0)),
                    "pitch": safe_float(getattr(msg, "pitch", 0.0)),
                    "yaw": safe_float(getattr(msg, "yaw", 0.0)),
                }
            )
        elif msg_type == "GLOBAL_POSITION_INT":
            payload.update(
                {
                    "lat": safe_int(getattr(msg, "lat", 0)) / 1e7,
                    "lon": safe_int(getattr(msg, "lon", 0)) / 1e7,
                    "alt": safe_int(getattr(msg, "alt", 0)) / 1000.0,
                    "relative_alt": safe_int(getattr(msg, "relative_alt", 0)) / 1000.0,
                    "vx": safe_int(getattr(msg, "vx", 0)) / 100.0,
                    "vy": safe_int(getattr(msg, "vy", 0)) / 100.0,
                    "vz": safe_int(getattr(msg, "vz", 0)) / 100.0,
                }
            )
        else:
            continue

        telemetry_socket.sendto(json.dumps(payload).encode("utf-8"), godot_addr)

        if time.time() - last_status > 2.0:
            print(f"Forwarded {msg_type}: {payload}")
            last_status = time.time()


if __name__ == "__main__":
    main()