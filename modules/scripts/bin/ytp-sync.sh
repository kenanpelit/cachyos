#!/usr/bin/env bash
# ytp-sync - mirror a YouTube playlist into a folder, numbered oldest first.
#
#   ytp-sync [options] [PLAYLIST_URL] [DIR]
#
# Defaults: the "LEARN 3000 English Words with Comprehensible Input" playlist
# into ~/Videos/vodka. Run it again at any time: only videos that are not yet
# in the folder are downloaded (a download archive remembers finished ones,
# failed ones are retried next run). Every video is saved as MP4 with its
# English subtitles (embedded, and as .srt next to the video). Extra languages
# (Turkish by default, YouTube's auto-translation) are fetched afterwards as
# .srt files only: YouTube rate-limits translated subtitles hard (429), so a
# missing one never costs the video - each run tries the missing ones again
# and stops at the first refusal. All videos are then named 001_<title>.mp4, 002_<title>.mp4, ... in upload
# order, oldest first, each as soon as it has finished (the playlist is
# fetched oldest first, so numbers rarely move). If a newly found video is older than ones already
# numbered, the numbers are shifted so the order stays right.
#
# Options:
#   -n, --dry-run          list what would be downloaded, change nothing
#   -r, --renumber-only    only (re)number the files already in DIR
#   -c, --refresh-cookies  refresh the YouTube cookies first (yt-cookies-youtube --force)
#   -p, --proxy URL        download through this proxy (e.g. socks5://host:1080)
#   -s, --subs LANGS       subtitles saved with the video (default: en)
#   -q, --quality HEIGHT   highest video height to fetch (default: 1080; 2160 = 4K)
#   -x, --extra-subs LANGS extra .srt languages, best effort (default: tr; '' = none)
#   -h, --help             this help
#
# Files: DIR/.ytp-sync/ holds archive.txt (finished ids), meta/<id>.info.json,
# names/<id> (current file name of each video) and incoming/ (downloads in
# progress). Delete a video's files AND its line in archive.txt to fetch it again.

set -Eeuo pipefail

DEFAULT_URL='https://www.youtube.com/playlist?list=PL60Dx6nQgiwdepCaaLC1uzKbvQ9C8o19W'
DEFAULT_DIR="$HOME/Videos/vodka"
COOKIES="${YTP_COOKIES:-$HOME/.config/yt-dlp/cookies-youtube.txt}"

max_height=1080 dry_run=0 renumber_only=0 refresh_cookies=0 proxy='' subs='en' extra_subs='tr'
args=()
while (($#)); do
  case "$1" in
    -n | --dry-run) dry_run=1 ;;
    -r | --renumber-only) renumber_only=1 ;;
    -c | --refresh-cookies) refresh_cookies=1 ;;
    -p | --proxy) proxy="${2:?--proxy needs a URL}"; shift ;;
    -s | --subs) subs="${2:?--subs needs languages}"; shift ;;
    -q | --quality) max_height="${2:?--quality needs a height, e.g. 720, 1080, 2160}"; shift ;;
    -x | --extra-subs) extra_subs="${2?--extra-subs needs languages}"; shift ;;
    -h | --help) sed -n '2,/^$/{s/^# \{0,1\}//;p}' "$0"; exit 0 ;;
    -*) echo "ytp-sync: unknown option $1 (see --help)" >&2; exit 2 ;;
    *) args+=("$1") ;;
  esac
  shift
done
url="${args[0]:-$DEFAULT_URL}"
dir="${args[1]:-$DEFAULT_DIR}"

for tool in yt-dlp jq ffmpeg flock; do
  command -v "$tool" >/dev/null || { echo "ytp-sync: $tool is not installed" >&2; exit 1; }
done

state="$dir/.ytp-sync"
mkdir -p "$state/meta" "$state/names" "$state/incoming"
touch "$state/archive.txt"

# One run per folder at a time. yt-dlp's per-video renumber hook runs inside
# the locked run, so it skips the lock (YTP_SYNC_IN_RUN).
if [[ -z "${YTP_SYNC_IN_RUN:-}" ]]; then
  exec 9>"$state/lock"
  flock -n 9 || { echo "ytp-sync: another run is already working on $dir" >&2; exit 1; }
