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
            if [ "$owner" != "$(id -u)" ] || [ "$((8#$mode & 8#022))" -ne 0 ]; then
                error "unsafe directory ownership/permissions: $cursor"; return 1
            fi
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
        if [ "$owner" != "$(id -u)" ] || [ "$((8#$mode & 8#022))" -ne 0 ]; then
            error "unsafe target ownership/permissions: $path"; return 1
        fi
        [ "$FORCE" -eq 1 ] || { error "already exists: $path (inspect it, then use --force to replace)"; return 1; }
    fi
}
# Validate every destination and package source before changing any files.
sources=("$SOURCE_DIR/bin/mownt" "$SOURCE_DIR/config/mounts.example.tsv" "$SOURCE_DIR/config/automation.example.conf" "$SOURCE_DIR/libexec/mownt-relay")
targets=("$PREFIX/bin/mownt" "$PREFIX/share/mownt/mounts.example.tsv" "$PREFIX/share/mownt/automation.example.conf" "$PREFIX/share/mownt/libexec/mownt-relay")
modes=(755 600 600 700)
for directory in "$PREFIX/bin" "$PREFIX/share/mownt" "$PREFIX/share/mownt/libexec"; do
    check_path "$directory" || exit 1
done
for target in "${targets[@]}"; do check_target "$target" || exit 1; done
for source in "${sources[@]}"; do
    if [ ! -f "$source" ] || [ -L "$source" ]; then
        error 'release source files are missing or symlinked'; exit 1
    fi
done
if [ "$DRY_RUN" -eq 1 ]; then
    index=0
    while [ "$index" -lt "${#sources[@]}" ]; do
        printf 'Would install %s to %s\n' "${sources[$index]}" "${targets[$index]}"
        index=$((index + 1))
    done
    exit 0
fi
umask 077
mkdir -p "$PREFIX/bin" "$PREFIX/share/mownt/libexec" || exit 1
# Stage every file on its destination filesystem before publishing the command.
temporaries=()
cleanup() { for temporary in "${temporaries[@]}"; do rm -f "$temporary"; done; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
index=0
while [ "$index" -lt "${#sources[@]}" ]; do
    target=${targets[$index]}
    temporary=$(mktemp "${target%/*}/.mownt-install.XXXXXXXX") || exit 1
    temporaries+=("$temporary")
    cat "${sources[$index]}" > "$temporary" && chmod "${modes[$index]}" "$temporary" || exit 1
    index=$((index + 1))
done
# The installed command becomes visible only after its helper and templates.
for index in 1 2 3 0; do mv -f "${temporaries[$index]}" "${targets[$index]}" || exit 1; done
printf 'Installed %s\n' "$PREFIX/bin/mownt"
printf 'Examples %s\nCreate private configuration following docs/setup.md before running mownt.\n' "$PREFIX/share/mownt"
