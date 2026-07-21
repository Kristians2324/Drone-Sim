#!/usr/bin/env python3
"""Companion UDP bridge for the Godot Drone Sim.

This bridge waits for a simple heartbeat from Godot, then relays JSON
messages between Godot and a MAVLink/ArduPilot-facing endpoint.

It is intentionally lightweight so you can swap the mock payload handlers
with real pymavlink encoding/decoding later.
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
import threading
import time
from dataclasses import dataclass
from typing import Optional, Any, cast

try:
    from pymavlink import mavutil
except ImportError:
    mavutil = None

MAVUtilModule = Any
_mavutil = cast(Any, mavutil)


@dataclass
class BridgeConfig:
    godot_bind_host: str = "0.0.0.0"
    godot_bind_port: int = 14551
    godot_target_host: str = "127.0.0.1"
    godot_target_port: int = 14550
    mavlink_bind_host: str = "0.0.0.0"
    mavlink_bind_port: int = 14552
    mavlink_target_host: str = "127.0.0.1"
    mavlink_target_port: int = 14550
    heartbeat_timeout_sec: float = 3.0
    status_rate_hz: float = 10.0
    mavlink_system_id: int = 255
    mavlink_component_id: int = 190


class Bridge:
    def __init__(self, config: BridgeConfig) -> None:
        self.config = config
        self.godot_sock = self._make_udp_socket(config.godot_bind_host, config.godot_bind_port)
        self.mavlink_sock = self._make_udp_socket(config.mavlink_bind_host, config.mavlink_bind_port)
        self.running = True
        self.godot_peer: Optional[tuple[str, int]] = None
        self.mavlink_peer: Optional[tuple[str, int]] = None
        self.last_heartbeat = 0.0
        self.connected = False
        self._lock = threading.Lock()
        self._master = None

        if mavutil is None:
            raise RuntimeError("pymavlink is required. Install it with: pip install pymavlink")

        self._master = cast(Any, _mavutil.mavlink_connection(
            f"udpout:{config.mavlink_target_host}:{config.mavlink_target_port}",
            source_system=config.mavlink_system_id,
            source_component=config.mavlink_component_id,
            autoreconnect=True,
        ))

    def _make_udp_socket(self, host: str, port: int) -> socket.socket:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((host, port))
        sock.setblocking(False)
        return sock

    def start(self) -> None:
        print(f"[bridge] waiting for Godot heartbeat on UDP {self.config.godot_bind_host}:{self.config.godot_bind_port}")
        print(f"[bridge] MAVLink side listens on UDP {self.config.mavlink_bind_host}:{self.config.mavlink_bind_port}")
        self._arm_vehicle()
        threading.Thread(target=self._godot_loop, daemon=True).start()
        threading.Thread(target=self._mavlink_loop, daemon=True).start()
        self._status_loop()

    def _godot_loop(self) -> None:
        while self.running:
            try:
                data, addr = self.godot_sock.recvfrom(65535)
            except BlockingIOError:
                time.sleep(0.01)
                continue
            except OSError:
                break

            self.godot_peer = addr
            payload = self._decode_json(data)
            if not isinstance(payload, dict):
                continue

            if payload.get("heartbeat"):
                with self._lock:
                    self.last_heartbeat = time.time()
                    if not self.connected:
                        self.connected = True
                        print(f"[bridge] heartbeat received from Godot {addr}")
                continue

            self._forward_godot_input(payload)

    def _mavlink_loop(self) -> None:
        while self.running:
            try:
                data, addr = self.mavlink_sock.recvfrom(65535)
            except BlockingIOError:
                time.sleep(0.01)
                continue
            except OSError:
                break

            self.mavlink_peer = addr
            payload = self._decode_json(data)
            if payload is None:
                continue

            self._forward_to_godot(payload)

    def _status_loop(self) -> None:
        interval = 1.0 / max(self.config.status_rate_hz, 0.1)
        while self.running:
            time.sleep(interval)
            with self._lock:
                age = time.time() - self.last_heartbeat
                should_connect = age <= self.config.heartbeat_timeout_sec
                if should_connect != self.connected:
                    self.connected = should_connect
                    state = "connected" if should_connect else "disconnected"
                    print(f"[bridge] Godot link {state}")

            if self.connected and self.godot_peer:
                self._send_json(self.godot_sock, self.godot_peer, {
                    "status": "alive",
                    "connected": True,
                    "heartbeat_age": age,
                    "source": "bridge.py",
                })

    def _forward_to_mavlink(self, payload: dict) -> None:
        if not self.mavlink_peer:
            self.mavlink_peer = (self.config.mavlink_target_host, self.config.mavlink_target_port)
        self._send_json(self.mavlink_sock, self.mavlink_peer, payload)

    def _forward_godot_input(self, payload: dict) -> None:
        if payload.get("type") != "godot_input":
            return

        throttle = self._clamp(float(payload.get("throttle", 0.0)), -1.0, 1.0)
        yaw = self._clamp(float(payload.get("yaw", 0.0)), -1.0, 1.0)
        pitch = self._clamp(float(payload.get("pitch", 0.0)), -1.0, 1.0)
        roll = self._clamp(float(payload.get("roll", 0.0)), -1.0, 1.0)

        if self._master is None:
            return

        master = cast(Any, self._master)
        master.mav.rc_channels_override_send(
            self.config.mavlink_system_id,
            self.config.mavlink_component_id,
            self._axis_to_pwm(roll),
            self._axis_to_pwm(pitch),
            self._throttle_to_pwm(throttle),
            self._axis_to_pwm(yaw),
            0,
            0,
            0,
            0,
        )

    def _arm_vehicle(self) -> None:
        if self._master is None:
            return

        print(f"[bridge] sending arm command to MAVLink target {self.config.mavlink_target_host}:{self.config.mavlink_target_port}")
        master = cast(Any, self._master)
        master.mav.command_long_send(
            self.config.mavlink_system_id,
            self.config.mavlink_component_id,
            _mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
            0,
            1,
            0,
            0,
            0,
            0,
            0,
            0,
        )

        # Explicitly set a mode that will keep the SITL receptive to RC overrides.
        # Prefer STABILIZE for manual-style control, fall back to GUIDED-compatible mode ID if needed.
        mavlink_enum = _mavutil.mavlink
        mode = getattr(mavlink_enum, "MAV_MODE_FLAG_CUSTOM_MODE_ENABLED", 1)
        custom_mode = 0  # STABILIZE for ArduPilot multirotors
        master.mav.command_long_send(
            self.config.mavlink_system_id,
            self.config.mavlink_component_id,
            mavlink_enum.MAV_CMD_DO_SET_MODE,
            0,
            mode,
            custom_mode,
            0,
            0,
            0,
            0,
            0,
        )

    def _clamp(self, value: float, minimum: float, maximum: float) -> float:
        return max(minimum, min(maximum, value))

    def _axis_to_pwm(self, value: float, center_is_low: bool = False) -> int:
        value = self._clamp(value, -1.0, 1.0)
        if center_is_low:
            # Map throttle from [-1, 1] to [1000, 2000] with -1 -> 1000 and +1 -> 2000.
            # This keeps the mapping simple and compatible with standard RC override ranges.
            return int(round(1500.0 + (value * 500.0)))
        return int(round(1500.0 + (value * 500.0)))

    def _throttle_to_pwm(self, value: float) -> int:
        # Treat throttle as a true RC throttle input: neutral/low starts at 1000,
        # full climb is 2000. Values below -1 are clamped, though the Godot side
        # should already normalize to [-1, 1].
        value = self._clamp(value, -1.0, 1.0)
        normalized = (value + 1.0) * 0.5
        return int(round(1000.0 + (normalized * 1000.0)))

    def _forward_to_godot(self, payload: dict) -> None:
        if not self.godot_peer:
            self.godot_peer = (self.config.godot_target_host, self.config.godot_target_port)
        self._send_json(self.godot_sock, self.godot_peer, payload)

    def _send_json(self, sock: socket.socket, addr: tuple[str, int], payload: dict) -> None:
        try:
            sock.sendto(json.dumps(payload).encode("utf-8"), addr)
        except OSError as exc:
            print(f"[bridge] send error to {addr}: {exc}", file=sys.stderr)

    def _decode_json(self, data: bytes) -> Optional[dict]:
        try:
            obj = json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return None
        return obj if isinstance(obj, dict) else None


def parse_args() -> BridgeConfig:
    parser = argparse.ArgumentParser(description="Godot ↔ MAVLink companion bridge")
    parser.add_argument("--godot-bind-host", default="0.0.0.0")
    parser.add_argument("--godot-bind-port", type=int, default=14550)
    parser.add_argument("--godot-target-host", default="127.0.0.1")
    parser.add_argument("--godot-target-port", type=int, default=14551)
    parser.add_argument("--mavlink-bind-host", default="0.0.0.0")
    parser.add_argument("--mavlink-bind-port", type=int, default=14552)
    parser.add_argument("--mavlink-target-host", default="127.0.0.1")
    parser.add_argument("--mavlink-target-port", type=int, default=14553)
    parser.add_argument("--heartbeat-timeout-sec", type=float, default=3.0)
    parser.add_argument("--status-rate-hz", type=float, default=10.0)
    args = parser.parse_args()
    return BridgeConfig(
        godot_bind_host=args.godot_bind_host,
        godot_bind_port=args.godot_bind_port,
        godot_target_host=args.godot_target_host,
        godot_target_port=args.godot_target_port,
        mavlink_bind_host=args.mavlink_bind_host,
        mavlink_bind_port=args.mavlink_bind_port,
        mavlink_target_host=args.mavlink_target_host,
        mavlink_target_port=args.mavlink_target_port,
        heartbeat_timeout_sec=args.heartbeat_timeout_sec,
        status_rate_hz=args.status_rate_hz,
    )


def main() -> int:
    config = parse_args()
    bridge = Bridge(config)
    try:
        bridge.start()
    except KeyboardInterrupt:
        print("\n[bridge] shutting down")
        bridge.running = False
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