fi

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# The video's own title as a file name: only "/" (impossible in a Linux file
# name) becomes "-", control characters go, whitespace is squeezed, and very
# long titles are cut at 150 characters.
safe_title() {
  local t
  t=$(printf '%s' "$1" | tr '/' '-' | tr -d '\000-\037' | tr -s ' ')
  t="${t#"${t%%[![:space:]]*}"}"
  t="${t%"${t##*[![:space:]]}"}"
  printf '%s' "${t:0:150}"
}

# Move every file of one video (video + subtitles) from one base name to another.
move_set() {
  local from="$1" to="$2" f suffix
  shopt -s nullglob
  for f in "$dir/$from".*; do
    suffix="${f#"$dir/$from"}"
    mv -n -- "$f" "$dir/$to$suffix"
  done
  shopt -u nullglob
}

# Number every downloaded video by upload date (then upload time, playlist
# position, id) and rename the ones whose name is not right yet.
renumber() {
  local -a rows=()
  local info id current
  shopt -s nullglob
  for info in "$state/meta"/*.info.json; do
    id=$(basename "$info" .info.json)
    # A video is ready once yt-dlp has written its final <id>.mp4 (merging and
    # embedding work on other names). Only then do its files leave incoming/,
    # all together, so a video never shows up in DIR without its subtitles.
    if [[ -f "$state/incoming/$id.mp4" ]]; then
      [[ -f "$state/names/$id" ]] || printf '%s' ".new-$id" >"$state/names/$id"
      current=$(<"$state/names/$id")
      local f suffix
      for f in "$state/incoming/$id".*; do
        [[ "$f" == *.part || "$f" == *.ytdl || "$f" == *.temp.* || "$f" == *.f[0-9]* ]] && continue
        suffix="${f#"$state/incoming/$id"}"
        mv -f -- "$f" "$dir/$current$suffix"
      done
    fi
    [[ -f "$state/names/$id" ]] || continue
    current=$(<"$state/names/$id")
    [[ -f "$dir/$current.mp4" ]] || continue
    # The thumbnail is embedded in the MP4; a loose copy is clutter.
    rm -f -- "$dir/$current".webp "$dir/$current".jpg
    local row
    if ! row=$(jq -r --arg id "$id" '[(.upload_date // "99999999"), ((.timestamp // 0) | tostring), ((.playlist_index // 0) | tostring), $id, (.title // $id)] | @tsv' "$info" 2>/dev/null); then
      echo "ytp-sync: unreadable $info, skipping $id this time" >&2
      continue
    fi
    rows+=("$row")
  done
  shopt -u nullglob
  ((${#rows[@]})) || return 0

  local count=${#rows[@]} width=3
  ((count > 999)) && width=${#count}

  # Sort, then work out the wanted name of each video.
  local -a ids=() wants=()
  local n=0 title
  while IFS=$'\t' read -r _ _ _ id title; do
    n=$((n + 1))
    ids+=("$id")
    wants+=("$(printf '%0*d' "$width" "$n")_$(safe_title "$title")")
  done < <(printf '%s\n' "${rows[@]}" | sort -t $'\t' -k1,1 -k2,2n -k3,3n -k4,4)

  # Two passes, so a shift (002 -> 003 while 003 -> 004) never collides.
  local i changed=0
  local -a first_name=()
  for i in "${!ids[@]}"; do
    current=$(<"$state/names/${ids[$i]}")
    first_name[i]="$current"
    [[ "$current" == "${wants[$i]}" ]] && continue
    move_set "$current" ".renumber-${ids[$i]}"
    printf '%s' ".renumber-${ids[$i]}" >"$state/names/${ids[$i]}"
    changed=$((changed + 1))
  done
  for i in "${!ids[@]}"; do
    current=$(<"$state/names/${ids[$i]}")
    [[ "$current" == "${wants[$i]}" ]] && continue
    move_set "$current" "${wants[$i]}"
    printf '%s' "${wants[$i]}" >"$state/names/${ids[$i]}"
    [[ "${first_name[$i]}" == .new-* ]] && say "new: ${wants[$i]}.mp4"
  done
  ((changed == 0)) || say "$count videos in $dir"
}

if ((renumber_only)); then
  renumber
  exit 0
fi

if ((refresh_cookies)); then
  say "Refreshing the YouTube cookies"
  yt-cookies-youtube --force
fi

common=(
  --ignore-config
  --js-runtimes deno --remote-components ejs:github
  --sleep-requests 1 --sleep-interval 8 --max-sleep-interval 20 --sleep-subtitles 5
  --retries 5 --extractor-retries 3 --fragment-retries 5 --retry-sleep 'http:exp=2:60'
  --socket-timeout 30 --concurrent-fragments 1
)
[[ -f "$COOKIES" ]] && common+=(--cookies "$COOKIES")
[[ -n "$proxy" ]] && common+=(--proxy "$proxy")

if ((dry_run)); then
  say "Playlist: $url"
  total=0 new=0
  while read -r id title; do
    total=$((total + 1))
    if ! grep -q "^youtube $id\$" "$state/archive.txt"; then
      new=$((new + 1))
      printf '  new: %s  %s\n' "$id" "$title"
    fi
  done < <(yt-dlp "${common[@]}" --flat-playlist --print '%(id)s %(title)s' "$url")
  say "$total videos in the playlist, $new not downloaded yet (nothing was changed)"
  exit 0
fi

say "Syncing $url"
say "into $dir"
set +e
yt-dlp "${common[@]}" \
  --yes-playlist --playlist-reverse \
  --download-archive "$state/archive.txt" \
  -f "bv*[height<=$max_height][ext=mp4]+ba[ext=m4a]/bv*[height<=$max_height]+ba/b[height<=$max_height]/bv*+ba/b" \
  --quiet --progress --no-warnings \
  --merge-output-format mp4 \
  --paths "$state/incoming" \
  -o '%(id)s.%(ext)s' \
  -o "infojson:$state/meta/%(id)s" \
  --write-info-json --no-write-playlist-metafiles --no-clean-info-json \
  --write-subs --write-auto-subs --sub-langs "$subs" --convert-subs srt --embed-subs \
  --embed-metadata --embed-chapters --embed-thumbnail \
  --ignore-errors \
  --exec "after_move:YTP_SYNC_IN_RUN=1 $(printf '%q' "$(readlink -f "$0")") --renumber-only $(printf '%q' "$url") $(printf '%q' "$dir") #" \
  --no-overwrites --continue --no-mtime \
  "$url"
rc=$?
set -e

renumber

# Extra subtitle languages as sidecar .srt files, for every video that lacks
# one. Stop at the first refusal: hammering a 429 only prolongs the block.
fetch_extra_subs() {
  [[ -n "$extra_subs" ]] || return 0
  local lang id current f got=0 missing=0
  local -a langs
  IFS=',' read -ra langs <<<"$extra_subs"
  shopt -s nullglob
  for lang in "${langs[@]}"; do
    for f in "$state/names"/*; do
      id=$(basename "$f")
      current=$(<"$f")
      [[ -f "$dir/$current.mp4" && ! -f "$dir/$current.$lang.srt" ]] || continue
      missing=$((missing + 1))
      rm -f "$state/incoming/subs-$id".*
      yt-dlp "${common[@]}" --skip-download --no-playlist \
        --write-subs --write-auto-subs --sub-langs "$lang" --convert-subs srt \
        --paths "$state/incoming" -o "subs-$id.%(ext)s" \
        "https://www.youtube.com/watch?v=$id" || true
      if [[ -s "$state/incoming/subs-$id.$lang.srt" ]]; then
        mv -f -- "$state/incoming/subs-$id.$lang.srt" "$dir/$current.$lang.srt"
        got=$((got + 1))
      else
        rm -f "$state/incoming/subs-$id".*
        say "YouTube refused the '$lang' subtitles; the rest are tried on the next run"
        break 2
      fi
    done
  done
  shopt -u nullglob
  ((missing == 0)) || say "Extra subtitles: $got of $missing fetched"
}
((rc == 130)) || fetch_extra_subs

# Ids in the playlist that are still not in the archive failed this time.
if ((rc != 0)); then
  echo
  echo "Some videos could not be downloaded (private/deleted ones always fail); run ytp-sync again later to retry the rest." >&2
  echo "If YouTube says \"Sign in to confirm you're not a bot\" or 429 Too Many Requests:" >&2
  echo "  - refresh the cookies:  ytp-sync --refresh-cookies" >&2
  echo "  - wait a while, or switch the Mullvad relay / try without the VPN" >&2
  echo "  - or go through another exit:  ytp-sync --proxy socks5://<host>:1080" >&2
fi
exit "$rc"
