#!/usr/bin/env bash
# ==============================================================================
# Script: brave-ext-copy.sh
# Description: Pick extensions from a source Brave (isolated) profile and install
#              the chosen ones into a target profile — by opening each one's
#              Chrome Web Store page in the target so you click "Add" once.
#
#   Why not just copy the files? Chromium signs each profile's extension list
#   with a machine-specific HMAC ("Secure Preferences"); a file-level copy gets
#   detected as tampering and the extension is disabled/removed. The Web Store
#   path is the only robust per-profile install.
#
# Usage: brave-ext-copy [source-profile]      (source defaults to "kenp")
#        ISOLATED_ROOT=... brave-ext-copy
# ==============================================================================
set -uo pipefail

ISOLATED_ROOT="${ISOLATED_ROOT:-$HOME/.brave/isolated}"
SOURCE="${1:-kenp}"
WEBSTORE="https://chromewebstore.google.com/detail"

# Extra extensions to always offer for install, even when they aren't in the
# source profile. One per line: "<32-char id><TAB><display name>". The id is
# the last path segment of the Chrome Web Store URL
# (…/detail/<slug>/<id>?…  ->  the <id> part).
EXTRA_EXTENSIONS=(
	"aapbdbdomjkkjkaonfhkkikfgjllcleb"$'\t'"Google Translate"
)

src_dir="$ISOLATED_ROOT/$SOURCE/Default"
src_pref="$src_dir/Preferences"
src_ext="$src_dir/Extensions"
[[ -d "$src_ext" ]] || { echo "Kaynak profil eklentileri yok: $src_ext" >&2; exit 1; }

command -v fzf >/dev/null || { echo "fzf gerekli (kurulu değil)." >&2; exit 1; }

# Resolve an extension's display name. Preferences usually holds the resolved
# name; when it's a localized "__MSG_key__" placeholder, look it up in the
# extension's _locales messages.
resolve_name() {
	local id="$1"
	local name=""
	name="$(jq -r --arg id "$id" '.extensions.settings[$id].manifest.name // empty' "$src_pref" 2>/dev/null)"

	if [[ -z "$name" || "$name" == __MSG_* ]]; then
		local extdir="$src_ext/$id" ver mf key locale msg
		ver="$(ls -1 "$extdir" 2>/dev/null | sort -V | tail -1)"
		mf="$extdir/$ver/manifest.json"
		[[ -f "$mf" ]] || { printf '%s' "$id"; return; }
		[[ -z "$name" ]] && name="$(jq -r '.name // empty' "$mf" 2>/dev/null)"
		if [[ "$name" == __MSG_* ]]; then
			key="${name#__MSG_}"; key="${key%__}"
			locale="$(jq -r '.default_locale // "en"' "$mf" 2>/dev/null)"
			for l in "$locale" en en_US en_GB; do
				msg="$(jq -r --arg k "$key" '.[$k].message // empty' \
					"$extdir/$ver/_locales/$l/messages.json" 2>/dev/null)"
				[[ -n "$msg" ]] && { printf '%s' "$msg"; return; }
			done
		fi
	fi
	printf '%s' "${name:-$id}"
}

# Build the "id<TAB>name" list from the extensions actually present in the
# source profile dir (skips Brave's internal Temp dir).
items=()
for d in "$src_ext"/*/; do
	id="$(basename "$d")"
	[[ "$id" == "Temp" ]] && continue
	[[ "$id" =~ ^[a-p]{32}$ ]] || continue   # extension ids are 32 chars a-p
	items+=("$id"$'\t'"$(resolve_name "$id")")
done

# Append the curated extras that aren't already present in the source profile.
for ex in "${EXTRA_EXTENSIONS[@]}"; do
	ex_id="${ex%%$'\t'*}"
	for it in "${items[@]}"; do [[ "${it%%$'\t'*}" == "$ex_id" ]] && continue 2; done
	items+=("$ex")
done

((${#items[@]})) || { echo "'$SOURCE' içinde eklenti bulunamadı." >&2; exit 1; }

# Pick the target profile (the other isolated profiles).
mapfile -t profiles < <(find "$ISOLATED_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
target="$(printf '%s\n' "${profiles[@]}" \
	| fzf --no-multi --height=40% --reverse --prompt="Hedef profil > ")"
[[ -n "$target" ]] || { echo "Hedef seçilmedi."; exit 0; }
[[ "$target" == "$SOURCE" ]] && { echo "Hedef kaynakla aynı ($SOURCE) — iptal."; exit 0; }

# Multi-select the extensions (display the name, keep the id).
selected="$(printf '%s\n' "${items[@]}" | sort -f -t$'\t' -k2 \
	| fzf --multi --reverse --height=70% --with-nth=2.. --delimiter=$'\t' \
		--prompt="$SOURCE -> $target  (TAB ile çoklu seç, Enter onayla) > " \
		--header='Seçtiğin eklentilerin Web Store sayfaları hedef profilde açılır; her birinde "Add" tıkla.')"
[[ -n "$selected" ]] || { echo "Bir şey seçilmedi."; exit 0; }

urls=()
while IFS=$'\t' read -r id name; do
	[[ -n "$id" ]] || continue
	urls+=("$WEBSTORE/$id")
	echo "  + $name"
done <<< "$selected"

echo
echo "${#urls[@]} Web Store sayfası '$target' profilinde açılıyor — her birinde \"Add to Brave\"e tıkla."
if command -v "start-brave-$target" >/dev/null 2>&1; then
	"start-brave-$target" "${urls[@]}" >/dev/null 2>&1 &
else
	# Fallback: launch the target's isolated profile directly.
	brave_cmd="$(command -v brave-origin-beta || command -v brave-browser || command -v brave)"
	[[ -n "$brave_cmd" ]] || { echo "start-brave-$target ve brave bulunamadı." >&2; exit 1; }
	"$brave_cmd" --user-data-dir="$ISOLATED_ROOT/$target" --profile-directory=Default \
		"${urls[@]}" >/dev/null 2>&1 &
fi
disown 2>/dev/null || true
