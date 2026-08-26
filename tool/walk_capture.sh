#!/usr/bin/env bash
# Captures a guidance walk: the log, and optionally the screen.
#
# A field test you cannot read back afterwards is an opinion. This pulls the
# three lines that reconstruct a walk — `Leg anchored` and `Walk` from native,
# `SAY` and `ADVANCE` from Dart — into one timestamped file, so a complaint
# ("the arrow pointed at the wall by the lifts") can be checked against what
# the app actually thought it was doing at that moment.
#
#   tool/walk_capture.sh start [name]   begin capturing
#   tool/walk_capture.sh stop           end, and say where the files are
#   tool/walk_capture.sh tail           watch the walk live on a laptop
#
# Screen recording is capped by Android at 3 minutes per file, so it restarts
# itself in a loop until stopped. Leave it off if the walk is long and you only
# need the numbers: pass NO_VIDEO=1.

set -u

ADB="${ADB:-$HOME/AppData/Local/Android/Sdk/platform-tools/adb.exe}"
[ -x "$ADB" ] || ADB="adb"

OUT_DIR="${OUT_DIR:-walk-captures}"
PID_FILE="$OUT_DIR/.capture.pids"

# Every tag that says something about a walk. TalkBack and the speech engine
# are deliberately not here: what the app *decided* to say is logged by SAY,
# and the TTS chatter buries it.
TAGS="ArGuidance:I ArrowRenderer:I flutter:I ArCoreDepth:W AndroidRuntime:E"

start() {
  local name="${1:-walk}"
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  local base="$OUT_DIR/${name}-${stamp}"
  mkdir -p "$OUT_DIR"

  "$ADB" logcat -c
  echo "Device: $("$ADB" shell getprop ro.product.model | tr -d '\r')" > "$base.log"
  echo "Started: $(date)" >> "$base.log"
  echo "---" >> "$base.log"

  # -v time so every line carries a clock to line the video up against.
  "$ADB" logcat -v time -s $TAGS >> "$base.log" &
  echo "$!" > "$PID_FILE"
  echo "$base" >> "$PID_FILE"

  if [ "${NO_VIDEO:-0}" != "1" ]; then
    record_loop "$base" &
    echo "$!" >> "$PID_FILE"
  fi

  echo "Capturing to $base.log"
  echo "Walk it, then: tool/walk_capture.sh stop"
}

# Android caps screenrecord at 180s, so chain them rather than lose the rest.
record_loop() {
  local base="$1"
  local part=1
  while :; do
    "$ADB" shell screenrecord --time-limit 180 --size 720x1600 \
      "/sdcard/walk-part$part.mp4" >/dev/null 2>&1 || return 0
    part=$((part + 1))
  done
}

stop() {
  [ -f "$PID_FILE" ] || { echo "Nothing is capturing."; exit 1; }
  local base
  base="$(sed -n '2p' "$PID_FILE")"

  while read -r line; do
    case "$line" in
      [0-9]*) kill "$line" 2>/dev/null ;;
    esac
  done < "$PID_FILE"
  "$ADB" shell pkill -INT screenrecord 2>/dev/null
  # screenrecord needs a moment to finalise the container, or the last file is
  # unplayable.
  sleep 3

  for remote in $("$ADB" shell ls /sdcard/walk-part*.mp4 2>/dev/null | tr -d '\r'); do
    "$ADB" pull "$remote" "${base}-$(basename "$remote")" >/dev/null 2>&1
    "$ADB" shell rm "$remote" 2>/dev/null
  done

  rm -f "$PID_FILE"
  echo "Saved:"
  ls -la "${base}"* 2>/dev/null
  echo
  echo "The walk, in order:"
  grep -E "Leg anchored|ADVANCE|SAY" "${base}.log" | tail -40
}

tail_live() {
  "$ADB" logcat -v time -s $TAGS | grep --line-buffered -E "Leg anchored|Walk |SAY|ADVANCE"
}

case "${1:-}" in
  start) shift; start "${1:-walk}" ;;
  stop) stop ;;
  tail) tail_live ;;
  *) echo "usage: $0 {start [name]|stop|tail}"; exit 2 ;;
esac
