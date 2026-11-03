#!/system/bin/sh
# Installer hook.
# Check the dependency, seed the default config, and set permissions.
# Detection is lazy: `tailscale-bindhosts apply` (or the Action button) auto-detects
# the first (bin, socket) pair when TS_BIN is empty.

MODDIR=${MODPATH:-${0%/*}}
TSH_ADB=${TSH_ADB:-/data/adb}
BH_MODDIR=${BH_MODDIR:-$TSH_ADB/modules/bindhosts}
TSH_DIR=${TSH_DIR:-$TSH_ADB/tailscale-bindhosts}

if ! command -v ui_print >/dev/null 2>&1; then
	ui_print() { echo "$1"; }
fi

if [ ! -f "$BH_MODDIR/bindhosts.sh" ]; then
	ui_print "[x] bindhosts is required but not installed."
	ui_print "[x] Install bindhosts first, then flash this module again."
	[ -n "${MODPATH:-}" ] && rm -rf "$MODPATH"
	exit 1
fi

mkdir -p "$TSH_DIR"
[ -f "$TSH_DIR/config" ] ||
	cp -f "$MODDIR/lib/config.example" "$TSH_DIR/config"
chmod 600 "$TSH_DIR/config" 2>/dev/null

chmod 755 "$MODDIR/tailscale-bindhosts.sh" "$MODDIR/service.sh" \
	"$MODDIR/action.sh" "$MODDIR/uninstall.sh" 2>/dev/null

ui_print "[+] tailscale-bindhosts installed"
ui_print "[*] after reboot, run (or tap Action):"
ui_print "      tailscale-bindhosts apply"
ui_print "[*] apply auto-detects tailscale when TS_BIN is empty."

# Success: fall through on purpose.  Magisk sources this file and still has
# finalization work to do after it returns.
