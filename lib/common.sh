#!/system/bin/sh
# tailscale-bindhosts shared library.
#
# Sourced only by tailscale-bindhosts.sh.  The implementation is split by
# layer so each file has one job:
#
#   core.sh        paths, config, state, logging
#   detect.sh      candidate discovery (bin/socket/repo pairs)
#   tailscale.sh   CLI invocation, status -> hosts entries
#   bindhosts.sh   target selection, hosts file surgery
#   status.sh      statistics, module.prop status line, tsh_status
#   actions.sh     auto-config, apply, unapply
#
# All paths can be overridden through the environment, which makes the module
# testable on a normal Linux box.  No file here touches the network on source.

. "$MODDIR/lib/core.sh"
. "$MODDIR/lib/detect.sh"
. "$MODDIR/lib/tailscale.sh"
. "$MODDIR/lib/bindhosts.sh"
. "$MODDIR/lib/status.sh"
. "$MODDIR/lib/actions.sh"
