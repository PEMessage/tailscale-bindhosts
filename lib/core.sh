# shellcheck shell=sh
# shellcheck disable=SC3043  # local is supported by Android mksh / busybox ash
# Core: paths, defaults, config, state, logging.
#
# Sourced by lib/common.sh (which is sourced by tailscale-bindhosts.sh only).
# Never exits the caller; functions only.

TSH_ADB="${TSH_ADB:-/data/adb}"

TSH_DIR="${TSH_DIR:-$TSH_ADB/tailscale-bindhosts}"
TSH_CONFIG="$TSH_DIR/config"
TSH_LOG="$TSH_DIR/tailscale-bindhosts.log"
TSH_STATE="$TSH_DIR/state"
TSH_ENTRIES="$TSH_DIR/entries.txt"
# Snapshot of the entries that were last written to a hosts file.  bindhosts
# may rewrite the target and strip our marker comments, so the current
# entries.txt is not enough to clean up rows that have since disappeared.
TSH_APPLIED="$TSH_DIR/entries.applied"
TSH_CANDIDATES="$TSH_DIR/candidates.tsv"

BH_MODDIR="${BH_MODDIR:-$TSH_ADB/modules/bindhosts}"
BH_PERSIST="${BH_PERSIST:-$TSH_ADB/bindhosts}"
BH_CUSTOM="$BH_PERSIST/custom-tailscale-bindhosts.txt"

# Magisk-Tailscaled family working directory (bin/, run/, settings.*).
TSH_TAILSCALE_DIR="${TSH_TAILSCALE_DIR:-$TSH_ADB/tailscale}"
# KernelSU-Tailscaled (WayneShao) persistent data directory.
TSH_KSU_TS_DIR="${TSH_KSU_TS_DIR:-$TSH_ADB/kernelsu-tailscaled}"

TSH_MARK_BEGIN='# >>> tailscale-bindhosts'
TSH_MARK_END='# <<< tailscale-bindhosts'

# Defaults; overwritten by tsh_load_config.
TS_BIN="${TS_BIN:-}"
TS_SOCKET="${TS_SOCKET:-}"
TS_ARGS="${TS_ARGS:-}"
ADD_SHORT="${ADD_SHORT:-1}"
ADD_IPV6="${ADD_IPV6:-1}"
ADD_SELF="${ADD_SELF:-1}"
BOOT_APPLY="${BOOT_APPLY:-0}"   # opt-in: one shot at boot, never a timer

# Last error, used for state reporting.
TSH_LAST_ERROR=""

tsh_init() {
	mkdir -p "$TSH_DIR" 2>/dev/null
}

# ---------------------------------------------------------------------------
# busybox / awk
# ---------------------------------------------------------------------------
tsh_find_busybox() {
	local tsh_b

	if [ "${TSH_BUSYBOX_CHECKED:-0}" = "1" ]; then
		[ -n "${TSH_BUSYBOX:-}" ]
		return
	fi

	TSH_BUSYBOX_CHECKED=1
	for tsh_b in busybox /data/adb/magisk/busybox /data/adb/ksu/bin/busybox \
		/data/adb/ap/bin/busybox; do
		if command -v "$tsh_b" >/dev/null 2>&1; then
			TSH_BUSYBOX=$tsh_b
			return 0
		fi
	done

	TSH_BUSYBOX=""
	return 1
}

tsh_awk() {
	if tsh_find_busybox; then
		"$TSH_BUSYBOX" awk "$@"
	else
		awk "$@"
	fi
}

# ---------------------------------------------------------------------------
# config
# ---------------------------------------------------------------------------
# Persisted keys, in the order tsh_save_config writes them.  Keep this list
# and lib/config.example in sync.
TSH_CONFIG_KEYS="TS_BIN TS_SOCKET TS_ARGS ADD_SHORT ADD_IPV6 ADD_SELF BOOT_APPLY"
TSH_CONFIG_BOOLS="ADD_SHORT ADD_IPV6 ADD_SELF BOOT_APPLY"

tsh_normalize_bool() {
	case "$1" in
		1|true|TRUE|on|ON|yes|YES) echo 1 ;;
		0|false|FALSE|off|OFF|no|NO|'') echo 0 ;;
		*) echo "$1" ;;
	esac
}

tsh_is_config_key() {
	local tsh_k

	for tsh_k in $TSH_CONFIG_KEYS; do
		[ "$tsh_k" = "$1" ] && return 0
	done
	return 1
}

tsh_is_bool_key() {
	local tsh_k

	for tsh_k in $TSH_CONFIG_BOOLS; do
		[ "$tsh_k" = "$1" ] && return 0
	done
	return 1
}

