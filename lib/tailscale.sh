# shellcheck shell=sh
# shellcheck disable=SC3043  # local is supported by Android mksh / busybox ash
# Tailscale layer: invoke the CLI and turn status JSON into hosts entries.
#
# Detection lives in lib/detect.sh, which is loaded before this file.

# Timeout in seconds for the next tsh_ts call; empty means "no timeout".
TSH_TS_TIMEOUT=""

# Run the configured CLI with TS_ARGS and --socket applied.
tsh_ts() {
	# shellcheck disable=SC2086  # TS_ARGS is intentionally word-split
	if [ -n "$TS_SOCKET" ]; then
		set -- "$TS_BIN" $TS_ARGS --socket="$TS_SOCKET" "$@"
	else
		set -- "$TS_BIN" $TS_ARGS "$@"
	fi

	if [ -n "$TSH_TS_TIMEOUT" ] && command -v timeout >/dev/null 2>&1; then
		timeout "$TSH_TS_TIMEOUT" "$@"
	else
		"$@"
	fi
}

tsh_ts_timeout() {
	TSH_TS_TIMEOUT=$1
	shift
	tsh_ts "$@"
}

# Generate $TSH_ENTRIES from `tailscale status --json`.
tsh_generate_entries() {
	local tsh_json tsh_errfile tsh_peers tsh_parse_err tsh_build_err
	local tsh_rc tsh_msg tsh_raw tsh_sort_out tsh_out

	tsh_init
	tsh_out=${1:-$TSH_ENTRIES}
	tsh_json="$TSH_DIR/status.json"
	tsh_errfile="$TSH_DIR/tailscale.err"
	tsh_peers="$TSH_DIR/peers.tsv"
	tsh_parse_err="$TSH_DIR/parse.err"
	tsh_build_err="$TSH_DIR/build.err"

	if [ -z "$TS_BIN" ]; then
		tsh_set_error "no TS_BIN configured; run 'tailscale-bindhosts detect' then 'tailscale-bindhosts use <n>'"
		return 1
	fi
	if [ ! -x "$TS_BIN" ]; then
		tsh_set_error "tailscale binary is not executable: '$TS_BIN'"
		return 1
	fi

	tsh_ts_timeout 20 status --json > "$tsh_json" 2> "$tsh_errfile"
	tsh_rc=$?
	chmod 600 "$tsh_json" 2>/dev/null
	if [ "$tsh_rc" -ne 0 ]; then
		tsh_msg=$(tsh_read_message "$tsh_errfile")
		[ "$tsh_rc" -eq 124 ] && tsh_msg="timed out after 20s"
		tsh_set_error "tailscale status failed (rc=$tsh_rc): $tsh_msg"
		return 1
	fi

	if [ ! -s "$tsh_json" ]; then
		tsh_set_error "tailscale status returned empty output"
		return 1
	fi

	if ! tsh_awk -f "$MODDIR/lib/parse-status.awk" "$tsh_json" \
		> "$tsh_peers" 2> "$tsh_parse_err"; then
		tsh_set_error "failed to parse tailscale status: $(tsh_read_message "$tsh_parse_err")"
		return 1
	fi

	tsh_raw="$TSH_DIR/entries.raw"
	if ! tsh_awk -v self="$ADD_SELF" -v v6="$ADD_IPV6" -v short="$ADD_SHORT" \
		-f "$MODDIR/lib/build-entries.awk" "$tsh_peers" \
		> "$tsh_raw" 2> "$tsh_build_err"; then
		tsh_set_error "failed to build hosts entries: $(tsh_read_message "$tsh_build_err")"
		rm -f "$tsh_raw"
		return 1
	fi

	tsh_sort_out="$tsh_out.tmp.$$"
	if ! sort -u "$tsh_raw" > "$tsh_sort_out"; then
		tsh_set_error "failed to sort hosts entries"
		rm -f "$tsh_raw" "$tsh_sort_out"
		return 1
	fi

	mv -f "$tsh_sort_out" "$tsh_out"
	chmod 644 "$tsh_out" 2>/dev/null
	rm -f "$tsh_raw"

	if [ ! -s "$tsh_out" ]; then
		tsh_set_error "no MagicDNS names found (is tailscale logged in?)"
		return 1
	fi
	return 0
}
