#!/bin/bash
# Export the result of the most recent subscription sync as node_exporter
# textfile metrics (pushed by node-exporter-push as archive-yj-janosch-home).
#
# The sync timer only queues POST /api/sync; the API runs the sync on its
# worker thread and reports failures solely as "Subscription sync error: ..." /
# "Subscription sync failed: ..." lines in its journal (a clean sync logs
# nothing). This runs as ExecStartPre of mediathekview-headless-sync.service,
# so it evaluates the previous run once its window has closed: the run is the
# last successful queue ({"status":"queued"} from curl), its errors are the API
# error lines logged since then. A queue that keeps failing stops advancing
# the run timestamp, which is the staleness signal.
set -u
TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/prometheus/node-exporter}"
f="$TEXTFILE_DIR/mediathekview_sync.prom"

run=$(journalctl -q --no-pager -u mediathekview-headless-sync.service --since -7d -o short-unix \
  | grep -F '"status":"queued"' | tail -n 1 | awk '{print int($1)}')
[ -n "$run" ] || exit 0

errors=$(journalctl -q --no-pager -u mediathekview-headless-api.service --since "@$run" -o cat \
  | grep -c -E '^Subscription sync (error|failed):')

success=$(awk '$1=="mediathekview_sync_last_success_timestamp_seconds"{print $2}' "$f" 2>/dev/null)
[ "$errors" -eq 0 ] && success=$run

{
  echo "# HELP mediathekview_sync_last_run_timestamp_seconds Unix time the most recent evaluated subscription sync was queued."
  echo "# TYPE mediathekview_sync_last_run_timestamp_seconds gauge"
  echo "mediathekview_sync_last_run_timestamp_seconds $run"
  if [ -n "$success" ]; then
    echo "# HELP mediathekview_sync_last_success_timestamp_seconds Unix time of the most recent subscription sync that logged no errors."
    echo "# TYPE mediathekview_sync_last_success_timestamp_seconds gauge"
    echo "mediathekview_sync_last_success_timestamp_seconds $success"
  fi
  echo "# HELP mediathekview_sync_errors_last_run Subscription errors the most recent evaluated sync logged."
  echo "# TYPE mediathekview_sync_errors_last_run gauge"
  echo "mediathekview_sync_errors_last_run $errors"
} > "$f.tmp" && mv "$f.tmp" "$f"
