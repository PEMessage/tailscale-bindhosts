# shellcheck shell=sh
# shellcheck disable=SC3043  # local is supported by Android mksh / busybox ash
# High-level actions: auto-config, apply, unapply.
#
# Sourced by lib/common.sh after status.sh.

tsh_record_failure() {
	tsh_write_state 0 "${1:-0}" "$TSH_LAST_ERROR"
	tsh_update_description "$(tsh_describe)"
}

# Take the first detected (bin, socket) pair and persist it.  Used when TS_BIN
# is empty, e.g. the Action button on a fresh install.
tsh_pick_first_candidate() {
	tsh_refresh_candidates || return 1

	if ! tsh_select_candidate 1; then
		tsh_set_error "no tailscale binary detected; run 'tailscale-bindhosts detect'"
		return 1
	fi

	tsh_save_config || {
		tsh_set_error "failed to save auto-detected config"
		return 1
	}

	tsh_log "auto-config: bin='$TS_BIN' socket='$TS_SOCKET'"
	return 0
}

# Ensure TS_BIN is set.  Only an empty value triggers detection; a stale but
# explicitly configured path is left alone and reported by the normal error.
tsh_ensure_config() {
	tsh_load_config
	[ -n "$TS_BIN" ] && return 0
	tsh_pick_first_candidate
}

# Remember the rows that are now present in the target.  bindhosts may later
# rewrite the target without our markers, so this snapshot is used to remove
# rows whose nodes disappear before the next apply.
tsh_snapshot_applied() {
	local tsh_tmp

	tsh_init
	tsh_tmp="$TSH_APPLIED.tmp.$$"
	if cp "$TSH_ENTRIES" "$tsh_tmp" 2>/dev/null &&
		mv -f "$tsh_tmp" "$TSH_APPLIED"; then
		chmod 644 "$TSH_APPLIED" 2>/dev/null
		return 0
	fi

	rm -f "$tsh_tmp"
	tsh_log "WARN: failed to save applied entries snapshot"
	return 1
}

# Generate entries, persist them for bindhosts, and inject them now.
tsh_apply() {
	local tsh_count tsh_target

	tsh_load_config
	tsh_init

	if ! tsh_ensure_config; then
		tsh_record_failure
		return 1
	fi

	tsh_log "apply: bin='$TS_BIN' socket='$TS_SOCKET' short=$ADD_SHORT ipv6=$ADD_IPV6 self=$ADD_SELF"

	if ! tsh_bh_installed; then
		tsh_set_error "bindhosts is required but not installed ($BH_MODDIR)"
		tsh_record_failure
		return 1
	fi
	if ! tsh_bh_available; then
		tsh_set_error "bindhosts is disabled; enable it before applying"
		tsh_record_failure
		return 1
	fi

	# Seed the cleanup snapshot on upgrade from a version that did not keep
	# one.  The old entries file is the best available approximation.
	if [ ! -s "$TSH_APPLIED" ] && [ -s "$TSH_ENTRIES" ]; then
		tsh_snapshot_applied
	fi

	if ! tsh_generate_entries; then
		tsh_record_failure
		return 1
	fi

	tsh_stats
	tsh_count=$TSH_STATS_ENTRIES

	tsh_write_bindhosts_custom || {
		tsh_record_failure "$tsh_count"
		return 1
	}

	tsh_target=$(tsh_bh_target)
	if ! tsh_inject "$tsh_target"; then
		# The custom file is already written; bindhosts will pick it up on
		# its next run, but report the failure now.
		tsh_record_failure "$tsh_count"
		return 1
	fi

	tsh_snapshot_applied
	tsh_log "applied $tsh_count entries to $tsh_target (bindhosts)"
	tsh_write_state 1 "$tsh_count" ""
	tsh_update_description "$(tsh_describe)"
	tsh_log "apply done: $tsh_count entries"
	return 0
}

# Remove our block, the bindhosts extension file and the generated cache.
# Keeps config and log, so a later apply can rebuild everything.
tsh_unapply() {
	local tsh_target tsh_rc

	tsh_load_config

	if tsh_bh_installed; then
		tsh_target=$(tsh_bh_target)
		tsh_strip "$tsh_target"
		tsh_rc=$?
		case "$tsh_rc" in
			0)
				printf 'ok: removed entries from %s\n' "$tsh_target"
				;;
			2)
				printf 'ok: nothing to clean in %s (file not found)\n' \
					"$tsh_target"
				;;
			3)
				tsh_set_error "hosts file is not writable: $tsh_target"
				tsh_error "$TSH_LAST_ERROR"
				tsh_record_failure
				return 1
				;;
			*)
				tsh_error "${TSH_LAST_ERROR:-failed to remove entries from $tsh_target}"
				tsh_record_failure
				return 1
				;;
		esac
	fi

	rm -f "$BH_CUSTOM"
	tsh_clean_generated
	tsh_update_description "$(tsh_describe)"
	printf 'ok: removed %s\n' "$BH_CUSTOM"
	return 0
}
