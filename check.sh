#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

failures=0
import_log=$(mktemp "${TMPDIR:-/tmp}/vibe-city-import.XXXXXX.log")

cleanup() {
	rm -f "$import_log"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $1"
	failures=1
}

echo "== Import project =="
set +e
godot --headless --import . >"$import_log" 2>&1
import_status=$?
set -e
cat "$import_log"

if grep -q "ERROR" "$import_log"; then
	fail "Godot import emitted ERROR lines."
fi

if [ "$import_status" -ne 0 ]; then
	echo "NOTE: Godot import exited with status $import_status; continuing because headless import can report non-zero status on some builds."
fi

echo "== Parse GDScript =="
script_roots=()
if [ -d scripts ]; then
	script_roots+=(scripts)
fi
if [ -d scenes ]; then
	script_roots+=(scenes)
fi

if [ "${#script_roots[@]}" -eq 0 ]; then
	echo "No scripts/ or scenes/ directories found."
else
	found_scripts=0
	while IFS= read -r script_file; do
		found_scripts=1
		echo "Checking $script_file"
		if ! godot --headless --check-only --script "$script_file"; then
			fail "GDScript parse check failed for $script_file."
		fi
	done < <(find "${script_roots[@]}" -type f -name '*.gd' | sort)

	if [ "$found_scripts" -eq 0 ]; then
		echo "No .gd files found under scripts/ or scenes/."
	fi
fi

echo "== Unit tests =="
if godot --headless -s tools/run_tests.gd; then
	echo "Unit tests passed."
else
	fail "Unit tests failed."
fi

echo "== Smoke main scene =="
if godot --headless --quit-after 60; then
	echo "Main scene loaded and exited."
else
	fail "Main scene smoke run failed."
fi

echo "== Integration: drive =="
test_drive_out=$(godot --headless -s tools/test_drive.gd 2>&1 || true)
if printf '%s' "${test_drive_out}" | grep -q "DRIVE TEST PASS"; then
	echo "Drive test passed."
else
	fail "Drive integration test failed."
fi

echo "== Integration: climb =="
test_climb_out=$(godot --headless -s tools/test_climb.gd 2>&1 || true)
if printf '%s' "${test_climb_out}" | grep -q "CLIMB TEST PASS"; then
	echo "Climb test passed."
else
	fail "Climb integration test failed."
fi

echo "== Integration: shoot =="
test_shoot_out=$(godot --headless -s tools/test_shoot.gd 2>&1 || true)
if printf '%s' "${test_shoot_out}" | grep -q "SHOOT TEST PASS"; then
	echo "Shoot test passed."
else
	fail "Shoot integration test failed."
fi

echo "== Integration: reclaim =="
test_reclaim_out=$(godot --headless -s tools/test_reclaim.gd 2>&1 || true)
if printf '%s' "${test_reclaim_out}" | grep -q "RECLAIM TEST PASS"; then
	echo "Reclaim test passed."
else
	fail "Reclaim integration test failed."
fi

echo "== Integration: streaming =="
test_streaming_out=$(godot --headless -s tools/test_streaming.gd 2>&1 || true)
if printf '%s' "${test_streaming_out}" | grep -q "STREAMING TEST PASS"; then
	echo "Streaming test passed."
else
	fail "Streaming integration test failed."
fi

echo "== Integration: mission =="
test_mission_out=$(godot --headless -s tools/test_mission.gd 2>&1 || true)
if printf '%s' "${test_mission_out}" | grep -q "MISSION TEST PASS"; then
	echo "Mission test passed."
else
	fail "Mission integration test failed."
fi

if [ "$failures" -eq 0 ]; then
	echo "PASS: project imports, scripts parse, and the main scene loads headlessly."
else
	echo "FAIL: one or more checks failed."
	exit 1
fi
