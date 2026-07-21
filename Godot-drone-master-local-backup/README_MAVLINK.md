# MAVLink / ArduPilot Bridge

This project now includes a heartbeat-driven UDP bridge for connecting the Godot drone simulation to an external MAVLink/ArduPilot companion app.

## What it does

- Waits for a heartbeat from your companion bridge before marking the link active
- Emits telemetry over UDP as JSON after the link is active
- Keeps the existing manual drone controls available when the bridge is disabled

## Current bridge behavior

- `scripts/MavlinkBridge.gd` listens on a UDP port and watches for heartbeat packets
- `scripts/DroneControllerManager.gd` can enable the bridge with exported settings
- Incoming payload example:

```json
{"heartbeat":true,"sysid":1,"compid":1}
```

## Setup in Godot

1. Select `DroneControllerManager` in the main scene.
2. Enable `use_mavlink_bridge`.
3. Set:
   - `mavlink_listen_port` to the UDP port your external app sends to
   - `mavlink_remote_host` to the host receiving telemetry
   - `mavlink_remote_port` to the telemetry port

## External app integration

Your external MAVLink folder can translate between real MAVLink packets and the Godot-side bridge used here.

Recommended pattern:

- Godot simulation handles the drone physics
- External app converts MAVLink ↔ local bridge messages
- ArduPilot/SITL or mission-control software talks to the external app

## Notes

This is still a bridge scaffold, not a full MAVLink binary packet encoder/decoder inside Godot yet. The current version is designed to fit a Python `bridge.py` process that waits for heartbeat and then relays MAVLink traffic.