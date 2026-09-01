# MediathekView Headless

`mediathekview-headless` provides search, downloads, subscriptions, download
history, and a local HTTP API without starting Swing, X11, Wayland, or a
virtual display. It is a standalone Java 17 application and does not change
the existing MediathekView desktop entry point.

Searches and exact entry lookups use the current MediathekViewWeb API. Media
is downloaded from the broadcaster URL returned for the selected entry.
Progressive files use Java's HTTP client; HLS playlists use `ffmpeg`.

## Build

Requirements:

- JDK 17 or newer
- `ffmpeg` at runtime when an entry only provides HLS

From the repository root:

```bash
JAVA_HOME=/path/to/jdk ./mvnw -f headless/pom.xml clean verify
java -jar headless/target/mediathekview-headless.jar --help
```

The fat JAR is `headless/target/mediathekview-headless.jar`.

## CLI

Global options such as `--state` and `--base-url` go before the subcommand.
`--timeout` controls catalog and subtitle requests and the ffmpeg network I/O
stall timeout. Complete media transfers have a separate six-hour safety cap.

Search and return human-readable rows:

```bash
java -jar headless/target/mediathekview-headless.jar \
  search "Die Sendung mit der Maus" --channel WDR --limit 5
```

Add `--json` for scripting. Each result has a stable `id`; use it for an
exact lookup or download:

```bash
java -jar headless/target/mediathekview-headless.jar \
  show --id 'ENTRY_ID' --json

java -jar headless/target/mediathekview-headless.jar \
  download --id 'ENTRY_ID' \
  --output /mnt/media/MediathekView-Downloads \
  --subdirectory Maus --quality HD
```

The output root must already exist and be writable. Downloads are written to
a partial file in the destination directory and renamed only after success.
The SQLite history prevents downloading the same entry ID twice. New filenames
carry a fingerprint of the selected media URL. Before a download, the output
tree is indexed by normalized episode title plus that source identity; legacy
MediathekView filenames carrying a ten-digit URL hash are recognized too.
Files without recoverable source identity are not used for deduplication,
because title-only matching can suppress distinct recurring episodes.
`--force` overrides the history and library checks for a one-off download.

Other commands:

```bash
java -jar headless/target/mediathekview-headless.jar \
  --state /var/lib/mediathekview-headless/history.db history --json

java -jar headless/target/mediathekview-headless.jar \
  --state /var/lib/mediathekview-headless/history.db \
  sync --config /etc/mediathekview-headless/subscriptions.json

java -jar headless/target/mediathekview-headless.jar \
  --state /var/lib/mediathekview-headless/history.db \
  sync --config /etc/mediathekview-headless/subscriptions.json --dry-run
```

## Subscriptions

Copy [`subscriptions.example.json`](subscriptions.example.json), set an
existing `outputDirectory`, and add one or more rules. Query clauses inside a
subscription use MediathekViewWeb's field-grouping behavior. Put words that
must all occur in the same field into one clause, such as `Anna Haustiere`.
Separate clauses targeting the same field can behave as alternatives. A clause
can search `channel`, `topic`, `title`, and/or `description`.

`maxResults` limits the newest matches considered in one run and defaults to
10. Matching entries are downloaded oldest-first within that window. The
history database makes later runs idempotent. Subscription names must be
unique within a config file.

Optional case-insensitive regular-expression filters are applied after the
catalog query and before `maxResults`:

- `includeTitleRegex` and `excludeTitleRegex`
- `includeTopicRegex` and `excludeTopicRegex`

The client pages through catalog results until it has found `maxResults`
entries that pass the filters. This matters for programs such as *Die Sendung
mit der Maus*, where standard, audio-description, and sign-language editions
share the same timestamp. Invalid regular expressions are reported as
subscription errors. Catalog entries that resolve to the same selected media
URL are treated as one item within a subscription, avoiding duplicate ARD/BR
copies of the same episode. The configured output tree is scanned recursively
before planning a sync. Identity-bearing existing videos are reported as
`already-in-library`; source-fingerprinted headless filenames and legacy names
ending in a ten-digit URL hash are both recognized.

Run `sync --dry-run` first, then run one ordinary `sync` before enabling a
timer. A dry run queries the live catalog and checks history without creating
output directories, downloading media, or writing history rows. An empty
history means the first ordinary run downloads all matching entries in the
configured result window.

## HTTP API

Start the server on loopback:

```bash
java -jar headless/target/mediathekview-headless.jar \
  --state /var/lib/mediathekview-headless/history.db \
  serve --bind 127.0.0.1 --port 7070 \
  --config /etc/mediathekview-headless/subscriptions.json
```

