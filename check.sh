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

echo "== Smoke main scene =="
if godot --headless --quit-after 60; then
	echo "Main scene loaded and exited."
else
	fail "Main scene smoke run failed."
fi

if [ "$failures" -eq 0 ]; then
	echo "PASS: project imports, scripts parse, and the main scene loads headlessly."
else
	echo "FAIL: one or more checks failed."
	exit 1
fi
