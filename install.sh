#!/bin/bash
# Copyright J.C. Vaught. See LICENSE.
# Local installation only. Never downloads dependencies or creates credentials.
set -o pipefail
PREFIX="$HOME/.local"
FORCE=0
DRY_RUN=0
usage() { printf 'Usage: ./install.sh [--prefix DIR] [--force] [--dry-run]\nInstalls below HOME. --force replaces regular files; symlinks are always refused.\n'; }
error() { printf 'install: %s\n' "$*" >&2; }
while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix) shift; [ "$#" -gt 0 ] || { usage >&2; exit 2; }; PREFIX=$1 ;;
        --force) FORCE=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done
[ "$(id -u)" -ne 0 ] || { error 'run as your normal account, without elevated privileges'; exit 1; }
case "$HOME" in /*) ;; *) error 'HOME must be absolute'; exit 1 ;; esac
case "$PREFIX" in "$HOME"/*) ;; *) error 'prefix must be below HOME'; exit 1 ;; esac
case "$PREFIX" in *[!A-Za-z0-9_./-]*|*'//'*) error 'unsupported prefix characters'; exit 1 ;; esac
case "/$PREFIX/" in */../*|*/./*) error 'dot path components are forbidden'; exit 1 ;; esac
PREFIX=${PREFIX%/}
SOURCE_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
SYSTEM=$(uname -s)
case "$SYSTEM" in Darwin|Linux) ;; *) error 'only macOS and Linux are supported'; exit 1 ;; esac
metadata() { if [ "$SYSTEM" = Darwin ]; then stat -f '%u %Lp' "$1"; else stat -c '%u %a' -- "$1"; fi; }
check_path() {
    local path=$1 cursor=$HOME remainder component data owner mode
    remainder=${path#"$HOME"/}
    while :; do
        [ ! -L "$cursor" ] || { error "refusing symlink: $cursor"; return 1; }
        if [ -e "$cursor" ]; then
            [ -d "$cursor" ] || { error "not a directory: $cursor"; return 1; }
            data=$(metadata "$cursor" 2>/dev/null) || return 1
            read -r owner mode <<< "$data"
            [ "$owner" = "$(id -u)" ] && [ "$((8#$mode & 8#022))" -eq 0 ] || { error "unsafe directory ownership/permissions: $cursor"; return 1; }
        fi
        [ -n "$remainder" ] || break
        component=${remainder%%/*}
        if [ "$remainder" = "$component" ]; then remainder=; else remainder=${remainder#*/}; fi
        cursor="$cursor/$component"
    done
}
check_target() {
    local path=$1 data owner mode
    [ ! -L "$path" ] || { error "refusing symlink: $path"; return 1; }
    if [ -e "$path" ]; then
        [ -f "$path" ] || { error "not a regular file: $path"; return 1; }
        data=$(metadata "$path" 2>/dev/null) || return 1
        read -r owner mode <<< "$data"
        [ "$owner" = "$(id -u)" ] && [ "$((8#$mode & 8#022))" -eq 0 ] || { error "unsafe target ownership/permissions: $path"; return 1; }
        [ "$FORCE" -eq 1 ] || { error "already exists: $path (inspect it, then use --force to replace)"; return 1; }
    fi
}
# Validate every destination before changing any files.
check_path "$PREFIX/bin" && check_path "$PREFIX/share/mownt" || exit 1
check_target "$PREFIX/bin/mownt" && check_target "$PREFIX/share/mownt/mounts.example.tsv" || exit 1
[ -f "$SOURCE_DIR/bin/mownt" ] && [ ! -L "$SOURCE_DIR/bin/mownt" ] && [ -f "$SOURCE_DIR/config/mounts.example.tsv" ] && [ ! -L "$SOURCE_DIR/config/mounts.example.tsv" ] || { error 'release source files are missing or symlinked'; exit 1; }
if [ "$DRY_RUN" -eq 1 ]; then
    printf 'Would install %s to %s\n' "$SOURCE_DIR/bin/mownt" "$PREFIX/bin/mownt"
    printf 'Would install example configuration to %s\n' "$PREFIX/share/mownt/mounts.example.tsv"
    exit 0
fi
umask 077
mkdir -p "$PREFIX/bin" "$PREFIX/share/mownt" || exit 1
# Temporary files are in the destination directories, then atomically renamed.
TMP_BIN=$(mktemp "$PREFIX/bin/.mownt.XXXXXXXX") || exit 1
TMP_CONFIG=$(mktemp "$PREFIX/share/mownt/.mounts.XXXXXXXX") || { rm -f "$TMP_BIN"; exit 1; }
trap 'rm -f "$TMP_BIN" "$TMP_CONFIG"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cat "$SOURCE_DIR/bin/mownt" > "$TMP_BIN" && chmod 755 "$TMP_BIN" && cat "$SOURCE_DIR/config/mounts.example.tsv" > "$TMP_CONFIG" && chmod 600 "$TMP_CONFIG" || exit 1
mv -f "$TMP_BIN" "$PREFIX/bin/mownt" && mv -f "$TMP_CONFIG" "$PREFIX/share/mownt/mounts.example.tsv" || exit 1
printf 'Installed %s\n' "$PREFIX/bin/mownt"
printf 'Example %s\nCreate a private config following docs/setup.md before running mownt.\n' "$PREFIX/share/mownt/mounts.example.tsv"
