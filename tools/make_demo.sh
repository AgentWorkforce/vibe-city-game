#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

WIDTH=1920
HEIGHT=1080
FPS=60
MAX_BYTES=$((30 * 1024 * 1024))
SCENE="res://scenes/demo/demo_scene.tscn"
OUT="$REPO_ROOT/demo.mp4"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vibe-city-demo.XXXXXX")
RAW="$TMP_DIR/demo.avi"
LOG="$TMP_DIR/godot-movie.log"

cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

need_tool() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Missing required tool: $1" >&2
		exit 1
	fi
}

bytes_for() {
	wc -c <"$1" | tr -d '[:space:]'
}

duration_for() {
	ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1"
}

stream_count() {
	ffprobe -v error -select_streams "$1" -show_entries stream=index -of csv=p=0 "$2" | wc -l | tr -d '[:space:]'
}

need_tool godot
need_tool ffmpeg
need_tool ffprobe

echo "Recording demo scene with Godot Movie Maker..."
set +e
godot \
	--path "$REPO_ROOT" \
	--write-movie "$RAW" \
	--fixed-fps "$FPS" \
	--resolution "${WIDTH}x${HEIGHT}" \
	--windowed \
	--single-window \
	--audio-driver CoreAudio \
	--scene "$SCENE" \
	--quit-after 3300 \
	>"$LOG" 2>&1
godot_status=$?
set -e
cat "$LOG"

if [ "$godot_status" -ne 0 ]; then
	echo "Godot movie recording failed with status $godot_status" >&2
	exit "$godot_status"
fi

if [ ! -s "$RAW" ]; then
	echo "Godot did not produce a movie at $RAW" >&2
	exit 1
fi

raw_dims=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$RAW")
if [ "$raw_dims" != "${WIDTH}x${HEIGHT}" ]; then
	echo "Movie resolution mismatch: got $raw_dims, expected ${WIDTH}x${HEIGHT}" >&2
	exit 1
fi

raw_audio_streams=$(stream_count a "$RAW")
if [ "$raw_audio_streams" -gt 0 ]; then
	echo "Raw movie audio streams: $raw_audio_streams"
else
	echo "Raw movie audio streams: 0 (shipping silent demo if this platform did not capture Movie Maker audio)"
fi

rm -f "$OUT"
crf=23
while true; do
	echo "Encoding demo.mp4 with CRF $crf..."
	ffmpeg -y -i "$RAW" \
		-map 0:v:0 -map 0:a? \
		-c:v libx264 -preset medium -crf "$crf" -pix_fmt yuv420p \
		-c:a aac -b:a 128k \
		-movflags +faststart \
		"$OUT"

	size_bytes=$(bytes_for "$OUT")
	if [ "$size_bytes" -le "$MAX_BYTES" ] || [ "$crf" -ge 30 ]; then
		break
	fi
	echo "Encoded size $size_bytes bytes exceeds 30MB; retrying at higher CRF."
	crf=$((crf + 3))
done

final_size=$(bytes_for "$OUT")
if [ "$final_size" -gt "$MAX_BYTES" ]; then
	echo "demo.mp4 is larger than 30MB after CRF $crf: $final_size bytes" >&2
	exit 1
fi

final_duration=$(duration_for "$OUT")
final_dims=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$OUT")
final_audio_streams=$(stream_count a "$OUT")

echo "Wrote demo.mp4"
echo "  size_bytes=$final_size"
echo "  duration_seconds=$final_duration"
echo "  resolution=$final_dims"
echo "  audio_streams=$final_audio_streams"
echo "  crf=$crf"
