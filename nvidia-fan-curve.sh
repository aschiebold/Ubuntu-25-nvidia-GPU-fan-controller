#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
GPU_INDEX=0
FAN_INDEX=0
POLL_SECONDS=3

# Curve points: tempC:speedPercent
# Edit these to your preference.
CURVE_POINTS=(
  "10:30"
  "35:30"
  "40:40"
  "55:55"
  "65:70"
  "75:85"
  "82:100"
)

# Clamp
MIN_SPEED=25
MAX_SPEED=100

get_temp() {
  /usr/bin/nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits -i "$GPU_INDEX" | tr -d '[:space:]'
}

interp_speed() {
  local t="$1"
  local prev_t prev_s next_t next_s
  local i

  # Below first point
  IFS=: read -r prev_t prev_s <<< "${CURVE_POINTS[0]}"
  if (( t <= prev_t )); then
    echo "$prev_s"
    return
  fi

  # Between points
  for (( i=1; i<${#CURVE_POINTS[@]}; i++ )); do
    IFS=: read -r next_t next_s <<< "${CURVE_POINTS[i]}"
    if (( t <= next_t )); then
      # Linear interpolation
      local dt=$(( next_t - prev_t ))
      local ds=$(( next_s - prev_s ))
      local x=$(( t - prev_t ))
      local s=$(( prev_s + (ds * x + dt / 2) / dt ))
      echo "$s"
      return
    fi
    prev_t=$next_t
    prev_s=$next_s
  done

  # Above last point
  echo "$next_s"
}

apply_speed() {
  local speed="$1"
  (( speed < MIN_SPEED )) && speed=$MIN_SPEED
  (( speed > MAX_SPEED )) && speed=$MAX_SPEED
  /usr/bin/nvidia-settings -a "[gpu:${GPU_INDEX}]/GPUFanControlState=1" \
                  -a "[fan:${FAN_INDEX}]/GPUTargetFanSpeed=${speed}" >/dev/null
  echo "$(date +'%F %T') temp=${temp}C speed=${speed}%"
}

cleanup() {
  # Return control to auto on exit
  /usr/bin/nvidia-settings -a "[gpu:${GPU_INDEX}]/GPUFanControlState=0" >/dev/null || true
}
trap cleanup EXIT INT TERM

# Enable manual mode once
/usr/bin/nvidia-settings -a "[gpu:${GPU_INDEX}]/GPUFanControlState=1" >/dev/null

while true; do
  temp="$(get_temp)"
  speed="$(interp_speed "$temp")"
  apply_speed "$speed"
  sleep "$POLL_SECONDS"
done
