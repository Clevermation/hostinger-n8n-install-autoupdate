#!/bin/bash

#===============================================================================
# Watchtower Setup Script for n8n Auto-Updates
# Created by Clevermation (clevermation.com)
# Version: 1.1.0
# 
# This script adds or updates Watchtower in an existing docker-compose.yml 
# to enable automatic nightly updates for n8n containers.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/clevermation/n8n-watchtower/main/setup-watchtower-n8n.sh | bash
#
# With custom time:
#   UPDATE_TIME=3 curl -fsSL ... | bash
#
# Security features:
#   - Creates backup before any changes
#   - Validates docker-compose.yml syntax
#   - Checks container health after restart
#   - Safe update of existing Watchtower config
#===============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration with defaults
UPDATE_TIME="${UPDATE_TIME:-2}"  # Default: 02:00 Uhr
TIMEZONE="${TIMEZONE:-Europe/Berlin}"
CLEANUP_SCRIPT="${CLEANUP_SCRIPT:-true}"  # Set to false to keep script

# Logging function
log() {
    echo -e "$1"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

log_step() {
    echo -e "${YELLOW}[$1]${NC} $2"
}

#---------------------------------------
# Header
#---------------------------------------
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║         Watchtower Setup for n8n Auto-Updates                 ║"
echo "║                   by Clevermation                             ║"
echo "║                     Version 1.1.0                             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

#---------------------------------------
# Pre-flight checks
#---------------------------------------
log_step "1/7" "Running pre-flight checks..."

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root or with sudo"
    exit 1
fi

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed!"
    exit 1
fi

if ! docker info &> /dev/null; then
    log_error "Docker daemon is not running!"
    exit 1
fi

# Validate UPDATE_TIME is a number between 0-23
if ! [[ "$UPDATE_TIME" =~ ^[0-9]+$ ]] || [ "$UPDATE_TIME" -lt 0 ] || [ "$UPDATE_TIME" -gt 23 ]; then
    log_error "UPDATE_TIME must be a number between 0 and 23"
    exit 1
fi

log_success "Pre-flight checks passed"

#---------------------------------------
# Find docker-compose.yml
#---------------------------------------
log_step "2/7" "Searching for docker-compose.yml..."

COMPOSE_FILE=""
POSSIBLE_PATHS=(
    "/root/docker-compose.yml"
    "/root/docker-compose.yaml"
    "/opt/n8n/docker-compose.yml"
    "/opt/n8n/docker-compose.yaml"
    "/home/*/docker-compose.yml"
    "/opt/docker-compose.yml"
)

# First check common paths
for path in "${POSSIBLE_PATHS[@]}"; do
    # Handle glob patterns
    for expanded_path in $path; do
        if [ -f "$expanded_path" ]; then
            # Verify it contains n8n
            if grep -q "n8n" "$expanded_path"; then
                COMPOSE_FILE="$expanded_path"
                break 2
            fi
        fi
    done
done

# If not found, search the system (limited depth for performance)
if [ -z "$COMPOSE_FILE" ]; then
    COMPOSE_FILE=$(find /root /opt /home -maxdepth 4 -name "docker-compose.yml" -type f 2>/dev/null | while read f; do
        if grep -q "n8n" "$f" 2>/dev/null; then
            echo "$f"
            break
        fi
    done)
fi

if [ -z "$COMPOSE_FILE" ] || [ ! -f "$COMPOSE_FILE" ]; then
    log_error "docker-compose.yml with n8n configuration not found!"
    log "Searched in: ${POSSIBLE_PATHS[*]}"
    exit 1
fi

log_success "Found: ${COMPOSE_FILE}"
COMPOSE_DIR=$(dirname "$COMPOSE_FILE")

#---------------------------------------
# Check for n8n container
#---------------------------------------
log_step "3/7" "Checking for n8n container..."

N8N_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i n8n | head -1)

if [ -z "$N8N_CONTAINER" ]; then
    log_error "No running n8n container found!"
    log "Running containers:"
    docker ps --format "  {{.Names}}"
    exit 1
