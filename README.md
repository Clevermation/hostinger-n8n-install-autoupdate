# n8n Auto-Update with Watchtower

Automatically update n8n installations with a single command.

Created by [Clevermation](https://clevermation.com)

## Quick Install

```bash
ssh root@SERVER_IP 'curl -fsSL https://raw.githubusercontent.com/Clevermation/hostinger-n8n-install-autoupdate/main/setup-watchtower-n8n.sh | bash'
```

## Custom Update Time

```bash
# Update at 3:00 AM
ssh root@SERVER_IP 'UPDATE_TIME=3 curl -fsSL https://raw.githubusercontent.com/Clevermation/hostinger-n8n-install-autoupdate/main/setup-watchtower-n8n.sh | bash'
```

## Change Existing Schedule

Just run the command again with a new time – it will update the existing configuration.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `UPDATE_TIME` | `2` | Hour to run updates (0-23) |
| `TIMEZONE` | `Europe/Berlin` | Timezone |

## What it does

1. Finds docker-compose.yml automatically
2. Detects running n8n container
3. Creates backup
4. Adds/updates Watchtower service
5. Validates syntax
6. Restarts containers
7. Removes itself

## Useful Commands

```bash
# Check logs
docker logs watchtower

# Force update now
docker exec watchtower /watchtower --run-once

# Check containers
docker ps
```

## Requirements

- Docker + docker-compose
- Running n8n container
- Root access

---

Made with ❤️ by [Clevermation](https://clevermation.com)
