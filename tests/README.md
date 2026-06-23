# Tests

## Run the tests

Double-click:

```text
tests\run_tests.cmd
```

That launcher runs Godot in headless mode.

## What to expect

- Godot opens in a console window
- it loads the project
- it runs whatever is configured as the test main scene
- `Exit code: 0` means success

## Godot path detection

```text
%USERPROFILE%\Desktop\godot\*.exe
```

The launcher first looks for a Godot executable in a folder named `godot`
on your Desktop. If it does not find one there, it falls back to the older
`Desktop\R2\Godot_v4.6.2-stable_win64.exe` path.
