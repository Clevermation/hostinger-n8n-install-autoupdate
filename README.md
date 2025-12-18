# n8n Auto-Update with Watchtower

Automatically update n8n installations with a single command. Created by [Clevermation](https://clevermation.com).

## Quick Install

Run this command on your server (via SSH):

```bash
curl -fsSL https://raw.githubusercontent.com/clevermation/n8n-watchtower/main/setup-watchtower-n8n.sh | bash
```

Or from your local machine:

```bash
ssh root@SERVER_IP 'curl -fsSL https://raw.githubusercontent.com/clevermation/n8n-watchtower/main/setup-watchtower-n8n.sh | bash'
```

## Features

- ✅ **Auto-detection** - Finds docker-compose.yml and n8n container automatically
- ✅ **Safe updates** - Creates backup before any changes
- ✅ **Syntax validation** - Validates config before restarting
- ✅ **Update mode** - Run again to change settings (e.g., update time)
- ✅ **Self-cleanup** - Removes itself after completion
- ✅ **Rolling restart** - Minimal downtime during updates

## Configuration

Default update time is **02:00** (Europe/Berlin). Customize with environment variables:

```bash
# Change update time to 3:00 AM
UPDATE_TIME=3 curl -fsSL https://raw.githubusercontent.com/clevermation/n8n-watchtower/main/setup-watchtower-n8n.sh | bash

# Change timezone
TIMEZONE=Europe/London UPDATE_TIME=4 curl -fsSL ... | bash

# Keep the script (don't delete after run)
CLEANUP_SCRIPT=false curl -fsSL ... | bash
```

| Variable | Default | Description |
|----------|---------|-------------|
| `UPDATE_TIME` | `2` | Hour to run updates (0-23) |
| `TIMEZONE` | `Europe/Berlin` | Timezone for scheduling |
| `CLEANUP_SCRIPT` | `true` | Delete script after completion |

## Update Existing Installation

Simply run the script again with a new time:

```bash
ssh root@SERVER_IP 'UPDATE_TIME=4 curl -fsSL https://raw.githubusercontent.com/clevermation/n8n-watchtower/main/setup-watchtower-n8n.sh | bash'
```

The script will detect the existing Watchtower config and update it.

## What gets added to docker-compose.yml

```yaml
  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_SCHEDULE=0 0 2 * * *
      - WATCHTOWER_ROLLING_RESTART=true
      - WATCHTOWER_INCLUDE_RESTARTING=true
      - TZ=Europe/Berlin
    command: root-n8n-1
```

## After Installation

```bash
# Check Watchtower logs
docker logs watchtower

# Force an immediate update check
docker exec watchtower /watchtower --run-once

# Check all running containers
docker ps

# Restore from backup (if needed)
cp /root/docker-compose.yml.backup.YYYYMMDD_HHMMSS /root/docker-compose.yml
docker compose up -d
```

## Security Features

- **Pre-flight checks**: Verifies root access, Docker installation, valid parameters
- **Backup creation**: Always creates timestamped backup before changes
- **Syntax validation**: Validates docker-compose.yml before restarting
- **Safe removal**: Only modifies Watchtower section, leaves rest untouched
- **Container health check**: Verifies containers start correctly

## Requirements

- Docker with docker-compose (v1 or v2)
- Running n8n container
- Root or sudo access
- curl

## Troubleshooting

**Script can't find docker-compose.yml:**
```bash
# Specify path manually (future feature) or check:
find / -name "docker-compose.yml" 2>/dev/null
```

**Watchtower not updating:**
```bash
# Check logs for errors
docker logs watchtower

# Verify container name matches
docker ps --format '{{.Names}}' | grep n8n
```

## License

MIT License - Feel free to use and modify.

---

Made with ❤️ by [Clevermation](https://clevermation.com)
