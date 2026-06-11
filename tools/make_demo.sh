#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

WIDTH=1920
HEIGHT=1080
FPS=60
MAX_BYTES=$((30 * 1024 * 1024))
OUT="$REPO_ROOT/demo.mp4"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vibe-city-demo.XXXXXX")
COMBINED_RAW="$TMP_DIR/demo-combined.avi"
CONCAT_LIST="$TMP_DIR/concat-list.txt"

SEGMENT_LABELS=("city" "playground")
SEGMENT_SCENES=(
	"res://scenes/demo/demo_city_scene.tscn"
	"res://scenes/demo/demo_scene.tscn"
)
SEGMENT_QUIT_FRAMES=(3000 1500)

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

render_segment() {
	local label="$1"
	local scene="$2"
	local quit_frames="$3"
	local raw="$TMP_DIR/${label}.avi"
	local log="$TMP_DIR/${label}-godot-movie.log"

	echo "Recording $label demo segment from $scene..."
	set +e
	godot \
		--path "$REPO_ROOT" \
		--write-movie "$raw" \
		--fixed-fps "$FPS" \
		--resolution "${WIDTH}x${HEIGHT}" \
		--windowed \
		--single-window \
		--audio-driver CoreAudio \
		--scene "$scene" \
		--quit-after "$quit_frames" \
		>"$log" 2>&1
	godot_status=$?
	set -e
	cat "$log"

	if [ "$godot_status" -ne 0 ]; then
		echo "Godot movie recording failed for $label with status $godot_status" >&2
		exit "$godot_status"
	fi

	if [ ! -s "$raw" ]; then
		echo "Godot did not produce a movie at $raw" >&2
		exit 1
	fi

	local raw_dims
	raw_dims=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$raw")
	if [ "$raw_dims" != "${WIDTH}x${HEIGHT}" ]; then
		echo "$label movie resolution mismatch: got $raw_dims, expected ${WIDTH}x${HEIGHT}" >&2
		exit 1
	fi

	local raw_duration
	raw_duration=$(duration_for "$raw")
	local raw_audio_streams
	raw_audio_streams=$(stream_count a "$raw")
	echo "$label segment:"
	echo "  raw=$raw"
	echo "  duration_seconds=$raw_duration"
	echo "  resolution=$raw_dims"
	echo "  audio_streams=$raw_audio_streams"

	printf "file '%s'\n" "$raw" >>"$CONCAT_LIST"
}

need_tool godot
need_tool ffmpeg
need_tool ffprobe

for i in "${!SEGMENT_LABELS[@]}"; do
	render_segment "${SEGMENT_LABELS[$i]}" "${SEGMENT_SCENES[$i]}" "${SEGMENT_QUIT_FRAMES[$i]}"
done

echo "Concatenating raw demo segments..."
ffmpeg -y -f concat -safe 0 -i "$CONCAT_LIST" -c copy "$COMBINED_RAW"

combined_dims=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$COMBINED_RAW")
if [ "$combined_dims" != "${WIDTH}x${HEIGHT}" ]; then
	echo "Combined movie resolution mismatch: got $combined_dims, expected ${WIDTH}x${HEIGHT}" >&2
	exit 1
fi

combined_audio_streams=$(stream_count a "$COMBINED_RAW")
if [ "$combined_audio_streams" -gt 0 ]; then
	echo "Combined raw movie audio streams: $combined_audio_streams"
else
	echo "Combined raw movie audio streams: 0 (shipping silent demo if this platform did not capture Movie Maker audio)"
fi

rm -f "$OUT"
crf=23
while true; do
	echo "Encoding demo.mp4 with CRF $crf..."
	ffmpeg -y -i "$COMBINED_RAW" \
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
