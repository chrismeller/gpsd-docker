#!/usr/bin/env bash

# this is a lightly-modified version of the chrony portion of this: 
# https://github.com/dkaulukukui/rpi-docker-gpsd-chrony/blob/main/entrypoint.sh

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration variables
LOG_LEVEL="${LOG_LEVEL:-0}" # chrony log level
ENABLE_SYSCLK="${ENABLE_SYSCLK:-true}"   # enable control of the system clock

# Function to log messages with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

start_chronyd() {
    log "Starting Chrony service..."
    
    # Check if chronyd exists
    if [[ ! -x "/usr/sbin/chronyd" ]]; then
        log "ERROR: chronyd not found at /usr/sbin/chronyd"
        return 1
    fi

    # Check if chrony user exists
    if ! id -u chrony &>/dev/null; then
        log "ERROR: User 'chrony' does not exist"
        return 1
    fi

    # confirm correct permissions on chrony run directory
        if [ -d /run/chrony ]; then
        chown -R chrony:chrony /run/chrony
        chmod o-rx /run/chrony
        # remove previous pid file if it exist
        rm -f /var/run/chrony/chronyd.pid
    fi

    # confirm correct permissions on chrony variable state directory
    if [ -d /var/lib/chrony ]; then
        chown -R chrony:chrony /var/lib/chrony
    fi

    # LOG_LEVEL environment variable is not present, so populate with chrony default (0)
    # chrony log levels: 0 (informational), 1 (warning), 2 (non-fatal error) and 3 (fatal error)
    if [ -z "${LOG_LEVEL}" ]; then
        LOG_LEVEL=0
    else
    # confirm log level is between 0-3, since these are the only log levels supported
        if expr "${LOG_LEVEL}" : "[^0123]" > /dev/null; then
            # level outside of supported range, let's set to default (0)
            LOG_LEVEL=0
        fi
    fi

    # enable control of system clock, enabled by default
    SYSCLK=""
    if [[ "${ENABLE_SYSCLK}" = false ]]; then
        SYSCLK="-x"
    fi
    
    local chronyd_cmd=(
        /usr/sbin/chronyd
        -u chrony       # Run as chrony user
        -d              # Foreground mode
        ${SYSCLK}       # Allow system clock control
        -L"$LOG_LEVEL"  # Log level
    )
    
    log "Executing: ${chronyd_cmd[*]}"
    "${chronyd_cmd[@]}" &
    local chronyd_pid=$!
    log "Chronyd started with PID: $chronyd_pid"
    echo "$chronyd_pid" > /var/run/chronyd.pid
    
    return 0
}

cleanup() {
    log "Received shutdown signal, cleaning up..."
    
    # Kill chronyd if running
    if [[ -f /var/run/chronyd.pid ]]; then
        local chronyd_pid=$(cat /var/run/chronyd.pid)
        if kill -0 "$chronyd_pid" 2>/dev/null; then
            log "Stopping chronyd (PID: $chronyd_pid)"
            kill -TERM "$chronyd_pid"
            wait "$chronyd_pid" 2>/dev/null || true
        fi
        rm -f /var/run/chronyd.pid
    fi
}

# Main execution
main() {
    log "=== GPS/Chrony Startup Script ==="
    log "Container info:"
    log "  User: $(whoami) UID: $(id -u) GID: $(id -g)"
    log "  Chrony Log Level: $LOG_LEVEL"
    log "  Chrony Control System Clock: $ENABLE_SYSCLK"
    
    # Set up signal handlers
    trap cleanup SIGTERM SIGINT SIGQUIT
    
    # Start services

    # start chronyd first
    if ! start_chronyd; then
        log "ERROR: Failed to start Chronyd"
        cleanup
        exit 1
    fi
    
    log "All services started successfully"

    local chrony_pid=$(cat /var/run/chronyd.pid)
    wait $chrony_pid
}

# Run main function with all arguments
main "$@"