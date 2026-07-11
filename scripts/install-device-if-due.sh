#!/usr/bin/env bash

# Attempt the release install to Phone X no more than once every six days.
# This script is intended to be run by a per-user LaunchAgent.
set -u -o pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin:${PATH:-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="${HOME}/Library/Application Support/HealthTrends"
LAST_SUCCESS_FILE="$STATE_DIR/daily-device-install.last-success"
LOCK_DIR="${TMPDIR:-/tmp}/healthtrends-daily-device-install.lock"
MIN_INTERVAL_SECONDS=$((6 * 24 * 60 * 60))

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$*"
}

# Notifications are intentionally best-effort: a Pushover outage must not
# affect the install result or the timestamp used to schedule the next attempt.
notify_pushover() {
    local title="$1"
    local message="$2"
    local output
    local status

    if output="$(/opt/homebrew/bin/fish -c '
        source /Users/louie/.config/fish/conf.d/pushover_env.fish
        source /Users/louie/code/dotfiles/.config/fish/functions/pushover.fish
        pushover --app mac-mini --title "$argv[1]" "$argv[2]"
    ' -- "$title" "$message" 2>&1)"; then
        log "Pushover notification sent: $title"
    else
        status=$?
        log "Pushover notification failed (exit $status): $output" >&2
    fi
}

# mkdir is atomic on macOS and provides a portable concurrency guard without
# relying on flock (which is not part of the default macOS installation). Keep
# the owner PID so a lock left by a crashed process can be recovered.
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    lock_pid=""
    if [[ -r "$LOCK_DIR/pid" ]]; then
        lock_pid="$(tr -d '[:space:]' < "$LOCK_DIR/pid")"
    fi
    if [[ "$lock_pid" =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then
        log "Another daily device install (PID $lock_pid) is already running; exiting."
        exit 0
    fi
    log "Removing stale daily install lock${lock_pid:+ from PID $lock_pid}."
    rm -f "$LOCK_DIR/pid"
    if ! rmdir "$LOCK_DIR" 2>/dev/null || ! mkdir "$LOCK_DIR" 2>/dev/null; then
        log "Unable to acquire the daily device install lock; exiting."
        exit 0
    fi
fi
printf '%s\n' "$$" > "$LOCK_DIR/pid"
trap 'rm -f "$LOCK_DIR/pid"; rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

now="$(date +%s)"
if [[ -r "$LAST_SUCCESS_FILE" ]]; then
    last_success="$(tr -d '[:space:]' < "$LAST_SUCCESS_FILE")"
    if [[ "$last_success" =~ ^[0-9]+$ ]]; then
        age=$((now - last_success))
        if (( age < MIN_INTERVAL_SECONDS )); then
            log "Last install succeeded ${age}s ago; next attempt is due after six days."
            exit 0
        fi
    else
        log "Ignoring malformed success timestamp in $LAST_SUCCESS_FILE."
    fi
fi

if ! mkdir -p "$STATE_DIR"; then
    log "Unable to create state directory: $STATE_DIR" >&2
    exit 1
fi

if ! cd -- "$REPO_DIR"; then
    log "Unable to change to repository directory: $REPO_DIR" >&2
    exit 1
fi

log "Attempting: just install-device 'Phone X'"
if ! just install-device 'Phone X'; then
    log "Device install failed; success timestamp was not updated." >&2
    notify_pushover "Health Trends install failed" "Health Trends failed to install to Phone X. The next scheduled attempt will retry."
    exit 1
fi

# Only write the timestamp after just has completed successfully. Use a
# temporary file plus rename so an interrupted write cannot leave a partial
# timestamp behind.
success_time="$(date +%s)"
timestamp_tmp="$STATE_DIR/.daily-device-install.last-success.$$"
if ! printf '%s\n' "$success_time" > "$timestamp_tmp" || ! mv -f "$timestamp_tmp" "$LAST_SUCCESS_FILE"; then
    rm -f "$timestamp_tmp"
    log "Install succeeded, but the success timestamp could not be saved." >&2
    exit 1
fi

log "Device install succeeded; recorded timestamp in $LAST_SUCCESS_FILE."
notify_pushover "Health Trends installed" "Health Trends was installed successfully to Phone X."