fi

log_success "Found n8n container: ${N8N_CONTAINER}"

#---------------------------------------
# Detect mode: Install or Update
#---------------------------------------
log_step "4/7" "Detecting installation mode..."

MODE="install"
CURRENT_TIME=""

if grep -q "watchtower:" "$COMPOSE_FILE"; then
    MODE="update"
    # Try to extract current update time
    CURRENT_TIME=$(grep -A 10 "watchtower:" "$COMPOSE_FILE" | grep "WATCHTOWER_SCHEDULE" | grep -oP '0 0 \K[0-9]+' || echo "unknown")
    log_warning "Watchtower already configured (current time: ${CURRENT_TIME}:00)"
    log "Mode: UPDATE - Will update existing configuration"
else
    log_success "Mode: INSTALL - Fresh installation"
fi

# Show what will happen
echo ""
log "${BLUE}Configuration:${NC}"
log "  • n8n container: ${N8N_CONTAINER}"
log "  • Update time: ${UPDATE_TIME}:00 ${TIMEZONE}"
if [ "$MODE" = "update" ] && [ "$CURRENT_TIME" != "unknown" ] && [ "$CURRENT_TIME" != "$UPDATE_TIME" ]; then
    log "  • Time change: ${CURRENT_TIME}:00 → ${UPDATE_TIME}:00"
fi
echo ""

read -p "Continue? (Y/n): " CONFIRM
CONFIRM=${CONFIRM:-Y}
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    log "${BLUE}Aborted by user.${NC}"
    exit 0
fi

#---------------------------------------
# Create backup
#---------------------------------------
log_step "5/7" "Creating backup..."

BACKUP_FILE="${COMPOSE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$COMPOSE_FILE" "$BACKUP_FILE"

# Verify backup was created
if [ ! -f "$BACKUP_FILE" ]; then
    log_error "Failed to create backup!"
    exit 1
fi

log_success "Backup created: ${BACKUP_FILE}"

#---------------------------------------
# Add or Update Watchtower
#---------------------------------------
log_step "6/7" "Configuring Watchtower..."

WATCHTOWER_CONFIG="  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_SCHEDULE=0 0 ${UPDATE_TIME} * * *
      - WATCHTOWER_ROLLING_RESTART=true
      - WATCHTOWER_INCLUDE_RESTARTING=true
      - TZ=${TIMEZONE}
    command: ${N8N_CONTAINER}"

if [ "$MODE" = "update" ]; then
    # Remove existing watchtower section
    # This uses awk to remove the watchtower service block
    awk '
    /^[[:space:]]*watchtower:/ { 
        in_watchtower = 1
        indent = match($0, /[^[:space:]]/) - 1
        next 
    }
    in_watchtower {
        current_indent = match($0, /[^[:space:]]/) - 1
        # Check if we hit a new service at same or lower indent level
        if (/^[[:space:]]*[a-z_-]+:/ && current_indent <= indent && !/^[[:space:]]*-/) {
            in_watchtower = 0
            print
        }
        # Skip lines that are part of watchtower config
        next
    }
    { print }
    ' "$COMPOSE_FILE" > "${COMPOSE_FILE}.tmp"
    mv "${COMPOSE_FILE}.tmp" "$COMPOSE_FILE"
    log_success "Removed old Watchtower configuration"
fi

# Find the line number of the top-level 'volumes:' section
VOLUMES_LINE=$(grep -n "^volumes:" "$COMPOSE_FILE" | tail -1 | cut -d: -f1)

if [ -n "$VOLUMES_LINE" ]; then
    # Insert watchtower before the volumes section
    head -n $((VOLUMES_LINE - 1)) "$COMPOSE_FILE" > "${COMPOSE_FILE}.tmp"
    echo "" >> "${COMPOSE_FILE}.tmp"
    echo "$WATCHTOWER_CONFIG" >> "${COMPOSE_FILE}.tmp"
    echo "" >> "${COMPOSE_FILE}.tmp"
    tail -n +$VOLUMES_LINE "$COMPOSE_FILE" >> "${COMPOSE_FILE}.tmp"
    mv "${COMPOSE_FILE}.tmp" "$COMPOSE_FILE"
