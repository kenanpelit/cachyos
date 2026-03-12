#!/usr/bin/env bash
# ==============================================================================
# Script: osc-pass.sh
# Description: Multi-store `pass(1)` wrapper with built-in stores, interactive selection, audit, migrate, and git backup helpers.
# Usage: osc-pass.sh [stores|current|path|mkdir|init|env|audit|migrate|select] [args]
# ==============================================================================

set -euo pipefail

SCRIPT_NAME="${0##*/}"
AUTO_GIT_BACKUP="${OSC_PASS_AUTO_GIT_BACKUP:-1}"

declare -A STORE_PATHS=()

die() {
	echo "Error: $*" >&2
	exit 1
}

warn() {
	echo "Warning: $*" >&2
}

info() {
	echo "$*"
}

trim() {
	local value="$1"
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s' "$value"
}

validate_store_name() {
	local store="$1"
	[[ "$store" =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid store name: $store"
}

refresh_store_map() {
	local path base name

	STORE_PATHS=()
	STORE_PATHS["personal"]="$HOME/.pass"
	STORE_PATHS["helium"]="$HOME/.passh"

	if [[ -e "$HOME/.password-store" ]]; then
		STORE_PATHS["default"]="$HOME/.password-store"
	fi

	shopt -s nullglob
	for path in "$HOME"/.pass-*; do
		[[ -e "$path" ]] || continue
		base="${path##*/}"
		name="${base#.pass-}"
		[[ -n "$name" ]] || continue
		[[ -n "${STORE_PATHS[$name]+x}" ]] && continue
		STORE_PATHS["$name"]="$path"
	done
	shopt -u nullglob
}

sorted_store_names() {
	(( ${#STORE_PATHS[@]} == 0 )) && return 0
	printf '%s\n' "${!STORE_PATHS[@]}" | sort
}

default_store_path() {
	local store="$1"

	validate_store_name "$store"

	case "$store" in
	default)
		printf '%s\n' "$HOME/.password-store"
		;;
	personal)
		printf '%s\n' "$HOME/.pass"
		;;
	helium)
		printf '%s\n' "$HOME/.passh"
		;;
	*)
		printf '%s\n' "$HOME/.pass-$store"
		;;
	esac
}

store_exists() {
	[[ -n "${STORE_PATHS[$1]+x}" ]]
}

store_path() {
	local store="$1"

	validate_store_name "$store"
	refresh_store_map

	if store_exists "$store"; then
		printf '%s\n' "${STORE_PATHS[$store]}"
	else
		default_store_path "$store"
	fi
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

require_pass() {
	require_command pass
}

require_gpg() {
	require_command gpg
}

require_fzf() {
	require_command fzf
}

store_state() {
	local path="$1"
	local status="-"
	local gpgid="-"

	if [[ -d "$path" ]]; then
		if [[ -s "$path/.gpg-id" ]]; then
			status="initialized"
			gpgid="$(paste -sd, "$path/.gpg-id")"
		else
			status="dir exists"
		fi
	else
		status="missing"
	fi

	printf '%s\t%s\n' "$status" "$gpgid"
}

print_usage() {
	refresh_store_map

	cat <<EOF

Usage:
  $SCRIPT_NAME stores
  $SCRIPT_NAME current
  $SCRIPT_NAME path <store>
  $SCRIPT_NAME mkdir <store>
  $SCRIPT_NAME init <store> <gpg-id...>
  $SCRIPT_NAME env <store>
  $SCRIPT_NAME audit [store]
  $SCRIPT_NAME migrate <src-store> <dst-store> [--move] [--force]
  $SCRIPT_NAME select [pass-args...]
  $SCRIPT_NAME <store> <pass-args...>
  $SCRIPT_NAME <pass-args...>      # fzf store picker if available

Notes:
  - Built-in stores: personal -> ~/.pass, helium -> ~/.passh
  - Additional stores are auto-discovered from ~/.pass-<name>
  - Unknown store names resolve to ~/.pass-<name>
  - Git backup runs automatically after successful changes when the store is a git repo

Examples:
  $SCRIPT_NAME stores
  $SCRIPT_NAME mkdir archive
  $SCRIPT_NAME init helium ABCDEF0123456789
  $SCRIPT_NAME personal show gmail
  $SCRIPT_NAME archive insert servers/login01
  $SCRIPT_NAME show gmail
  $SCRIPT_NAME audit
  $SCRIPT_NAME migrate personal helium --force

Available stores:
$(while IFS= read -r store; do printf '  %-12s -> %s\n' "$store" "${STORE_PATHS[$store]}"; done < <(sorted_store_names))

EOF
}

list_stores() {
	local store path status_line status gpgid

	refresh_store_map

	printf "%-12s %-40s %-14s %s\n" "STORE" "PATH" "STATUS" "GPG"
	printf "%-12s %-40s %-14s %s\n" "-----" "----" "------" "---"

	while IFS= read -r store; do
		path="${STORE_PATHS[$store]}"
		status_line="$(store_state "$path")"
		status="${status_line%%$'\t'*}"
		gpgid="${status_line#*$'\t'}"
		printf "%-12s %-40s %-14s %s\n" "$store" "$path" "$status" "$gpgid"
	done < <(sorted_store_names)
}

show_current() {
	if [[ -n "${PASSWORD_STORE_DIR:-}" ]]; then
		printf '%s\n' "$PASSWORD_STORE_DIR"
	else
		default_store_path personal
	fi
}

mkdir_store() {
	local store="$1"
	local path

	path="$(store_path "$store")"
	mkdir -p "$path"

	info "Created store directory:"
	info "  $path"
}

maybe_git_backup() {
	local path="$1"
	local label="$2"
	local message

	[[ "$AUTO_GIT_BACKUP" == "1" ]] || return 0
	command -v git >/dev/null 2>&1 || return 0
	git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
	[[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]] || return 0

	git -C "$path" add -A >/dev/null 2>&1 || {
		warn "git add failed for $path"
		return 0
	}

	if git -C "$path" diff --cached --quiet >/dev/null 2>&1; then
		return 0
	fi

	message="osc-pass: ${label} $(date -Iseconds)"

	if ! git -C "$path" commit -m "$message" >/dev/null 2>&1; then
		warn "git commit failed for $path"
		return 0
	fi

	if git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
		git -C "$path" push >/dev/null 2>&1 || warn "git push failed for $path"
	fi
}

init_store() {
	local store="$1"
	shift
	local path

	[[ $# -ge 1 ]] || die "Usage: $SCRIPT_NAME init <store> <gpg-id...>"

	require_pass
	require_gpg

	path="$(store_path "$store")"
	mkdir -p "$path"

	PASSWORD_STORE_DIR="$path" pass init "$@"
	maybe_git_backup "$path" "$store init"

	info
	info "Store initialized:"
	info "  name : $store"
	info "  path : $path"
	info "  gpg  : $*"
}

print_env() {
	local store="$1"
	local path

	path="$(store_path "$store")"
	printf 'export PASSWORD_STORE_DIR=%q\n' "$path"
}

select_store() {
	local row
	local store path status_line status gpgid

	refresh_store_map
	require_fzf

	row="$(
		while IFS= read -r store; do
			path="${STORE_PATHS[$store]}"
			status_line="$(store_state "$path")"
			status="${status_line%%$'\t'*}"
			gpgid="${status_line#*$'\t'}"
			printf '%s\t%s\t%s\t%s\n' "$store" "$path" "$status" "$gpgid"
		done < <(sorted_store_names) |
			fzf \
				--delimiter=$'\t' \
				--with-nth=1,3,4 \
				--prompt='osc-pass store> ' \
				--preview='printf "Path: %s\nStatus: %s\nGPG: %s\n" {2} {3} {4}'
	)" || return 130

	printf '%s\n' "${row%%$'\t'*}"
}

run_pass() {
	local store="$1"
	shift
	local path

	require_pass

	path="$(store_path "$store")"
	[[ -d "$path" ]] || die "Store directory missing: $path"

	PASSWORD_STORE_DIR="$path" pass "$@"
	maybe_git_backup "$path" "$store $*"
}

audit_store() {
	local store="$1"
	local path
	local issue_count=0
	local recipient

	path="$(store_path "$store")"

	if [[ ! -d "$path" ]]; then
		warn "$store: missing directory ($path)"
		return 1
	fi

	if [[ ! -s "$path/.gpg-id" ]]; then
		warn "$store: missing or empty .gpg-id"
		return 1
	fi

	while IFS= read -r recipient || [[ -n "$recipient" ]]; do
		recipient="$(trim "$recipient")"
		[[ -n "$recipient" ]] || continue

		if gpg --list-secret-keys "$recipient" >/dev/null 2>&1 || gpg --list-keys "$recipient" >/dev/null 2>&1; then
			continue
		fi

		warn "$store: unresolved gpg recipient '$recipient'"
		issue_count=$((issue_count + 1))
	done <"$path/.gpg-id"

	if (( issue_count == 0 )); then
		info "$store: OK ($path)"
		return 0
	fi

	return 1
}

audit_all_stores() {
	local store
	local failed=0

	refresh_store_map

	while IFS= read -r store; do
		audit_store "$store" || failed=$((failed + 1))
	done < <(sorted_store_names)

	(( failed == 0 )) || return 1
}

ensure_destination_initialized() {
	local src_path="$1"
	local dst_path="$2"
	local -a recipients=()

	[[ -s "$dst_path/.gpg-id" ]] && return 0
	[[ -s "$src_path/.gpg-id" ]] || die "Destination store is not initialized and source store has no .gpg-id"

	mapfile -t recipients <"$src_path/.gpg-id"
	(( ${#recipients[@]} > 0 )) || die "Source .gpg-id is empty"

	PASSWORD_STORE_DIR="$dst_path" pass init "${recipients[@]}"
}

migrate_store() {
	local src_store="$1"
	local dst_store="$2"
	shift 2

	local move_mode=0
	local force_mode=0
	local src_path dst_path file rel entry

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--move)
			move_mode=1
			;;
		-f | --force)
			force_mode=1
			;;
		*)
			die "Unknown migrate option: $1"
			;;
		esac
		shift
	done

	require_pass
	require_gpg

	src_path="$(store_path "$src_store")"
	dst_path="$(store_path "$dst_store")"

	[[ -d "$src_path" ]] || die "Source store directory missing: $src_path"
	mkdir -p "$dst_path"
	ensure_destination_initialized "$src_path" "$dst_path"

	while IFS= read -r -d '' file; do
		rel="${file#$src_path/}"
		entry="${rel%.gpg}"

		if [[ -f "$dst_path/$rel" && "$force_mode" != "1" ]]; then
			warn "Skipping existing entry: $entry"
			continue
		fi

		if [[ "$force_mode" == "1" ]]; then
			PASSWORD_STORE_DIR="$src_path" pass show "$entry" | PASSWORD_STORE_DIR="$dst_path" pass insert -m -f "$entry" >/dev/null
		else
			PASSWORD_STORE_DIR="$src_path" pass show "$entry" | PASSWORD_STORE_DIR="$dst_path" pass insert -m "$entry" >/dev/null
		fi

		info "Migrated: $entry"

		if [[ "$move_mode" == "1" ]]; then
			PASSWORD_STORE_DIR="$src_path" pass rm -rf "$entry" >/dev/null
		fi
	done < <(find "$src_path" -type f -name '*.gpg' -print0)

	maybe_git_backup "$dst_path" "$dst_store migrate from $src_store"
	[[ "$move_mode" == "1" ]] && maybe_git_backup "$src_path" "$src_store migrate to $dst_store"
}

run_selected_store() {
	local store

	store="$(select_store)"
	[[ $# -eq 0 ]] && {
		printf '%s\n' "$store"
		return 0
	}

	run_pass "$store" "$@"
}

main() {
	local cmd

	[[ $# -ge 1 ]] || {
		print_usage
		exit 1
	}

	cmd="$1"
	shift || true

	case "$cmd" in
	help | -h | --help)
		print_usage
		;;
	stores)
		list_stores
		;;
	current)
		show_current
		;;
	path)
		[[ $# -eq 1 ]] || die "Usage: $SCRIPT_NAME path <store>"
		store_path "$1"
		;;
	mkdir)
		[[ $# -eq 1 ]] || die "Usage: $SCRIPT_NAME mkdir <store>"
		mkdir_store "$1"
		;;
	init)
		[[ $# -ge 2 ]] || die "Usage: $SCRIPT_NAME init <store> <gpg-id...>"
		init_store "$@"
		;;
	env)
		[[ $# -eq 1 ]] || die "Usage: $SCRIPT_NAME env <store>"
		print_env "$1"
		;;
	audit)
		if [[ $# -eq 0 ]]; then
			audit_all_stores
		elif [[ $# -eq 1 ]]; then
			audit_store "$1"
		else
			die "Usage: $SCRIPT_NAME audit [store]"
		fi
		;;
	migrate)
		[[ $# -ge 2 ]] || die "Usage: $SCRIPT_NAME migrate <src-store> <dst-store> [--move] [--force]"
		migrate_store "$@"
		;;
	select)
		run_selected_store "$@"
		;;
	*)
		refresh_store_map
		if store_exists "$cmd"; then
			[[ $# -ge 1 ]] || die "No pass arguments provided"
			run_pass "$cmd" "$@"
		elif command -v fzf >/dev/null 2>&1; then
			run_selected_store "$cmd" "$@"
		else
			die "Unknown command/store: $cmd"
		fi
		;;
	esac
}

main "$@"
