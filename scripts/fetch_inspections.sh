#!/bin/bash
# Title: Fetch DOHMH rodent initial inspections
# Data source: NYC Open Data p937-wjvj (Rodent Inspection), inspection_type='Initial' (~2.16M rows)
# Note: dataset contains junk dates (1918..2045); filtered downstream in aggregation.
#
# Paged on Socrata's :id, not $offset. Offset paging rescans the result set for
# every page, so each page costs more than the one before it: the 100k page at
# offset 300000 measured ~53s and at 400000 ~70s, and on 2026-10-05 a later page
# gave up and failed the weekly refresh (curl exit 22). Keyset paging on :id uses
# the index and stays flat -- the same page size 1.5M rows deep returns in under
# 2s. :id is Socrata's unique, stable row identifier, so unlike job_id
# (2,157,751 rows but only 2,157,485 distinct) it cannot drop or repeat a row at
# a page boundary.
# Fails loud: a short total exits 1 and leaves the published data alone.
set -euo pipefail
mkdir -p "$(dirname "$0")/../data"
cd "$(dirname "$0")/../data"

out=inspections_initial.csv
page=100000
last=""
: > "$out"

while true; do
  tmp=$(mktemp)
  where="inspection_type='Initial'"
  if [ -n "$last" ]; then where="$where AND :id > '$last'"; fi
  # see fetch_311.sh: a Socrata throttle arrives as 403, which curl's default
  # retry set skips, so retry on all errors.
  curl -sf -G "https://data.cityofnewyork.us/resource/p937-wjvj.csv" \
    --retry 5 --retry-delay 15 --retry-all-errors --max-time 600 \
    --data-urlencode "\$select=:id,inspection_date,result,latitude,longitude,borough" \
    --data-urlencode "\$where=$where" \
    --data-urlencode "\$order=:id" \
    --data-urlencode "\$limit=$page" > "$tmp"
  # Split the key off the data: the page's last :id addresses the next request,
  # and the remaining columns append to $out under a header written once.
  last=$(python3 - "$tmp" "$out" <<'PY'
import csv, os, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, newline="") as fh:
    rows = list(csv.reader(fh))
if len(rows) < 2:
    sys.exit(0)
head, body = rows[0], rows[1:]
with open(dst, "a", newline="") as fh:
    w = csv.writer(fh)
    if os.path.getsize(dst) == 0:
        w.writerow(head[1:])
    w.writerows(r[1:] for r in body)
print(body[-1][0])
PY
)
  rm "$tmp"
  if [ -z "$last" ]; then break; fi
  echo "  $(( $(wc -l < "$out") - 1 )) fetched..."
done

total=$(( $(wc -l < "$out") - 1 ))
echo "inspections_initial.csv: $total rows"
if [ "$total" -lt 2000000 ]; then
  echo "FATAL: only $total rows (expected ~2.1M)." >&2; exit 1
fi
echo DONE
