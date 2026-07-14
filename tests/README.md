# Tests

## Run the tests

Double-click:

```text
tests\run_tests.cmd
```

That launcher runs Godot in headless mode.

## Run in Docker

Build the image:

```text
docker compose build
```

Run the project in headless mode:

```text
docker compose run --rm drone-sim
```

To run a custom Godot command, append it after `docker compose run --rm drone-sim`, for example:

```text
docker compose run --rm drone-sim godot --headless --path /workspace --quit
```

## What to expect

- Godot opens in a console window
- it loads the project
- it runs whatever is configured as the test main scene
- `Exit code: 0` means success

## Current launcher path

```text
%USERPROFILE%\Desktop\R2\Godot_v4.6.2-stable_win64.exe
```
