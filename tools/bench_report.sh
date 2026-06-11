#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

PEDS=${BENCH_PEDESTRIANS:-60}
CARS=${BENCH_TRAFFIC_CARS:-16}
AGENTS=${BENCH_AGENTS:-12}
POLICE=${BENCH_POLICE:-4}
FRAMES=${BENCH_FRAMES:-1800}
WARMUP=${BENCH_WARMUP_FRAMES:-120}
SEED=${BENCH_SEED:-11011}
LABEL=${BENCH_LABEL:-benchmark_city}
BUDGET_MS=${BENCH_BUDGET_MS:-4.5}
WARN_ONLY=${BENCH_WARN_ONLY:-1}
QUIT_AFTER=$(((FRAMES + WARMUP) * 12 + 1800))

log_file=$(mktemp "${TMPDIR:-/tmp}/vibe-city-bench.XXXXXX")
cleanup() {
	rm -f "$log_file"
}
trap cleanup EXIT

echo "== VIBE CITY headless benchmark =="
echo "counts: pedestrians=$PEDS traffic_cars=$CARS agents=$AGENTS police=$POLICE"
echo "frames: measured=$FRAMES warmup=$WARMUP seed=$SEED budget_ms=$BUDGET_MS warn_only=$WARN_ONLY"

set +e
godot \
	--headless \
	--no-header \
	--scene res://scenes/bench/benchmark_city.tscn \
	--quit-after "$QUIT_AFTER" \
	-- \
	--pedestrians "$PEDS" \
	--traffic-cars "$CARS" \
	--agents "$AGENTS" \
	--police "$POLICE" \
	--bench-frames "$FRAMES" \
	--warmup-frames "$WARMUP" \
	--seed "$SEED" \
	--bench-label "$LABEL" \
	>"$log_file" 2>&1
godot_status=$?
set -e

cat "$log_file"

if [ "$godot_status" -ne 0 ]; then
	echo "FAIL: benchmark scene exited with status $godot_status"
	exit "$godot_status"
fi

json_path=$(awk -F= '/^BENCH_JSON_ABS=/{path=$2} END{print path}' "$log_file")
if [ -z "$json_path" ] || [ ! -f "$json_path" ]; then
	echo "FAIL: benchmark did not publish a JSON report path"
	exit 1
fi

budget_result=$(
	python3 - "$json_path" "$BUDGET_MS" <<'PY'
import json
import sys

path = sys.argv[1]
budget = float(sys.argv[2])
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

p95 = float(data["metrics"]["combined_ms"]["p95"])
print(f"{p95:.6f}")
print("OVER" if p95 > budget else "OK")
PY
)

combined_p95=$(printf '%s\n' "$budget_result" | sed -n '1p')
budget_status=$(printf '%s\n' "$budget_result" | sed -n '2p')

if [ "$budget_status" = "OVER" ]; then
	message="combined p95 ${combined_p95} ms exceeds budget ${BUDGET_MS} ms"
	if [ "$WARN_ONLY" = "1" ] || [ "$WARN_ONLY" = "true" ] || [ "$WARN_ONLY" = "yes" ]; then
		echo "WARN: $message"
		exit 0
	fi
	echo "FAIL: $message"
	exit 1
fi

echo "PASS: combined p95 ${combined_p95} ms is within budget ${BUDGET_MS} ms"
