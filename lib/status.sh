# shellcheck shell=sh
# shellcheck disable=SC3043  # local is supported by Android mksh / busybox ash
# Status layer: entry statistics, module.prop description, status output.
#
# Sourced by lib/common.sh after core/detect/tailscale/bindhosts.

# One awk pass over the generated entries.
# Sets TSH_STATS_ENTRIES / _NODES / _V4 / _V6.
tsh_stats() {
	local tsh_stats_line

	TSH_STATS_ENTRIES=0
	TSH_STATS_NODES=0
	TSH_STATS_V4=0
	TSH_STATS_V6=0
	[ -s "$TSH_ENTRIES" ] || return 0

	tsh_stats_line=$(tsh_awk '
		NF < 2 { next }
		{
			entries++
			nodes[$2] = 1
			if ($1 ~ /:/)
				v6++
			else
				v4++
		}
		END { printf "%d %d %d %d\n", entries, length(nodes), v4, v6 }
	' "$TSH_ENTRIES")

	read -r TSH_STATS_ENTRIES TSH_STATS_NODES TSH_STATS_V4 TSH_STATS_V6 <<EOF
$tsh_stats_line
EOF
}

# Human-readable summary written to module.prop (manager status line).
tsh_describe() {
	local tsh_err

	tsh_load_state
	tsh_stats

	if [ "$STATE_LAST_OK" = "1" ]; then
		printf 'status: active ✅ | %s nodes, %s entries | %s' \
			"$TSH_STATS_NODES" "$STATE_LAST_COUNT" "$STATE_LAST_RUN"
	elif [ -n "$STATE_LAST_RUN" ]; then
		tsh_err=$(printf '%s' "$STATE_LAST_ERROR" | head -c 70)
		printf 'status: error ❌ | %s' "$tsh_err"
	else
		printf 'status: idle 💤 | run: tailscale-bindhosts apply'
	fi
}

# Rewrite only the description= line of the active module.prop so managers
# (Magisk / KernelSU / APatch) can show a status.  Refuse to touch the source
# tree or a fake test module: only real module directories are updated.
tsh_update_description() {
	local tsh_ud_text tsh_ud_prop tsh_ud_tmp

	tsh_ud_text=$1
	tsh_ud_prop="$MODDIR/module.prop"
	[ -f "$tsh_ud_prop" ] || return 0

	case "$MODDIR" in
		"$TSH_ADB"/modules/*|"$TSH_ADB"/modules_update/*) ;;
		*) return 0 ;;
	esac

	tsh_ud_tmp="$tsh_ud_prop.tmp.$$"
	tsh_awk -v d="$tsh_ud_text" '
		BEGIN { FS = OFS = "="; found = 0 }
		$1 == "description" { print "description", d; found = 1; next }
		{ print }
		END { if (!found) print "description", d }
	' "$tsh_ud_prop" > "$tsh_ud_tmp" || {
		rm -f "$tsh_ud_tmp"
		return 1
	}

	mv -f "$tsh_ud_tmp" "$tsh_ud_prop"
	chmod 644 "$tsh_ud_prop" 2>/dev/null
	chown 0:0 "$tsh_ud_prop" 2>/dev/null
	return 0
}

tsh_status() {
	local tsh_bin_ok tsh_bh tsh_bh_enabled tsh_target tsh_target_ok
	local tsh_mode

	tsh_load_config
	tsh_load_state
	tsh_init
	tsh_stats

	tsh_bin_ok=0
	[ -n "$TS_BIN" ] && [ -x "$TS_BIN" ] && tsh_bin_ok=1

	tsh_bh=0
	tsh_bh_installed && tsh_bh=1

	tsh_bh_enabled=0
	tsh_bh_available && tsh_bh_enabled=1

	tsh_target=""
	tsh_target_ok=0
	if [ "$tsh_bh_enabled" = 1 ]; then
		tsh_target=$(tsh_bh_target)
		[ -f "$tsh_target" ] && [ -w "$tsh_target" ] && tsh_target_ok=1
	fi

	tsh_mode=$(tsh_bh_mode)

	cat <<EOF
bin=$TS_BIN
bin_ok=$tsh_bin_ok
socket=$TS_SOCKET
args=$TS_ARGS
add_short=$ADD_SHORT
add_ipv6=$ADD_IPV6
add_self=$ADD_SELF
boot_apply=$BOOT_APPLY
bindhosts=$tsh_bh
bindhosts_enabled=$tsh_bh_enabled
bindhosts_mode=$tsh_mode
target=$tsh_target
target_ok=$tsh_target_ok
entries=$TSH_STATS_ENTRIES
last_run=$STATE_LAST_RUN
last_ok=$STATE_LAST_OK
last_count=$STATE_LAST_COUNT
last_error=$STATE_LAST_ERROR
EOF
}
