#!/usr/bin/env sh
# ==============================================================================
# m3u2csv.py - Convert M3U playlists to TSV (name, group, url)
# ------------------------------------------------------------------------------
# Usage:
#   m3u2csv.py INPUT.m3u OUTPUT.csv
# Notes:
#   - Outputs tab-separated values (TSV) with 3 columns: name, group, url
#   - Designed to be installed as an extensionless executable (m3u2csv)
# ==============================================================================
if [ "$#" -lt 2 ]; then
  echo "usage: m3u2csv INPUT.m3u OUTPUT.csv" >&2
  exit 2
fi
in="$1"
out="$2"
awk '
  BEGIN { OFS = "\t"; want = 0; name = ""; group = "" }
  /^#EXTINF/ {
    group = ""
    if (match($0, /group-title="[^"]*"/)) {
      group = substr($0, RSTART + 13, RLENGTH - 14)
    }
    n = split($0, parts, ",")
    name = parts[n]
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
    want = 1
    next
  }
  /^[^#]/ && $0 != "" {
    if (want == 1) {
      print name, group, $0
      want = 0
    }
  }
' "$in" > "$out"
