#!/system/bin/sh
# Manager action button hook.
# The button is just a manual `apply`.

MODDIR=${0%/*}
[ -f "$MODDIR/tailscale-bindhosts.sh" ] || MODDIR=/data/adb/modules/tailscale-bindhosts

exec sh "$MODDIR/tailscale-bindhosts.sh" apply
