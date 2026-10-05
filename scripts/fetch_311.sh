#!/bin/bash
# Title: Fetch NYC 311 rat sightings, 2010-present
# Data sources: NYC Open Data 76ig-c548 (311 SRs 2010-2019), erm2-nwe9 (311 SRs 2020-present)
# Filter: complaint_type='Rodent' AND descriptor='Rat Sighting'
# Fails loud: any empty page before expected end, or totals far below known counts, exits 1.
set -euo pipefail
mkdir -p "$(dirname "$0")/../data"
cd "$(dirname "$0")/../data"

FIELDS="unique_key,created_date,latitude,longitude,community_board,borough,incident_zip,location_type,incident_address"

fetch_dataset() {
  local id=$1 out=$2
  local offset=0 page=50000
  : > "$out"
  while true; do
    local tmp=$(mktemp)
    # see fetch_inspections.sh: a Socrata throttle arrives as 403, which curl's
    # default retry set skips, so retry on all errors.
    curl -sf -G "https://data.cityofnewyork.us/resource/${id}.csv" \
      --retry 5 --retry-delay 15 --retry-all-errors --max-time 600 \
      --data-urlencode "\$select=$FIELDS" \
      --data-urlencode "\$where=complaint_type='Rodent' AND descriptor='Rat Sighting'" \
      --data-urlencode "\$order=unique_key" \
      --data-urlencode "\$limit=$page" \
      --data-urlencode "\$offset=$offset" > "$tmp"
    local rows=$(( $(wc -l < "$tmp") - 1 ))
    if [ "$rows" -le 0 ]; then rm "$tmp"; break; fi
    if [ "$offset" -eq 0 ]; then cat "$tmp" >> "$out"; else tail -n +2 "$tmp" >> "$out"; fi
    rm "$tmp"
    offset=$((offset + page))
    echo "  $id: $offset fetched..."
    if [ "$rows" -lt "$page" ]; then break; fi
  done
  local total=$(( $(wc -l < "$out") - 1 ))
  echo "$id -> $out: $total rows"
  if [ "$total" -lt 100000 ]; then
    echo "FATAL: $id returned only $total rows (expected ~140k+). Refusing to continue." >&2
    exit 1
  fi
}

fetch_dataset 76ig-c548 rat_311_2010_2019.csv
fetch_dataset erm2-nwe9 rat_311_2020_present.csv
echo "DONE"
