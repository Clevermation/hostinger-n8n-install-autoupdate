#!/bin/bash

#===============================================================================
# Watchtower Setup Script for n8n Auto-Updates
# Created by Clevermation (clevermation.com)
# Version: 1.2.0
# 
# This script adds or updates Watchtower in an existing docker-compose.yml 
# to enable automatic nightly updates for n8n containers.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Clevermation/hostinger-n8n-install-autoupdate/main/setup-watchtower-n8n.sh | bash
#
# With custom time:
#   UPDATE_TIME=3 curl -fsSL ... | bash
#===============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
UPDATE_TIME="${UPDATE_TIME:-2}"
TIMEZONE="${TIMEZONE:-Europe/Berlin}"

log_success() { echo -e "${GREEN}✓ $1${NC}"; }
log_error() { echo -e "${RED}✗ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
log_step() { echo -e "${YELLOW}[$1]${NC} $2"; }

# Header
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║         Watchtower Setup for n8n Auto-Updates                 ║"
echo "║                   by Clevermation                             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

#---------------------------------------
# Pre-flight checks
#---------------------------------------
log_step "1/6" "Running pre-flight checks..."

if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

if ! command -v docker &> /dev/null || ! docker info &> /dev/null; then
    log_error "Docker is not installed or not running!"
    exit 1
fi

if ! [[ "$UPDATE_TIME" =~ ^[0-9]+$ ]] || [ "$UPDATE_TIME" -lt 0 ] || [ "$UPDATE_TIME" -gt 23 ]; then
    log_error "UPDATE_TIME must be between 0 and 23"
    exit 1
fi

log_success "Pre-flight checks passed"

#---------------------------------------
# Find docker-compose.yml
#---------------------------------------
log_step "2/6" "Searching for docker-compose.yml..."

COMPOSE_FILE=""
for path in "/root/docker-compose.yml" "/root/docker-compose.yaml" "/opt/n8n/docker-compose.yml"; do
    if [ -f "$path" ] && grep -q "n8n" "$path"; then
        COMPOSE_FILE="$path"
        break
    fi
done

if [ -z "$COMPOSE_FILE" ]; then
    COMPOSE_FILE=$(find /root /opt /home -maxdepth 4 -name "docker-compose.yml" -type f 2>/dev/null | while read f; do
        grep -q "n8n" "$f" 2>/dev/null && echo "$f" && break
    done)
fi

if [ -z "$COMPOSE_FILE" ] || [ ! -f "$COMPOSE_FILE" ]; then
    log_error "docker-compose.yml with n8n not found!"
    exit 1
fi

log_success "Found: ${COMPOSE_FILE}"
COMPOSE_DIR=$(dirname "$COMPOSE_FILE")

#---------------------------------------
# Find n8n container
#---------------------------------------
log_step "3/6" "Checking for n8n container..."

N8N_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i n8n | head -1)

if [ -z "$N8N_CONTAINER" ]; then
    log_error "No running n8n container found!"
    exit 1
fi

log_success "Found: ${N8N_CONTAINER}"

#---------------------------------------
# Detect mode
#---------------------------------------
log_step "4/6" "Configuring Watchtower..."

MODE="install"
if grep -q "watchtower:" "$COMPOSE_FILE"; then
    MODE="update"
    log_warning "Updating existing Watchtower configuration"
fi

#---------------------------------------
# Create backup
#---------------------------------------
BACKUP_FILE="${COMPOSE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$COMPOSE_FILE" "$BACKUP_FILE"
log_success "Backup: ${BACKUP_FILE}"

#---------------------------------------
# Update docker-compose.yml
#---------------------------------------
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
    awk '
    /^[[:space:]]*watchtower:/ { in_wt = 1; next }
    in_wt && /^[[:space:]]*[a-z_-]+:/ && !/^[[:space:]]*-/ { in_wt = 0 }
    !in_wt { print }
    ' "$COMPOSE_FILE" > "${COMPOSE_FILE}.tmp"
    mv "${COMPOSE_FILE}.tmp" "$COMPOSE_FILE"
fi

# Insert before volumes: section
VOLUMES_LINE=$(grep -n "^volumes:" "$COMPOSE_FILE" | tail -1 | cut -d: -f1)

if [ -n "$VOLUMES_LINE" ]; then
    head -n $((VOLUMES_LINE - 1)) "$COMPOSE_FILE" > "${COMPOSE_FILE}.tmp"
    echo "" >> "${COMPOSE_FILE}.tmp"
    echo "$WATCHTOWER_CONFIG" >> "${COMPOSE_FILE}.tmp"
    echo "" >> "${COMPOSE_FILE}.tmp"
    tail -n +$VOLUMES_LINE "$COMPOSE_FILE" >> "${COMPOSE_FILE}.tmp"
    mv "${COMPOSE_FILE}.tmp" "$COMPOSE_FILE"
else
    echo "" >> "$COMPOSE_FILE"
    echo "$WATCHTOWER_CONFIG" >> "$COMPOSE_FILE"
fi

log_success "Watchtower configuration added"

#---------------------------------------
# Validate syntax
#---------------------------------------
log_step "5/6" "Validating configuration..."

cd "$COMPOSE_DIR"
if ! docker compose config > /dev/null 2>&1 && ! docker-compose config > /dev/null 2>&1; then
    log_error "Syntax error! Restoring backup..."
    cp "$BACKUP_FILE" "$COMPOSE_FILE"
    exit 1
fi

log_success "Syntax valid"

#---------------------------------------
# Restart containers
#---------------------------------------
log_step "6/6" "Starting containers..."

# Stop existing watchtower
docker stop watchtower > /dev/null 2>&1 || true
docker rm watchtower > /dev/null 2>&1 || true

# Start all containers
if docker compose version &> /dev/null; then
    docker compose up -d
else
    docker-compose up -d
fi

sleep 5

#---------------------------------------
# Summary
#---------------------------------------
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Watchtower ${MODE} complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAME|n8n|watchtower|traefik" || true
echo ""
echo -e "Update schedule: ${GREEN}${UPDATE_TIME}:00 ${TIMEZONE}${NC}"
echo -e "Logs: ${YELLOW}docker logs watchtower${NC}"
echo ""

# Self-cleanup
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || echo "")
[ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ] && rm -f "$SCRIPT_PATH"

exit 0
