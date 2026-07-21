# MavLink Bridge

This folder contains a Docker-ready MAVLink bridge that forwards telemetry to your simulator and accepts control input over UDP.

## Run locally

```bash
pip install -r requirements.txt
python Bridge.py
```

## Build Docker image

```bash
docker build -t mavlink-bridge .
```

## Run Docker container

```bash
docker run --rm -it \
  -p 14550:14550/udp \
  -p 14551:14551/udp \
  -p 14552:14552/udp \
  mavlink-bridge
```

## Notes

- The bridge listens for MAVLink on `127.0.0.1:14550` by default.
- Telemetry is forwarded to `127.0.0.1:14551` by default.
- Control JSON is received on `127.0.0.1:14552` by default.
- On Windows, if `127.0.0.1:14550` fails with `WinError 10013`, try a different port or run with `--mavlink-bind 0.0.0.0`.
- If the error still happens on `0.0.0.0`, the port is likely reserved or blocked by the OS or another process.
- The Python virtual environment is not the cause of this error; it is a UDP bind restriction at the OS/socket level.
