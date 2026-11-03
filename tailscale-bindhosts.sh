#!/system/bin/sh
# tailscale-bindhosts - generate MagicDNS /etc/hosts entries and hand them to
# bindhosts (required).
#
# This is the runtime entry point.  service.sh wraps the boot subcommand and
# action.sh calls apply; customize.sh and uninstall.sh are deliberately simple
# install/cleanup hooks and never source common.sh.
#
# Commands are listed by usage() below; `boot` is the internal service hook.
#
# Apply is manual by design.  There is no cron job and no background loop.

SELF=$0
while [ -L "$SELF" ]; do
	LINK=$(readlink "$SELF" 2>/dev/null) || break
	case "$LINK" in
		/*) SELF=$LINK ;;
		*) SELF=$(dirname "$SELF")/$LINK ;;
	esac
done
MODDIR=$(cd "$(dirname "$SELF")" 2>/dev/null && pwd)
[ -f "$MODDIR/lib/common.sh" ] || MODDIR=/data/adb/modules/tailscale-bindhosts
. "$MODDIR/lib/common.sh"

usage() {
	cat <<'EOF'
tailscale-bindhosts - MagicDNS hosts generator

  status                 print key=value status
  detect                 list detected (bin, socket) pairs
  use <n>                use the n-th detected pair
  set <key> <value>      update one config value
  preview                print the hosts lines that would be applied
  apply                  generate and apply now (manual, no timer)
  unapply                remove the applied entries (keep module/config)
  test                   run the configured tailscale binary
  log [lines]            print the module log (default 100 lines)

Config keys:
  TS_BIN TS_SOCKET TS_ARGS ADD_SHORT ADD_IPV6 ADD_SELF BOOT_APPLY
EOF
}

cmd_detect() {
	if ! tsh_refresh_candidates; then
		tsh_error "$TSH_LAST_ERROR"
		return 1
	fi

	if [ ! -s "$TSH_CANDIDATES" ]; then
		printf 'no tailscale binary found\n'
		return 1
	fi

	# awk (not `read`) so an empty socket field is preserved: tab is IFS
	# whitespace and would otherwise be collapsed with the next tab.
	tsh_awk -F '\t' -v cur_bin="$TS_BIN" -v cur_sock="$TS_SOCKET" '
		{
			n++
			printf "[%d] %s\n", n, $3
			printf "    bin:    %s\n", $1
			if ($2 == "" && $3 == "KyuubiRan/Shellscaled")
				printf "    socket: default (managed by wrapper)\n"
			else
				printf "    socket: %s\n", ($2 == "" ? "default" : $2)
			printf "    source: %s\n", $4
			if ($1 == cur_bin && $2 == cur_sock)
				printf "    (current)\n"
			printf "\n"
		}
	' "$TSH_CANDIDATES"
	return 0
}

cmd_use() {
	tsh_n=${1:-}
	case "$tsh_n" in
		''|*[!0-9]*)
			printf 'usage: tailscale-bindhosts use <n>\n' >&2
			return 2
			;;
	esac

	tsh_load_config
	if ! tsh_refresh_candidates; then
		tsh_error "$TSH_LAST_ERROR"
		return 1
	fi

	if ! tsh_select_candidate "$tsh_n"; then
		tsh_error "no candidate $tsh_n; run detect again"
		return 1
	fi

	tsh_save_config || {
		tsh_error "failed to save config"
		return 1
	}

	printf 'ok: TS_BIN=%s\n' "$TS_BIN"
	printf 'ok: TS_SOCKET=%s\n' "${TS_SOCKET:-<default>}"
	return 0
}

cmd_set() {
	tsh_load_config
	tsh_set "$@" || return $?
	printf 'ok\n'
}

cmd_preview() {
	local tsh_preview

	tsh_load_config
	if [ -z "$TS_BIN" ]; then
		printf '[*] no TS_BIN configured; auto-detecting...\n' >&2
		if ! tsh_ensure_config; then
			tsh_error "$TSH_LAST_ERROR"
			return 1
		fi
		printf '[+] auto-selected: %s\n' "$TS_BIN" >&2
	fi

	# Generate into a temporary file so preview never changes entries.txt or
	# the last-applied snapshot.
	tsh_preview="$TSH_DIR/preview.$$"
	if ! tsh_generate_entries "$tsh_preview"; then
		rm -f "$tsh_preview"
		tsh_error "$TSH_LAST_ERROR"
		return 1
	fi

	cat "$tsh_preview"
	rm -f "$tsh_preview"
}

cmd_apply() {
	tsh_load_config

	if [ -z "$TS_BIN" ]; then
		printf '[*] no TS_BIN configured; auto-detecting...\n'
		if ! tsh_ensure_config; then
			tsh_error "$TSH_LAST_ERROR"
			return 1
		fi
		printf '[+] auto-selected: %s\n' "$TS_BIN"
		printf '[+] socket: %s\n' "${TS_SOCKET:-default}"
		printf '\n'
	fi

	printf '[*] tailscale-bindhosts apply\n'
	printf '    bin:     %s\n' "${TS_BIN:-<not configured>}"
	printf '    socket:  %s\n' "${TS_SOCKET:-default}"
	printf '    repo:    %s\n' "$(tsh_repo_for_bin "${TS_BIN:-/nonexistent}")"
	printf '    target:  %s\n' "$(tsh_bh_target)"
	printf '    custom:  %s\n' "$BH_CUSTOM"
	printf '    options: short=%s ipv6=%s self=%s\n' "$ADD_SHORT" "$ADD_IPV6" "$ADD_SELF"
	printf '\n'

	if ! tsh_apply; then
		tsh_error "$TSH_LAST_ERROR"
		return 1
	fi

	tsh_stats
	tsh_count=$TSH_STATS_ENTRIES

	printf '[+] %s nodes, %s entries (%s IPv4, %s IPv6)\n' \
		"$TSH_STATS_NODES" "$tsh_count" "$TSH_STATS_V4" "$TSH_STATS_V6"
	printf '[+] wrote %s\n' "$BH_CUSTOM"
	printf '[+] injected %s\n' "$(tsh_bh_target)"
	printf '\n    # entries\n'

	tsh_list_n=0
	while IFS= read -r tsh_line && [ "$tsh_list_n" -lt 40 ]; do
		printf '    %s\n' "$tsh_line"
		tsh_list_n=$((tsh_list_n + 1))
	done < "$TSH_ENTRIES"
	[ "$tsh_count" -gt 40 ] &&
		printf '    ... (%s more)\n' "$((tsh_count - 40))"

	printf '\n[+] done\n'
}

cmd_test() {
	local tsh_out tsh_rc

	tsh_load_config
	if [ -z "$TS_BIN" ]; then
		tsh_error "TS_BIN is empty; run detect then use <n>"
		return 1
	fi
	if [ ! -x "$TS_BIN" ]; then
		tsh_error "tailscale binary is not executable: $TS_BIN"
		return 1
	fi

	tsh_init
	tsh_out="$TSH_DIR/test.$$"
	tsh_rc=0

	printf '### binary\n%s\n' "$TS_BIN"
	printf '### version\n'
	if ! tsh_ts_timeout 20 version > "$tsh_out" 2>&1; then
		tsh_rc=1
	fi
	head -n 5 "$tsh_out"

	printf '### status\n'
	if ! tsh_ts_timeout 20 status > "$tsh_out" 2>&1; then
		tsh_rc=1
	fi
	head -n 25 "$tsh_out"

	rm -f "$tsh_out"
	if [ "$tsh_rc" -ne 0 ]; then
		tsh_error "one or more tailscale commands failed"
	fi
	return "$tsh_rc"
}

cmd_log() {
	tsh_lines=${1:-100}
	case "$tsh_lines" in
		''|*[!0-9]*) tsh_lines=100 ;;
	esac
	[ -f "$TSH_LOG" ] || {
		printf '(no log yet)\n'
		return 0
	}
	tail -n "$tsh_lines" "$TSH_LOG"
}

# ---------------------------------------------------------------------------
# runtime hooks (called by the manager scripts in the module root)
# ---------------------------------------------------------------------------

cmd_boot() {
	[ "$BOOT_APPLY" = "1" ] || {
		tsh_log "boot apply disabled, waiting for a manual apply"
		tsh_update_description "$(tsh_describe)"
		return 0
	}

	if ! tsh_bh_installed; then
		tsh_set_error "bindhosts is not installed"
		tsh_record_failure
		tsh_log "bindhosts is not installed; skipping boot apply"
		return 0
	fi

	if ! tsh_ensure_config; then
		tsh_log "boot auto-config failed: $TSH_LAST_ERROR"
		tsh_record_failure
		return 0
	fi

	(
		tsh_attempt=0
		while [ "$tsh_attempt" -lt 24 ]; do
			if [ -n "$TS_BIN" ] && [ -x "$TS_BIN" ]; then
				if tsh_ts_timeout 8 status --json 2>/dev/null | grep -q '"HostName"'; then
					break
				fi
			fi
			tsh_attempt=$((tsh_attempt + 1))
			sleep 5
		done

		# bindhosts creates /data/adb/hosts (mode 3) or the redirect file
		# (mode 4) from its own service.sh; give it a moment to win the
		# boot race before injecting.
		tsh_target=$(tsh_bh_target)
		tsh_attempt=0
		while [ -n "$tsh_target" ] && [ ! -f "$tsh_target" ] &&
			[ "$tsh_attempt" -lt 12 ]; do
			tsh_attempt=$((tsh_attempt + 1))
			sleep 5
		done
		tsh_apply
	) >> "$TSH_LOG" 2>&1 &

	return 0
}

tsh_load_config

case "${1:-}" in
	status) tsh_status ;;
	detect) cmd_detect ;;
	use)
		shift
		cmd_use "$@"
		;;
	set)
		shift
		cmd_set "$@"
		;;
	preview) cmd_preview ;;
	apply) cmd_apply ;;
	unapply) tsh_unapply ;;
	test) cmd_test ;;
	log)
		shift
		cmd_log "$@"
		;;
	boot) cmd_boot ;;
	-h|--help|help|'') usage ;;
	*)
		printf 'unknown command: %s\n\n' "$1" >&2
		usage >&2
		exit 2
		;;
esac