else
    # No top-level volumes section, append at end
    echo "" >> "$COMPOSE_FILE"
    echo "$WATCHTOWER_CONFIG" >> "$COMPOSE_FILE"
fi

log_success "Watchtower configuration added"

# Validate the compose file syntax
log "Validating docker-compose.yml syntax..."
cd "$COMPOSE_DIR"
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    if ! docker compose config > /dev/null 2>&1; then
        log_error "docker-compose.yml syntax error! Restoring backup..."
        cp "$BACKUP_FILE" "$COMPOSE_FILE"
        exit 1
    fi
elif command -v docker-compose &> /dev/null; then
    if ! docker-compose config > /dev/null 2>&1; then
        log_error "docker-compose.yml syntax error! Restoring backup..."
        cp "$BACKUP_FILE" "$COMPOSE_FILE"
        exit 1
    fi
fi
log_success "Syntax validation passed"

#---------------------------------------
# Restart containers
#---------------------------------------
log_step "7/7" "Starting containers..."

cd "$COMPOSE_DIR"

# Stop existing watchtower if running (to avoid conflicts)
if docker ps --format '{{.Names}}' | grep -q "watchtower"; then
    log "Stopping existing Watchtower container..."
    docker stop watchtower > /dev/null 2>&1 || true
    docker rm watchtower > /dev/null 2>&1 || true
fi

# Start all containers
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    docker compose up -d
elif command -v docker-compose &> /dev/null; then
    docker-compose up -d
else
    log_error "Neither 'docker compose' nor 'docker-compose' found!"
    exit 1
fi

# Wait for containers to start
log "Waiting for containers to initialize..."
sleep 5

# Verify all containers are running
FAILED_CONTAINERS=""
for container in $(docker compose ps --format '{{.Names}}' 2>/dev/null || docker-compose ps --format '{{.Names}}' 2>/dev/null); do
    STATUS=$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)
    if [ "$STATUS" != "true" ]; then
        FAILED_CONTAINERS="$FAILED_CONTAINERS $container"
    fi
done

if [ -n "$FAILED_CONTAINERS" ]; then
    log_warning "Some containers may not be running properly:$FAILED_CONTAINERS"
    log "Check with: docker ps -a"
fi

#---------------------------------------
# Summary
#---------------------------------------
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
if [ "$MODE" = "update" ]; then
    echo -e "${GREEN}✓ Watchtower configuration updated!${NC}"
else
    echo -e "${GREEN}✓ Watchtower installation complete!${NC}"
fi
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Show running containers
log "${YELLOW}Running containers:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -E "NAME|n8n|watchtower|traefik" || true

echo ""
log "${GREEN}Summary:${NC}"
log "  • n8n container: ${N8N_CONTAINER}"
log "  • Update schedule: Every day at ${UPDATE_TIME}:00 ${TIMEZONE}"
log "  • Backup location: ${BACKUP_FILE}"
echo ""
log "${BLUE}Watchtower will automatically update n8n every night at ${UPDATE_TIME}:00.${NC}"
echo ""
log "${YELLOW}Useful commands:${NC}"
log "  • Check logs:     docker logs watchtower"
log "  • Force update:   docker exec watchtower /watchtower --run-once"
log "  • Change time:    UPDATE_TIME=3 <run this script again>"
echo ""

#---------------------------------------
# Self-cleanup
#---------------------------------------
if [ "$CLEANUP_SCRIPT" = "true" ]; then
    SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || echo "")
    if [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ] && [[ "$SCRIPT_PATH" != *"/dev/"* ]]; then
        rm -f "$SCRIPT_PATH"
        log_success "Setup script removed."
    fi
fi

exit 0
