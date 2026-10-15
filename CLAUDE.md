# MediathekView

This fork adds the standalone Java headless client under `headless/`. Read
`../CLAUDE.md` and `/home/janosch/DEV/CLAUDE.md` for workspace-wide rules.

## Live headless instance

- Host: CT 102 `archive-yj-janosch-home` (Debian 13, `10.18.0.12`, timezone
  `Asia/Singapore`) on the Proxmox host `minipc-china-01` at YJ Janosch Home.
  Build and mount details: `infra/infra-configs/proxmox/yjh/README.md`.
- Remote access: `ssh minipc-china-01` (root on the Proxmox host, over the YJ
  Janosch Home IPsec), then `pct enter 102` or `pct exec 102 -- <cmd>`, which is
  root in the CT. Fallback: MeshCentral node `minipc-china-01` (group "YJ
  Janosch Home") is the host, not the CT — reach the CT from it with `pct exec`.
- JAR: `/opt/mediathekview-headless/mediathekview-headless.jar`
- configuration: `/etc/mediathekview-headless/subscriptions.json`
- SQLite state/history: `/var/lib/mediathekview-headless/history.db`
- media library: `/mnt/nas-china-01/Kinder/Video/Mediathek`
- service account: `admin`

The API is `mediathekview-headless-api.service`. It listens without
authentication on loopback only at `http://127.0.0.1:7070`; never expose it
directly to an untrusted network. It requires the
`/mnt/nas-china-01/Kinder` NAS mount and has write access only to its state and
media-library paths.

`mediathekview-headless-sync.timer` queues `POST /api/sync` hourly with up to
five minutes of randomized delay. The API owns a single download worker, so
timer and manual work remain serialized. The checked-in unit sources are in
`headless/systemd/`; API usage and deployment assumptions are documented in
`headless/README.md`.

## Deploying

Deploys go through `master` and build on the host from
`/opt/mediathekview-headless-src` (owned by `admin`) — nothing is copied in from
a workstation. Build with a JDK between 17 and 21; **JDK 25 cannot compile this
POM**, so on the dev machine pass
`JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64`. Installing the JAR and
restarting the service need root, and SSH as `admin` cannot `sudo`
non-interactively — run those steps as root in the CT (`pct exec 102` from the
host). Back up the JAR being replaced before installing over it. Full runbook,
including single-episode backfills: `headless/README.md`.

## Read-only status checks

Run these in CT 102 (`pct exec 102 -- …` on `minipc-china-01`):

```bash
systemctl status mediathekview-headless-api.service \
  mediathekview-headless-sync.timer --no-pager -l
systemctl list-timers mediathekview-headless-sync.timer --no-pager
curl --fail --silent --show-error http://127.0.0.1:7070/health
curl --fail --silent --show-error http://127.0.0.1:7070/api/downloads
journalctl -u mediathekview-headless-api.service \
  -u mediathekview-headless-sync.service --since "24 hours ago" --no-pager
df -h /var/lib/mediathekview-headless /mnt/nas-china-01/Kinder
```

The sync oneshot exiting successfully means its request was queued, not that
all downloads finished. Use `/api/downloads` to confirm final download states.
