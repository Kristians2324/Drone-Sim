#!/usr/bin/env sh
set -e

if [ "$#" -eq 0 ]; then
  set -- godot --headless --path /workspace
fi

exec "$@"