Endpoints:

- `GET /health`
- `POST /api/search` — a MediathekViewWeb search request
- `POST /api/entries` — JSON array of exact entry IDs
- `GET /api/downloads` — recent local download history
- `POST /api/downloads` — queue `{id, subdirectory, quality, subtitles}`
- `POST /api/sync` — queue one subscription run

Examples:

```bash
curl --fail --silent --show-error \
  -H 'Content-Type: application/json' \
  --data '{"queries":[{"fields":["title","topic"],"query":"Maus"}],"size":5,"future":false}' \
  http://127.0.0.1:7070/api/search

curl --fail --silent --show-error \
  -H 'Content-Type: application/json' \
  --data '{"id":"ENTRY_ID","subdirectory":"Maus","quality":"HD","subtitles":true}' \
  http://127.0.0.1:7070/api/downloads
```

The API has no authentication and therefore binds to `127.0.0.1` by default.
Use SSH port forwarding or place an authenticated reverse proxy in front of
it; do not bind it to an untrusted network as-is. The complete contract is in
[`openapi.yaml`](openapi.yaml).

## systemd

Example units are in [`systemd/`](systemd/). They assume:

- JAR: `/opt/mediathekview-headless/mediathekview-headless.jar`
- config: `/etc/mediathekview-headless/subscriptions.json`
- state: `/var/lib/mediathekview-headless/history.db`
- service user: `admin`
- NAS mount: `/mnt/nas-china-01/Kinder`

The API service requires the NAS mount and is sandboxed with write access only
to its state directory and the configured media library. The timer calls
the loopback API hourly, so subscription work stays serialized by the API's
single download worker.

## Deployment

The live instance builds on the host; no artifact is uploaded.

- build checkout: `/opt/mediathekview-headless-src`, owned by `admin`, tracking
  `origin/master` at `https://github.com/jttdev/MediathekView.git`
- deployed JAR: `/opt/mediathekview-headless/mediathekview-headless.jar`,
  `root:root`, mode `0644`
- superseded JARs stay alongside it as
  `mediathekview-headless.jar.bak-<deployed-commit>-<UTC timestamp>`

`/opt/MediathekView` (upstream GUI distribution) and
`/opt/src/MediathekView-headless` (stale root-owned checkout) are not the
deploy source.

Deploys go through `master`: merge and push there first, then build on the host
as `admin`, whose home holds the Maven wrapper and dependency cache.

```bash
cd /opt/mediathekview-headless-src
git pull --ff-only
./mvnw -o -f headless/pom.xml package
```

The POM targets `release 17`, so build with a JDK between 17 and 21 — **JDK 25
cannot compile it** (`Releaseversion 17 nicht unterstützt`). The host default is
JDK 21; on the dev machine, where JDK 25 is the default, pass
`JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64`.

Installing and restarting need root. SSH as `admin` cannot `sudo`
non-interactively, so run these through the MeshCentral agent, which is root:

```bash
curl -sS http://127.0.0.1:7070/api/downloads   # confirm nothing is mid-download
cp -f /opt/mediathekview-headless/mediathekview-headless.jar \
  "/opt/mediathekview-headless/mediathekview-headless.jar.bak-<deployed-commit>-$(date -u +%Y%m%dT%H%M%SZ)"
install -o root -g root -m 0644 \
  /opt/mediathekview-headless-src/headless/target/mediathekview-headless.jar \
  /opt/mediathekview-headless/mediathekview-headless.jar
systemctl restart mediathekview-headless-api.service
curl --fail -sS http://127.0.0.1:7070/health
```

Finish by posting `/api/sync` once and reading the journal, so a broken build
surfaces immediately rather than at the next timer run.

## Backfilling a single episode

A download that fails is retried on later syncs, because only completed or
already-in-library entries are skipped. Retries reach an episode only while it
is still inside its subscription's `maxResults` window, so an old episode that
newer ones have pushed out of that window is lost until it is fetched by hand.

Queue it through the running API, which serializes it with the single download
worker; a second JVM would write `history.db` concurrently:

```bash
curl -sS -X POST -H 'Content-Type: application/json' \
  --data '{"id":"ENTRY_ID","subdirectory":"Anna und das wilde Wissen","quality":"HD","subtitles":true}' \
  http://127.0.0.1:7070/api/downloads
```

Resolve `ENTRY_ID` first with `POST /api/search`; MediathekViewWeb entry IDs
are not stable across film-list rebuilds, so an ID from an old history row is
usually stale.
