#!/usr/bin/env bash
# Package the Magisk / KernelSU / APatch module into a flashable zip.
#
# Usage:
#   ./build.sh [--out DIR]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${OUT:-$HERE/dist}"

# Files shipped in the zip. Everything else (README, build.sh, ...) stays out.
MODULE_FILES=(
    module.prop
    customize.sh
    service.sh
    action.sh
    uninstall.sh
    tailscale-bindhosts.sh
    lib
    META-INF
)

# -- helpers ---------------------------------------------------------------

need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }
die()  { echo "error: $*" >&2; exit 1; }

runcmd() {
    echo "Running: $*"
    "$@"
}

title() {
    echo "=========================="
    echo "${FUNCNAME[1]}"
    echo "=========================="
}

usage() {
    cat <<'EOF'
Usage: ./build.sh [--out DIR]

  --out DIR   output directory for the zip (default: ./dist, or $OUT)
  -h, --help  show this help
EOF
}

# -- steps -----------------------------------------------------------------

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --out)
                [ "$#" -ge 2 ] || die "--out needs a directory"
                OUT=$2
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "unknown argument: $1"
                ;;
        esac
    done
}

resolve() {
    [ -f "$HERE/module.prop" ] || die "run me from the module repository"
    VERSION=$(sed -n 's/^version=//p' "$HERE/module.prop")
    [ -n "$VERSION" ] || die "cannot read version from module.prop"

    # package() runs inside $STAGE, so a relative --out would otherwise be
    # resolved relative to the build directory.
    case "$OUT" in
        /*) ;;
        *) OUT="$PWD/$OUT" ;;
    esac

    ZIP="$OUT/tailscale-bindhosts-$VERSION.zip"
    STAGE="$HERE/build"
}

check_env() {
    title
    need zip
    need sed
}

stage() {
    title
    [ -d "$STAGE" ] && runcmd rm -rf "$STAGE"
    runcmd mkdir -p "$STAGE" "$OUT"
    for item in "${MODULE_FILES[@]}"; do
        runcmd cp -a "$HERE/$item" "$STAGE/"
    done
    # Recovery / manager installers invoke this directly on some devices.
    runcmd chmod 755 "$STAGE/META-INF/com/google/android/update-binary"
}

package() {
    title
    [ -e "$ZIP" ] && runcmd rm -f "$ZIP"
    runcmd zip -qr9 "$ZIP" .
}

handoff() {
    title
    echo "Built: $ZIP"
    echo "Flash it, reboot, then configure it from a root shell:"
    echo "  tailscale-bindhosts detect"
    echo "  tailscale-bindhosts use 1"
    echo "  tailscale-bindhosts apply"
}

# -- main ------------------------------------------------------------------

main() {
    parse_args "$@"
    resolve
    check_env
    stage
    ( cd "$STAGE" && package )
    handoff
}

main "$@"
