#!/system/bin/sh
# Uninstall hook.
# Keep it simple: undo the applied entries, then remove our persistent state.

MODDIR=${0%/*}
[ -f "$MODDIR/tailscale-bindhosts.sh" ] || MODDIR=/data/adb/modules/tailscale-bindhosts
TSH_ADB=${TSH_ADB:-/data/adb}
BH_MODDIR=${BH_MODDIR:-$TSH_ADB/modules/bindhosts}
BH_PERSIST=${BH_PERSIST:-$TSH_ADB/bindhosts}
TSH_DIR=${TSH_DIR:-$TSH_ADB/tailscale-bindhosts}
export TSH_ADB BH_MODDIR BH_PERSIST TSH_DIR

if [ -f "$MODDIR/tailscale-bindhosts.sh" ]; then
	sh "$MODDIR/tailscale-bindhosts.sh" unapply >/dev/null 2>&1
fi

# Also cover the case where the CLI could not run.
rm -f "$BH_PERSIST/custom-tailscale-bindhosts.txt"
rm -rf "$TSH_DIR"
rm -f /data/adb/ksu/bin/tailscale-bindhosts /data/adb/ap/bin/tailscale-bindhosts \
	/debug_ramdisk/tailscale-bindhosts /sbin/tailscale-bindhosts
exit 0
