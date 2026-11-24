#!/usr/bin/env bash
# Full verification pipeline. Requires rojo, lune, luau-lsp (and optionally
# selene) on PATH, plus python3 for the layout check.
#
#   scripts/check.sh            build + every check
#   SKIP_SIM=1 scripts/check.sh skip the ~70 s multi-round server simulation
#
# Roblox API definitions for luau-lsp: download scripts/globalTypes.None.d.luau
# from the luau-lsp repository (matching your luau-lsp version) and pass its
# path in ROBLOX_DEFS, or place it in the project root.
set -uo pipefail
cd "$(dirname "$0")/.."
DEFS="${ROBLOX_DEFS:-globalTypes.None.d.luau}"
status=0
step() { printf '\n== %s\n' "$1"; }

step "generate map (lune run map/build)"
lune run map/build || status=1

step "layout / navigability check"
python3 tests/layout_check.py || status=1

step "rojo build"
rojo build default.project.json -o TheMimicProtocol.rbxl || status=1

step "rojo sourcemap + luau-lsp analyze"
rojo sourcemap default.project.json -o sourcemap.json || status=1
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions="$DEFS" \
	--base-luaurc=.luaurc src || status=1

if command -v selene >/dev/null 2>&1 && [ "${SKIP_SELENE:-0}" != "1" ]; then
	step "selene"
	selene src || status=1
fi

step "unit tests"
lune run tests/run || status=1

step "client smoke test"
lune run tests/sim/client || status=1

if [ "${SKIP_SIM:-0}" != "1" ]; then
	step "server round simulation"
	lune run tests/sim/run || status=1
fi

if [ $status -eq 0 ]; then echo -e "\nALL CHECKS PASSED"; else echo -e "\nSOME CHECKS FAILED"; fi
exit $status
