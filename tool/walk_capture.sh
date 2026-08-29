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
  "$ADB" logcat -v time -s $TAGS | grep --line-buffered -E "Leg anchored|Walk |SAY|ADVANCE|RECENTRE"
}

# Reads a capture back as numbers instead of as a story.
#
# A walk you can only describe is a walk you cannot tune. These are the three
# measurements that say whether AR navigation is accurate, and each one needs a
# ground truth the phone cannot supply — so the tape measure goes in on the
# command line and the log supplies the rest.
#
#   report <log> --straight=<metres>   odometry scale over a measured line
#   report <log> --loop                misclosure of a walk back to its start
#   report <log>                       whatever the walk happened to contain
#
# Targets, until a device says otherwise:
#   * scale error under 5% of distance walked
#   * loop misclosure under 5% of the loop's perimeter
#   * off-route: mean under 1.0m and max under 2.5m over a whole walk
#     (2.5m is `ArGuidanceCubit._registrationHoldsM`, the point at which the app
#     stops believing its own registration — a walk that reaches it has already
#     failed, whatever the walker thought)
report() {
  local log="${1:-}"
  [ -f "$log" ] || { echo "usage: $0 report <capture.log> [--straight=M] [--loop]"; exit 2; }
  shift

  local truth=""
  local loop=0
  for arg in "$@"; do
    case "$arg" in
      --straight=*) truth="${arg#--straight=}" ;;
      --loop) loop=1 ;;
    esac
  done

  echo "=== $(basename "$log")"
  sed -n '1,2p' "$log"
  echo

  echo "--- Registration"
  grep -E "REGISTERED|Registering late|Route registered|RECENTRE|not registering" "$log" \
    | sed 's/^/  /' | head -30
  grep -cE "RECENTRE at" "$log" | sed 's/^/  landmark corrections applied: /'
  grep -cE "RECENTRE REFUSED" "$log" | sed 's/^/  landmark corrections refused: /'
  echo

  echo "--- Floor"
  grep -E "Floor measured|No floor plane" "$log" | sed 's/^/  /' | head -5
  echo

  # `Route ... off 1.2m ...` — the one number that says whether the building
  # agrees with the app. Everything else in the log is the app agreeing with
  # itself.
  echo "--- Off-route"
  awk '
    match($0, /off ([0-9]+\.[0-9]+)m/, m) {
      n++; sum += m[1]; if (m[1] > max) max = m[1]
    }
    END {
      if (n == 0) { print "  no registered route in this capture"; exit }
      printf "  samples %d   mean %.2fm   max %.2fm\n", n, sum / n, max
      printf "  verdict %s\n", (sum / n < 1.0 && max < 2.5) ? "PASS" : "FAIL"
    }
  ' "$log"
  echo

  # `Pose x=1.20 z=-3.40 ...` — raw ARCore, the only thing in the log that a
  # tape measure can be held against.
  echo "--- Pose track"
  awk -v truth="$truth" -v loop="$loop" '
    match($0, /Pose x=(-?[0-9]+\.[0-9]+) z=(-?[0-9]+\.[0-9]+)/, m) {
      x = m[1] + 0; z = m[2] + 0
      if (n == 0) { x0 = x; z0 = z }
      if (n > 0) { path += sqrt((x - px) ^ 2 + (z - pz) ^ 2) }
      px = x; pz = z; n++
    }
    END {
      if (n < 2) { print "  too few pose samples"; exit }
      net = sqrt((px - x0) ^ 2 + (pz - z0) ^ 2)
      printf "  samples %d   path walked %.2fm   net displacement %.2fm\n", n, path, net
      if (truth != "") {
        err = net - truth
        printf "  straight-line truth %.2fm -> error %+.2fm (%+.1f%%)\n", truth, err, 100 * err / truth
        printf "  verdict %s\n", (err < 0 ? -err : err) / truth < 0.05 ? "PASS" : "FAIL"
      }
      if (loop == 1) {
        printf "  loop misclosure %.2fm over a %.2fm perimeter (%.1f%%)\n", net, path, 100 * net / path
        printf "  verdict %s\n", (path > 0 && net / path < 0.05) ? "PASS" : "FAIL"
      }
    }
  ' "$log"
}

case "${1:-}" in
  start) shift; start "${1:-walk}" ;;
  stop) stop ;;
  tail) tail_live ;;
  report) shift; report "$@" ;;
  *) echo "usage: $0 {start [name]|stop|tail|report <log> [--straight=M] [--loop]}"; exit 2 ;;
esac