tsh_load_config() {
	local tsh_line tsh_key tsh_val

	[ -f "$TSH_CONFIG" ] || return 0
	while IFS= read -r tsh_line; do
		case "$tsh_line" in
			''|'#'*) continue ;;
		esac
		tsh_key=${tsh_line%%=*}
		tsh_val=${tsh_line#*=}
		if tsh_is_config_key "$tsh_key"; then
			eval "$tsh_key=\$tsh_val"
		fi
	done < "$TSH_CONFIG"

	ADD_SHORT=$(tsh_normalize_bool "$ADD_SHORT")
	ADD_IPV6=$(tsh_normalize_bool "$ADD_IPV6")
	ADD_SELF=$(tsh_normalize_bool "$ADD_SELF")
	BOOT_APPLY=$(tsh_normalize_bool "$BOOT_APPLY")
}

tsh_save_config() {
	local tsh_tmp tsh_key tsh_val

	tsh_init
	tsh_tmp="$TSH_CONFIG.tmp.$$"
	{
		for tsh_key in $TSH_CONFIG_KEYS; do
			# Indirect read: the key is also the variable name.
			eval "tsh_val=\$$tsh_key"
			printf '%s=%s\n' "$tsh_key" "$tsh_val"
		done
	} > "$tsh_tmp" || {
		rm -f "$tsh_tmp"
		return 1
	}

	mv -f "$tsh_tmp" "$TSH_CONFIG"
	chmod 600 "$TSH_CONFIG" 2>/dev/null
}

tsh_set() {
	local tsh_key tsh_val

	tsh_key=${1:-}
	[ -n "$tsh_key" ] && [ $# -ge 2 ] || {
		tsh_error "missing value"
		return 2
	}
	if ! tsh_is_config_key "$tsh_key"; then
		tsh_error "unknown config key: $tsh_key"
		return 2
	fi

	tsh_val=$2
	if tsh_is_bool_key "$tsh_key"; then
		tsh_val=$(tsh_normalize_bool "$tsh_val")
		case "$tsh_val" in
			0|1) ;;
			*)
				tsh_error "invalid boolean for $tsh_key: $2 (use 0 or 1)"
				return 2
				;;
		esac
	fi
	eval "$tsh_key=\$tsh_val"

	tsh_save_config || {
		tsh_error "failed to save config"
		return 1
	}
}

# ---------------------------------------------------------------------------
# log / state
# ---------------------------------------------------------------------------
# Print an error for the user.  Unlike tsh_set_error this is not logged and
# does not touch TSH_LAST_ERROR.
tsh_error() {
	printf 'error: %s\n' "$*" >&2
}

# Flatten a command's stderr file into one short line for an error message.
tsh_read_message() {
	tr '\n' ' ' < "$1" 2>/dev/null | head -c 200
}

tsh_log() {
	local tsh_size

	tsh_init
	printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$TSH_LOG" 2>/dev/null

	tsh_size=$(wc -c < "$TSH_LOG" 2>/dev/null || echo 0)
	if [ "$tsh_size" -gt 262144 ]; then
		tail -n 400 "$TSH_LOG" > "$TSH_LOG.tmp" 2>/dev/null &&
			mv -f "$TSH_LOG.tmp" "$TSH_LOG" 2>/dev/null
	fi
}

tsh_set_error() {
	TSH_LAST_ERROR=$*
	tsh_log "ERROR: $*"
}

tsh_write_state() {
	tsh_init
	{
		printf 'last_run=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
		printf 'last_ok=%s\n' "$1"
		printf 'last_count=%s\n' "$2"
		printf 'last_error=%s\n' "$3"
	} > "$TSH_STATE.tmp.$$" && mv -f "$TSH_STATE.tmp.$$" "$TSH_STATE"
}

tsh_load_state() {
	local tsh_line tsh_key tsh_val

	STATE_LAST_RUN=""
	STATE_LAST_OK=""
	STATE_LAST_COUNT=""
	STATE_LAST_ERROR=""
	[ -f "$TSH_STATE" ] || return 0

	while IFS= read -r tsh_line; do
		case "$tsh_line" in
			''|'#'*) continue ;;
		esac
		tsh_key=${tsh_line%%=*}
		tsh_val=${tsh_line#*=}
		case "$tsh_key" in
			last_run) STATE_LAST_RUN=$tsh_val ;;
			last_ok) STATE_LAST_OK=$tsh_val ;;
			last_count) STATE_LAST_COUNT=$tsh_val ;;
			last_error) STATE_LAST_ERROR=$tsh_val ;;
		esac
	done < "$TSH_STATE"
}

# Remove generated caches while keeping config and log.
tsh_clean_generated() {
	rm -f "$TSH_ENTRIES" "$TSH_APPLIED" "$TSH_STATE" \
		"$TSH_DIR/status.json" "$TSH_DIR/peers.tsv" \
		"$TSH_DIR/entries.raw" "$TSH_DIR/parse.err" \
		"$TSH_DIR/build.err" "$TSH_DIR/tailscale.err" \
		"$TSH_DIR/candidates.tsv"
}
