#!/bin/bash
# Title: Fetch DOHMH rodent initial inspections
# Data source: NYC Open Data p937-wjvj (Rodent Inspection), inspection_type='Initial' (~2.12M rows)
# Note: dataset contains junk dates (1918..2045); filtered downstream in aggregation.
set -euo pipefail
mkdir -p "$(dirname "$0")/../data"
cd "$(dirname "$0")/../data"
out=inspections_initial.csv
: > "$out"
offset=0; page=100000
while true; do
  tmp=$(mktemp)
  # Socrata reports anonymous per-IP throttling as a 403, not a 429, so the retry
  # has to cover all errors: curl's default set skips 403 and one blip would kill
  # a 21-page pull. After the retries are spent curl still fails and set -e stops us.
  curl -sf -G "https://data.cityofnewyork.us/resource/p937-wjvj.csv" \
    --retry 5 --retry-delay 15 --retry-all-errors --max-time 600 \
    --data-urlencode "\$select=inspection_date,result,latitude,longitude,borough" \
    --data-urlencode "\$where=inspection_type='Initial'" \
    --data-urlencode "\$order=job_id" \
    --data-urlencode "\$limit=$page" --data-urlencode "\$offset=$offset" > "$tmp"
  rows=$(( $(wc -l < "$tmp") - 1 ))
  if [ "$rows" -le 0 ]; then rm "$tmp"; break; fi
  if [ "$offset" -eq 0 ]; then cat "$tmp" >> "$out"; else tail -n +2 "$tmp" >> "$out"; fi
  rm "$tmp"
  offset=$((offset + page))
  echo "  $offset fetched..."
  if [ "$rows" -lt "$page" ]; then break; fi
done
total=$(( $(wc -l < "$out") - 1 ))
echo "inspections_initial.csv: $total rows"
if [ "$total" -lt 2000000 ]; then
  echo "FATAL: only $total rows (expected ~2.1M)." >&2; exit 1
fi
echo DONE
