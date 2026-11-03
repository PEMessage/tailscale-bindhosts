#!/system/bin/sh
# Boot service hook.
# All runtime logic lives in tailscale-bindhosts.sh; this file only dispatches.
#
# `exec` is intentional: it keeps the process tree the same as before, so the
# optional background wait-for-tailscaled job survives the hook exiting.

MODDIR=${0%/*}
[ -f "$MODDIR/tailscale-bindhosts.sh" ] || MODDIR=/data/adb/modules/tailscale-bindhosts

# Refresh the terminal shortcut at boot.  At this point MODDIR is the final
# module path, so this survives module updates and also covers Magisk's tmpfs
# dirs (/debug_ramdisk, /sbin) that do not persist across reboots.
for tsh_bin_dir in /debug_ramdisk /sbin /data/adb/ksu/bin /data/adb/ap/bin; do
	if [ -d "$tsh_bin_dir" ] && [ -w "$tsh_bin_dir" ]; then
		ln -sf "$MODDIR/tailscale-bindhosts.sh" "$tsh_bin_dir/tailscale-bindhosts" 2>/dev/null
	fi
done

exec sh "$MODDIR/tailscale-bindhosts.sh" boot
