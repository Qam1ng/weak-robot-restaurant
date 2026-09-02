#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/builds/orientation"
AVI="$OUTPUT_DIR/robot_delegation_orientation.avi"
MP4="$OUTPUT_DIR/robot_delegation_orientation.mp4"
TMP_MP4="$OUTPUT_DIR/robot_delegation_orientation.tmp.mp4"
VOICE_WAV="$OUTPUT_DIR/robot_delegation_orientation_voice.wav"

mkdir -p "$OUTPUT_DIR"
godot --path "$ROOT" --write-movie "$AVI" --fixed-fps 30 --disable-vsync --quit-after 1800 "$ROOT/scenes/VideoOrientation.tscn"
node "$ROOT/tools/build_orientation_audio.mjs" "$VOICE_WAV"

ffmpeg -y -i "$AVI" -i "$VOICE_WAV" -map 0:v:0 -map 1:a:0 -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k "$TMP_MP4"

mv -f "$TMP_MP4" "$MP4"
