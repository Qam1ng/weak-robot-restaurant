#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/builds/orientation"
MP4="$OUTPUT_DIR/robot_delegation_orientation.mp4"
VOICE_WAV="$OUTPUT_DIR/robot_delegation_orientation_voice.wav"

mkdir -p "$OUTPUT_DIR"
node "$ROOT/tools/build_orientation_audio.mjs" "$VOICE_WAV"
node "$ROOT/tools/build_orientation_video.mjs" "$VOICE_WAV" "$MP4"
