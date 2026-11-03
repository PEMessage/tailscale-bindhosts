# shellcheck shell=sh
# shellcheck disable=SC3043  # local is supported by Android mksh / busybox ash
# Detection layer: discover (bin, socket, repo) pairs.
#
# Sourced by lib/common.sh.  Returns TSV records:
#   bin<TAB>socket<TAB>repo<TAB>source
# An empty socket means "use the CLI default" (or a wrapper-managed socket).

# Resolve symlinks.  Prefer one `readlink -f`; the fallback uses shell
# parameter expansion instead of forking dirname for every hop.
tsh_realpath() {
	local tsh_rp tsh_n tsh_l tsh_dir

	tsh_rp=$(readlink -f "$1" 2>/dev/null)
	if [ -n "$tsh_rp" ]; then
		printf '%s\n' "$tsh_rp"
		return 0
	fi

	tsh_rp=$1
	tsh_n=0
	while [ -L "$tsh_rp" ] && [ "$tsh_n" -lt 20 ]; do
		tsh_l=$(readlink "$tsh_rp" 2>/dev/null) || break
		case "$tsh_l" in
			/*) tsh_rp=$tsh_l ;;
			*)
				case "$tsh_rp" in
					*/*) tsh_dir=${tsh_rp%/*} ;;
					*) tsh_dir=. ;;
				esac
				tsh_rp=$tsh_dir/$tsh_l
				;;
		esac
		tsh_n=$((tsh_n + 1))
	done
	printf '%s\n' "$tsh_rp"
}

# Dedup key.  Normal symlinks resolve to their target; if the target changes
# the basename (a multicall tailscale/tailscaled binary), keep the original
# name so the CLI is still called "tailscale".
tsh_bin_key() {
	local tsh_bk_real tsh_bk_name tsh_bk_dir

	if [ -L "$1" ]; then
		tsh_bk_real=$(tsh_realpath "$1")
	else
		tsh_bk_real=$1
	fi

	tsh_bk_name=${1##*/}
	if [ "${tsh_bk_real##*/}" = "$tsh_bk_name" ]; then
		printf '%s\n' "$tsh_bk_real"
	else
		tsh_bk_dir=${tsh_bk_real%/*}
		[ -n "$tsh_bk_dir" ] || tsh_bk_dir=.
		printf '%s/%s\n' "$tsh_bk_dir" "$tsh_bk_name"
	fi
}

# Internal record: key<TAB>bin<TAB>socket<TAB>repo<TAB>source.
tsh_emit_pair() {
	[ -x "$1" ] || return 0
	printf '%s\t%s\t%s\t%s\t%s\n' \
		"$(tsh_bin_key "$1")" "$1" "$2" "$3" "$4"
}

tsh_socket_for_repo() {
	case "$1" in
		WayneShao/KernelSU-Tailscaled)
			echo "$TSH_KSU_TS_DIR/run/tailscaled.sock"
			;;
		Iridule/Tailscale-native-magisk)
			echo "$TSH_ADB/tailscale-native/tailscaled.sock"
			;;
		*)
			echo ""
			;;
	esac
}

# Best-effort repository name for a binary path.
tsh_repo_for_bin() {
	local tsh_rf_orig tsh_rf_real tsh_rf_p

	tsh_rf_orig=$1
	tsh_rf_real=$(tsh_realpath "$1")
	for tsh_rf_p in "$tsh_rf_orig" "$tsh_rf_real"; do
		case "$tsh_rf_p" in
			*/modules/shellscaled/*)
				echo "KyuubiRan/Shellscaled"
				return 0
				;;
			*/kernelsu-tailscaled/*)
				echo "WayneShao/KernelSU-Tailscaled"
				return 0
				;;
			*/modules/native_tailscale/*|*/tailscale-native/*)
				echo "Iridule/Tailscale-native-magisk"
				return 0
				;;
			# anasfanani, mgksu and the Alt-Repo fork share this layout.
			# Report the original project (highest star count) instead of
			# trying to tell the forks apart.
			*/modules/magisk-tailscaled/*|*/modules/tailscaled/*|"$TSH_TAILSCALE_DIR"/*)
				echo "anasfanani/Magisk-Tailscaled"
				return 0
				;;
		esac
	done

	echo "unknown"
}

# Read the socket declared by the Magisk-Tailscaled family, if any.
# Some forks (notably anasfanani) use the default socket and have none.
tsh_socket_from_settings() {
	local tsh_sf tsh_sock tsh_sdir

	for tsh_sf in "$TSH_TAILSCALE_DIR/settings.ini" \
		"$TSH_TAILSCALE_DIR/settings.sh"; do
		[ -f "$tsh_sf" ] || continue

		tsh_sock=$(sed -n '/^[[:space:]]*#/d; s/.*--socket=\([^ "]*\).*/\1/p' \
			"$tsh_sf" | head -n 1)
		[ -n "$tsh_sock" ] || continue

		# settings.ini uses ${tailscale_dir}; expand the common forms.
		tsh_sdir=$(sed -n 's/^[[:space:]]*tailscale_dir="\([^"]*\)".*/\1/p' \
			"$tsh_sf" | head -n 1)
		[ -n "$tsh_sdir" ] || tsh_sdir=$(sed -n \
			's/^[[:space:]]*TS_DIR="\([^"]*\)".*/\1/p' "$tsh_sf" | head -n 1)
		if [ -n "$tsh_sdir" ]; then
			tsh_sock=$(printf '%s\n' "$tsh_sock" | tsh_awk -v d="$tsh_sdir" '
				{
					gsub(/\$\{tailscale_dir\}/, d)
					gsub(/\$tailscale_dir/, d)
					gsub(/\$\{TS_DIR\}/, d)
					print
				}
			')
		fi

		printf '%s\n' "$tsh_sock"
		return 0
	done
	return 0
}

# Resolve one candidate PID into a bin/socket/repo record.
tsh_candidate_pid() {
	local tsh_cp_pid tsh_cp_argv0 tsh_exe tsh_bin tsh_cmd tsh_sock tsh_repo

	tsh_cp_pid=$1
	tsh_cp_argv0=$2

	tsh_exe=$(readlink "/proc/$tsh_cp_pid/exe" 2>/dev/null)
	tsh_exe=${tsh_exe% (deleted)}

	# Prefer the sibling of the real executable; fall back to argv[0].
	tsh_bin=""
	[ -n "$tsh_exe" ] && tsh_bin=${tsh_exe%/*}/tailscale
	if [ ! -x "$tsh_bin" ]; then
		case "$tsh_cp_argv0" in
			*/*) tsh_bin=${tsh_cp_argv0%/*}/tailscale ;;
		esac
	fi
	[ -x "$tsh_bin" ] || return 0

	tsh_cmd=$(tr '\0' '\n' < "/proc/$tsh_cp_pid/cmdline" 2>/dev/null) 2>/dev/null
	[ -n "$tsh_cmd" ] || return 0

	tsh_sock=$(printf '%s\n' "$tsh_cmd" |
		sed -n 's/^--*socket=//p' | head -n 1)
	if [ -z "$tsh_sock" ]; then
		tsh_sock=$(printf '%s\n' "$tsh_cmd" |
			sed -n '/^--*socket$/{n;p;}' | head -n 1)
	fi

	tsh_repo=$(tsh_repo_for_bin "$tsh_bin")
	# Shellscaled's CLI wrapper injects --socket and rejects overrides.
	[ "$tsh_repo" = "KyuubiRan/Shellscaled" ] && tsh_sock=""

	tsh_emit_pair "$tsh_bin" "$tsh_sock" "$tsh_repo" \
		"running daemon (pid $tsh_cp_pid)"
}

# Pairs discovered from a live tailscaled process.  Its own --socket is
# authoritative; no socket means "use the CLI default".
#
# `ps -A -o PID,ARGS` is one process.  Scanning /proc with `tr` and `readlink`
# per PID took ~25s on a device with 1000 processes.  The /proc/*/comm
# fallback only reads files with shell builtins.
tsh_candidates_running() {
	local tsh_ps_file tsh_pid tsh_args tsh_argv0 tsh_p tsh_comm

	tsh_init
	tsh_ps_file="$TSH_DIR/.ps.$$"

	if ps -A -o PID,ARGS > "$tsh_ps_file" 2>/dev/null && [ -s "$tsh_ps_file" ]; then
		while read -r tsh_pid tsh_args; do
			tsh_argv0=${tsh_args%% *}
			case "${tsh_argv0##*/}" in
				tailscaled|.tailscaled*)
					tsh_candidate_pid "$tsh_pid" "$tsh_argv0"
					;;
			esac
		done < "$tsh_ps_file"
	else
		for tsh_p in /proc/[0-9]*; do
			tsh_comm=""
			IFS= read -r tsh_comm < "$tsh_p/comm" 2>/dev/null || continue
			case "$tsh_comm" in
				tailscaled|.tailscaled*)
					tsh_candidate_pid "${tsh_p##*/}" ""
					;;
			esac
		done
	fi

	rm -f "$tsh_ps_file"
}

# Static table: repo|bin|sockets|source
#   sockets: semicolon-separated, first existing path wins
#   @settings: use the socket declared by the Magisk-Tailscaled settings file
#   empty: use the CLI default / a wrapper-managed socket
tsh_static_table() {
	cat <<EOF
anasfanani/Magisk-Tailscaled|$TSH_TAILSCALE_DIR/bin/tailscale|@settings|settings/default
anasfanani/Magisk-Tailscaled|$TSH_ADB/modules/magisk-tailscaled/system/bin/tailscale|@settings|module dir
anasfanani/Magisk-Tailscaled|$TSH_ADB/modules/tailscaled/system/bin/tailscale|@settings|module dir
KyuubiRan/Shellscaled|$TSH_ADB/modules/shellscaled/bin/tailscale||wrapper manages socket
WayneShao/KernelSU-Tailscaled|$TSH_KSU_TS_DIR/engine-current/bin/tailscale|$TSH_KSU_TS_DIR/run/tailscaled.sock|engine-current
WayneShao/KernelSU-Tailscaled|$TSH_ADB/modules/kernelsu-tailscaled/bin/tailscale|$TSH_KSU_TS_DIR/run/tailscaled.sock|module bin
Iridule/Tailscale-native-magisk|$TSH_ADB/modules/native_tailscale/bin/tailscale|$TSH_ADB/tailscale-native/tailscaled.sock|native module
Termux|/data/data/com.termux/files/usr/bin/tailscale|/data/data/com.termux/files/usr/var/run/tailscale/tailscaled.sock;/var/run/tailscale/tailscaled.sock|PATH
system|/system/bin/tailscale|/var/run/tailscale/tailscaled.sock|PATH
system|/system/xbin/tailscale|/var/run/tailscale/tailscaled.sock|PATH
EOF
}

# Known project layouts.
tsh_candidates_static() {
	local tsh_declared tsh_repo tsh_bin tsh_socks tsh_src
	local tsh_sock tsh_s tsh_old_ifs tsh_path_bin tsh_path_repo tsh_path_sock

	tsh_declared=$(tsh_socket_from_settings)

	tsh_static_table | while IFS='|' read -r tsh_repo tsh_bin tsh_socks tsh_src; do
		[ -n "$tsh_bin" ] || continue

		if [ "$tsh_socks" = "@settings" ]; then
			if [ -n "$tsh_declared" ]; then
				tsh_emit_pair "$tsh_bin" "$tsh_declared" "$tsh_repo" "$tsh_src"
			else
				tsh_emit_pair "$tsh_bin" "" "$tsh_repo" "default socket"
			fi
			continue
		fi

		tsh_sock=""
		tsh_old_ifs=$IFS
		IFS=';'
		for tsh_s in $tsh_socks; do
			if [ -n "$tsh_s" ] && [ -e "$tsh_s" ]; then
				tsh_sock=$tsh_s
				break
			fi
		done
		IFS=$tsh_old_ifs

		tsh_emit_pair "$tsh_bin" "$tsh_sock" "$tsh_repo" "$tsh_src"
	done

	# Anything else already on PATH.
	tsh_path_bin=$(command -v tailscale 2>/dev/null)
	case "$tsh_path_bin" in
		/*)
			tsh_path_repo=$(tsh_repo_for_bin "$tsh_path_bin")
			[ "$tsh_path_repo" = "unknown" ] && tsh_path_repo="PATH"
			tsh_path_sock=$(tsh_socket_for_repo "$tsh_path_repo")
			tsh_emit_pair "$tsh_path_bin" "$tsh_path_sock" \
				"$tsh_path_repo" "PATH"
			;;
	esac
}

# Print unique bin<TAB>socket<TAB>repo<TAB>source records.  The live daemon
# wins over static guesses because it is emitted first and dedup is by binary.
tsh_detect_candidates() {
	{
		tsh_candidates_running
		tsh_candidates_static
	} | tsh_awk -F '\t' '
		!seen[$1]++ { print $2 "\t" $3 "\t" $4 "\t" $5 }
	'
}

# Refresh $TSH_CANDIDATES from the current system.  The cache is replaced
# atomically; TSH_LAST_ERROR is set when detection fails.
tsh_refresh_candidates() {
	local tsh_tmp

	tsh_init
	tsh_tmp="$TSH_CANDIDATES.tmp.$$"
	if ! tsh_detect_candidates > "$tsh_tmp"; then
		rm -f "$tsh_tmp"
		tsh_set_error "failed to detect tailscale"
		return 1
	fi
	mv -f "$tsh_tmp" "$TSH_CANDIDATES"
}

# Point TS_BIN / TS_SOCKET at the n-th cached candidate.
tsh_select_candidate() {
	local tsh_line

	tsh_line=$(tsh_awk -F '\t' -v n="$1" 'NR == n { print; exit }' \
		"$TSH_CANDIDATES")
	[ -n "$tsh_line" ] || return 1

	TS_BIN=$(printf '%s\n' "$tsh_line" | tsh_awk -F '\t' '{ print $1 }')
	TS_SOCKET=$(printf '%s\n' "$tsh_line" | tsh_awk -F '\t' '{ print $2 }')
	return 0
}
