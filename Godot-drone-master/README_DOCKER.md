# Dockerized Drone Project Bundle

This folder is set up as a single handoff package for your drone project.
It keeps the simulator and its supporting tools together so someone else can
review the whole thing in one place.

## Included parts

- `Drone Sim/` - the Godot drone simulation project
- `MavLink/` - contains `MavLink-Bridge`, the Python bridge service
- `Mission Planner/` - included as part of the full project bundle for review

## Docker services

- `drone-sim` - runs the Godot project container
- `mavlink-bridge` - runs the Python MAVLink bridge container
- `mission-planner` - included as a Windows-only profile because it is a Windows app folder

## How to run

From the parent `Documents` folder:

```bash
cd "C:\Users\USER\Documents"
docker compose -f "Drone Sim\docker-compose.yml" up --build
```

## How to verify it on another laptop

1. Copy the whole parent `Documents` folder content so these folders stay together on the other laptop:
   - `Drone Sim/`
   - `MavLink/`
   - `Mission Planner/`
2. Install Docker Desktop on the other laptop.
3. Open a terminal in the new laptop's `Documents` folder.
4. Run:

```bash
docker compose -f "Drone Sim\docker-compose.yml" up --build
```
5. If the containers start without path errors, the package is wired correctly.
6. If you want to prove the code is present, open the folders and confirm the files are still there after the copy.

## Best way to move it to another laptop

You have 3 easy options:

- **USB / external drive**: copy the three folders as-is, then paste them into `Documents` on the other laptop.
- **Zip file**: zip the three folders together, transfer the zip, and extract it on the other laptop.
- **Git/GitHub**: push the project to a repository and clone it on the other laptop, then run the same Docker command.

## Important reality check

Docker can recreate the environment from the files it can already access,
but it cannot pull your local project folders onto a different laptop by
itself. So:

- If the files are **already copied** to the other laptop, the same Docker
  command will build/run the project there.
- If the files are **not copied anywhere**, Docker on the new laptop will have
  nothing to build from.

That means Docker is the **packaging and run method**, while USB/zip/Git is the
**file transfer method**.

## Important note

`Mission Planner` is not a Linux-native source project, so it cannot be fully
containerized the same way as the Godot and Python parts. In this bundle it is
kept alongside the other projects and mounted for packaging/review so the full
set of project files can be handed over together.
