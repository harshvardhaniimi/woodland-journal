#!/bin/sh
# Run the unit tests with LuaJIT (luajit, or TeX Live's luajittex --luaonly).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if command -v luajit >/dev/null 2>&1; then LUA="luajit"
elif command -v luajittex >/dev/null 2>&1; then LUA="luajittex --luaonly"
else echo "LuaJIT not found (luajit or luajittex)" >&2; exit 2; fi
status=0
for t in "$ROOT"/tests/test_*.lua; do
    $LUA "$t" "$ROOT" || status=1
done
# The installer, against fake Kobo folders.
out="$(python3 "$ROOT/tests/test_install.py" 2>&1)" || status=1
printf '%s\n' "$out" | tail -3
exit $status
