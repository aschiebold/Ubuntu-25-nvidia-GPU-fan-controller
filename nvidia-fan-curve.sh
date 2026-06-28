#!/usr/bin/env bash
# Headless, session-independent NVIDIA fan curve daemon. Runs as root.
#
# Temperature is read via nvidia-smi (no X needed). Fan speed is set via
# nvidia-settings, which needs an NV-CONTROL (X/Xwayland) endpoint. This daemon
# dynamically discovers a usable endpoint from whatever graphical session is
# active on the seat (the logged-in user, uid 1000, OR the gdm greeter, uid 984)
# and applies a temp->fan-speed curve. If no endpoint is available it simply
# waits and retries (the GPU falls back to its safe default auto fan control)
# instead of exiting, so systemd never enters a restart loop.
set -uo pipefail

# --- Config ---
GPU_INDEX=0
FAN_INDEX=0
POLL_SECONDS=3
RECONNECT_SECONDS=10

# Curve points: tempC:speedPercent
CURVE_POINTS=(
  "10:30"
  "35:40"
  "40:50"
  "55:55"
  "65:70"
  "75:85"
  "82:100"
)

# Clamp
MIN_SPEED=25
MAX_SPEED=100
# Only apply a new fan speed when this many percent differs (0 disables).
HYSTERESIS_PERCENT=2

# UIDs whose runtime dir may host a usable Xwayland: 1000=user, 984=gdm greeter.
CANDIDATE_UIDS=(1000 984)
CANDIDATE_DISPLAYS=(":0" ":1")

NVS=/usr/bin/nvidia-settings
NVSMI=/usr/bin/nvidia-smi

CUR_DISPLAY=""
CUR_XAUTH=""

log() { echo "$(date +'%F %T') $*"; }

# Return 0 if the given DISPLAY/XAUTHORITY serves a working NV-CONTROL fan query.
nvs_probe() {
  local disp="$1" xauth="$2" out
  out="$(DISPLAY="$disp" XAUTHORITY="$xauth" timeout 8 "$NVS" \
        -q "[gpu:${GPU_INDEX}]/GPUFanControlState" -t 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]]
}

# Find a usable endpoint; sets CUR_DISPLAY/CUR_XAUTH. Returns 0 on success.
discover_endpoint() {
  local uid rd auth disp
  for uid in "${CANDIDATE_UIDS[@]}"; do
    rd="/run/user/$uid"
    [[ -d "$rd" ]] || continue
    while IFS= read -r auth; do
      [[ -n "$auth" && -r "$auth" ]] || continue
      for disp in "${CANDIDATE_DISPLAYS[@]}"; do
        if nvs_probe "$disp" "$auth"; then
          CUR_DISPLAY="$disp"; CUR_XAUTH="$auth"
          return 0
        fi
      done
    done < <(ls -1t "$rd"/.mutter-Xwaylandauth.* "$rd"/.Xauthority 2>/dev/null)
  done
  return 1
}

get_temp() {
  "$NVSMI" --query-gpu=temperature.gpu --format=csv,noheader,nounits -i "$GPU_INDEX" 2>/dev/null | tr -d '[:space:]'
}

interp_speed() {
  local t="$1"
  local prev_t prev_s next_t next_s
  local i

  IFS=: read -r prev_t prev_s <<< "${CURVE_POINTS[0]}"
  if (( t <= prev_t )); then
    echo "$prev_s"; return
  fi
  for (( i=1; i<${#CURVE_POINTS[@]}; i++ )); do
    IFS=: read -r next_t next_s <<< "${CURVE_POINTS[i]}"
    if (( t <= next_t )); then
      local dt=$(( next_t - prev_t ))
      local ds=$(( next_s - prev_s ))
      local x=$(( t - prev_t ))
      local s=$(( prev_s + (ds * x + dt / 2) / dt ))
      echo "$s"; return
    fi
    prev_t=$next_t
    prev_s=$next_s
  done
  echo "$next_s"
}

# Set fan control state (0=auto, 1=manual) on the current endpoint.
set_state() {
  local st="$1"
  DISPLAY="$CUR_DISPLAY" XAUTHORITY="$CUR_XAUTH" timeout 8 "$NVS" \
    -a "[gpu:${GPU_INDEX}]/GPUFanControlState=${st}" >/dev/null 2>&1
}

# Apply a fan speed on the current endpoint. Nonzero return => endpoint lost.
apply_speed() {
  local speed="$1"
  (( speed < MIN_SPEED )) && speed=$MIN_SPEED
  (( speed > MAX_SPEED )) && speed=$MAX_SPEED
  DISPLAY="$CUR_DISPLAY" XAUTHORITY="$CUR_XAUTH" timeout 8 "$NVS" \
    -a "[gpu:${GPU_INDEX}]/GPUFanControlState=1" \
    -a "[fan:${FAN_INDEX}]/GPUTargetFanSpeed=${speed}" >/dev/null 2>&1
}

cleanup() {
  # Hand fan control back to the GPU's automatic mode on exit, if we have an endpoint.
  if [[ -n "$CUR_DISPLAY" && -n "$CUR_XAUTH" ]]; then
    set_state 0 || true
  fi
}
# On a signal, exit cleanly (0) so `systemctl stop/restart` is graceful; the EXIT
# trap then runs cleanup exactly once.
on_signal() { exit 0; }
trap cleanup EXIT
trap on_signal INT TERM

log "nvidia-fan-curve daemon starting (headless / session-independent)"

last_applied_speed=""
while true; do
  if ! discover_endpoint; then
    log "no NV-CONTROL X endpoint yet; GPU on default auto fan; retry in ${RECONNECT_SECONDS}s"
    last_applied_speed=""
    sleep "$RECONNECT_SECONDS"
    continue
  fi
  log "using NV-CONTROL endpoint DISPLAY=$CUR_DISPLAY XAUTHORITY=$CUR_XAUTH"
  set_state 1 || true

  # Inner loop: control until the endpoint disappears, then re-discover.
  while true; do
    temp="$(get_temp)"
    if [[ -z "$temp" ]]; then
      log "temperature read failed; retrying"
      sleep "$POLL_SECONDS"; continue
    fi
    speed="$(interp_speed "$temp")"
    if [[ -z "$last_applied_speed" ]] \
       || (( speed > last_applied_speed + HYSTERESIS_PERCENT )) \
       || (( speed < last_applied_speed - HYSTERESIS_PERCENT )); then
      if apply_speed "$speed"; then
        log "temp=${temp}C speed=${speed}%"
        last_applied_speed="$speed"
      else
        log "apply failed; NV-CONTROL endpoint lost, re-discovering"
        CUR_DISPLAY=""; CUR_XAUTH=""; last_applied_speed=""
        break
      fi
    else
      log "temp=${temp}C speed=${last_applied_speed}% (held by hysteresis)"
    fi
    sleep "$POLL_SECONDS"
  done
done
