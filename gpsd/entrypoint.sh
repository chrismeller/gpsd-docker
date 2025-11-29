#!/usr/bin/env bash

# this is a lightly-modified version of the gpsd portion of this: 
# https://github.com/dkaulukukui/rpi-docker-gpsd-chrony/blob/main/entrypoint.sh

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration variables
GPS_DEVICE="${GPS_DEVICE:-/dev/ttyAMA0}"
PPS_DEVICE="${PPS_DEVICE:-/dev/pps0}"
GPS_SPEED="${GPS_SPEED:-38400}"
GPSD_SOCKET="${GPSD_SOCKET:-/var/run/gpsd.sock}"
DEBUG_LEVEL="${DEBUG_LEVEL:-1}" #gpsd debug level

# Function to log messages with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

check_device() {
    local device="$1"
    if [[ ! -e "$device" ]]; then
        log "WARNING: Device $device does not exist"
        return 1
    fi
    return 0
}

start_gpsd() {
    log "Starting GPSD service..."
    
    # Check if GPS device exists
    if ! check_device "$GPS_DEVICE"; then
        log "ERROR: GPS device $GPS_DEVICE not found"
        return 1
    fi
    
    # Check if PPS device exists (optional)
    local pps_arg=""
    if check_device "$PPS_DEVICE"; then
        pps_arg="$PPS_DEVICE"
        log "PPS device found: $PPS_DEVICE"
    else
        log "WARNING: PPS device $PPS_DEVICE not found, continuing without PPS"
    fi
    
    # Build gpsd command
    local gpsd_cmd=(
	gpsd
        -G                  # Listen on all addresses
        -N                  # Stay in the foreground
        -n                  # Don't wait for client to connect
        -D"$DEBUG_LEVEL"    # Debug level
        -S 2947             # Port
        -s "$GPS_SPEED"     # Fixed port speed
        -F "$GPSD_SOCKET"   # Control socket
        "$GPS_DEVICE"
    )
    
    # Add PPS device if available
    [[ -n "$pps_arg" ]] && gpsd_cmd+=("$pps_arg")
    
    # Add any additional arguments
    gpsd_cmd+=("$@")
    
    log "Executing (line-buffered): stdbuf -oL -eL ${gpsd_cmd[*]}"
    stdbuf -oL -eL "${gpsd_cmd[@]}" &
    local gpsd_pid=$!
    log "GPSD started with PID: $gpsd_pid"
    echo "$gpsd_pid" > /var/run/gpsd.pid
    
    return 0
}

cleanup() {
    log "Received shutdown signal, cleaning up..."

    # Kill gpsd if running
    if [[ -f /var/run/gpsd.pid ]]; then
        local gpsd_pid=$(cat /var/run/gpsd.pid)
        if kill -0 "$gpsd_pid" 2>/dev/null; then
            log "Stopping gpsd (PID: $gpsd_pid)"
            kill -TERM "$gpsd_pid"
            wait "$gpsd_pid" 2>/dev/null || true
        fi
        rm -f /var/run/gpsd.pid
    fi
    
    log "Cleanup completed"
    exit 0
}

# Main execution
main() {
    log "=== GPS/Chrony Startup Script ==="
    log "Container info:"
    log "  User: $(whoami) UID: $(id -u) GID: $(id -g)"
    log "  GPS Device: $GPS_DEVICE"
    log "  PPS Device: $PPS_DEVICE"
    log "  GPS Speed: $GPS_SPEED"
    log "  GPSD Debug Level: $DEBUG_LEVEL"
    
    # Set up signal handlers
    trap cleanup SIGTERM SIGINT SIGQUIT
    
    # Start services
    # now start gpsd
    if ! start_gpsd "$@"; then
        log "ERROR: Failed to start GPSD"
        exit 1
    fi
    
    log "All services started successfully"

    local gpsd_pid=$(cat /var/run/gpsd.pid)
    wait $gpsd_pid
}

# Run main function with all arguments
main "$@"