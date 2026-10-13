#!/bin/bash
# Copyright J.C. Vaught. See LICENSE.
# Import the original literal configuration as data. Never execute the source.
set -euo pipefail
export LC_ALL=C
die() { printf 'import: %s\n' "$*" >&2; exit 1; }
if [ "$#" -ne 2 ]; then
    printf 'Usage: ./tools/import-legacy.sh OLD_SCRIPT OUTPUT_DIRECTORY\n' >&2
    exit 2
fi
SOURCE=$1
DEST=${2%/}
[ -f "$SOURCE" ] && [ -r "$SOURCE" ] || die 'old script must be a readable file'
[ "$(id -u)" -ne 0 ] || die 'run as your normal account'
case "$HOME" in /*) ;; *) die 'HOME must be absolute' ;; esac
case "$DEST" in "$HOME"/*) ;; *) die 'output directory must be below HOME' ;; esac
case "$DEST" in *[!A-Za-z0-9_./-]*|*'//'*) die 'unsupported output path' ;; esac
case "/$DEST/" in */../*|*/./*) die 'dot path components are forbidden' ;; esac
SYSTEM=$(uname -s)
metadata() {
    case "$SYSTEM" in
        Darwin) stat -f '%u %Lp' "$1" ;;
        Linux) stat -c '%u %a' -- "$1" ;;
        *) die 'only macOS and Linux are supported' ;;
    esac
}
cursor=$HOME
remainder=${DEST#"$HOME"/}
while :; do
    [ ! -L "$cursor" ] || die 'output path contains a symlink'
    if [ -e "$cursor" ]; then
        [ -d "$cursor" ] || die 'output ancestor is not a directory'
        read -r owner mode <<< "$(metadata "$cursor")"
        if [ "$owner" != "$(id -u)" ] || [ "$((8#$mode & 8#022))" -ne 0 ]; then
            die 'output ancestors must be user-owned and not writable by others'
        fi
    fi
    [ -n "$remainder" ] || break
    component=${remainder%%/*}
    if [ "$remainder" = "$component" ]; then remainder=; else remainder=${remainder#*/}; fi
    cursor="$cursor/$component"
done
umask 077
mkdir -p "$DEST"
read -r owner mode <<< "$(metadata "$DEST")"
[ "$mode" = 700 ] || die 'existing output directory must have mode 700'
for name in mounts.tsv automation.conf; do
    if [ -e "$DEST/$name" ] || [ -L "$DEST/$name" ]; then die 'output files already exist; choose a fresh directory'; fi
done
mkdir "$DEST/.import.lock" 2>/dev/null || die 'another import is active; inspect .import.lock if a prior import was interrupted'
TMP=
created_mounts=0
committed=0
cleanup() {
    if [ "$committed" -eq 0 ] && [ "$created_mounts" -eq 1 ]; then rm -f "$DEST/mounts.tsv"; fi
    [ -z "$TMP" ] || rm -rf "$TMP"
    rmdir "$DEST/.import.lock" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
TMP=$(mktemp -d "$DEST/.import.XXXXXXXX")
export MOWNT_IMPORT_SETTINGS="$TMP/automation.conf"
awk '
function invalid() { bad=1 }
function path_ok(p, parts,n,i) {
    if (p == "" || p == "/" || p ~ /[^A-Za-z0-9_.\/~\-]/ || p ~ /\/\// || p ~ /\/$/) return 0
    n=split(p,parts,"/")
    for(i=1;i<=n;i++) if(parts[i]=="." || parts[i]=="..") return 0
    return 1
}
function literal(line,key, value) {
    sub("^" key "=", "", line)
    if(line !~ /^"[^"]*"([ \t]*#.*)?[ \t]*$/) { invalid(); return "" }
    sub(/^"/, "", line); sub(/".*$/, "", line)
    return line
}
/^REMOTE_SHARE=/ {
    if (++shares != 1) invalid()
    share=literal($0,"REMOTE_SHARE")
    if(split(share,sp,":")!=2 || sp[1] !~ /^[A-Za-z0-9][A-Za-z0-9_-]*$/ || !path_ok(sp[2]) || sp[2] ~ /^[-\/~]/) invalid()
}
/^REMOTE_PERCEPTION_DIR=/ {
    if (++dirs != 1) invalid()
    relay_dir=literal($0,"REMOTE_PERCEPTION_DIR")
    if(!path_ok(relay_dir) || relay_dir ~ /^-/) invalid()
}
/^RCLONE_CONF=/ {
    if (++confs != 1) invalid()
    conf=literal($0,"RCLONE_CONF")
    sub(/^\$HOME\//,"~/",conf)
    if(!path_ok(conf) || conf !~ /^(~\/|\/)/) invalid()
}
/^PERCEPTION_BOXES=/ {
    if (++boxes != 1) invalid()
    value=$0
    sub(/^PERCEPTION_BOXES=\(/,"",value)
    if(value !~ /\)[ \t]*(#.*)?$/) { invalid(); next }
    sub(/\)[ \t]*(#.*)?$/,"",value)
    gsub(/"/,"",value)
    sub(/^[ \t]+/,"",value); sub(/[ \t]+$/,"",value)
    n=split(value,hosts,/[ \t]+/)
    if(n==0) invalid()
    for(i=1;i<=n;i++) {
        if(hosts[i] !~ /^[A-Za-z0-9][A-Za-z0-9_.-]*$/) invalid()
        aliases=aliases (i>1 ? "," : "") hosts[i]
    }
}
/^[ \t]*sshfs_mount[ \t]+(theia-home|theia-work|delta-home|delta-scratch|delta-projects)[ \t]+/ {
    if(NF!=4 || $3 !~ /^"[A-Za-z0-9][A-Za-z0-9_.-]*:\/[A-Za-z0-9_.\/-]+"$/ || $4 !~ /^"\$HOME\/[A-Za-z0-9_.\/-]+"$/) { invalid(); next }
    label=$2
    if(++seen[label]!=1) invalid()
    remote=$3; gsub(/"/,"",remote)
    split(remote,endpoint,":")
    local_path=$4; sub(/^"\$HOME\//,"~/",local_path); sub(/"$/,"",local_path)
    if(!path_ok(endpoint[2]) || !path_ok(local_path)) invalid()
    group=(label ~ /^theia-/ ? "theia" : "delta")
    rows[label]=group "\t" label "\t" endpoint[1] "\t" endpoint[2] "\t" local_path "\trw"
}
/^[ \t]*perception_wang\)[ \t]*echo[ \t]+/ {
    if(++localshares!=1) invalid()
    value=$0
    sub(/^[ \t]*perception_wang\)[ \t]*echo[ \t]+/,"",value)
    if(value !~ /^"\$HOME\/[A-Za-z0-9_.\/-]+";;[ \t]*$/) { invalid(); next }
    sub(/^"\$HOME\//,"~/",value); sub(/";;[ \t]*$/,"",value)
    local_share=value
    if(!path_ok(local_share)) invalid()
}
END {
    n=split("theia-home theia-work delta-home delta-scratch delta-projects",order," ")
    for(i=1;i<=n;i++) if(seen[order[i]]!=1) invalid()
    if(shares!=1 || dirs!=1 || boxes!=1 || localshares!=1 || confs>1) invalid()
    if(bad) exit 1
    print "# Imported literal settings. Keep this file private."
    for(i=1;i<=n;i++) print rows[order[i]]
    print "perception\tperception_wang\t" aliases "\t" relay_dir "\t" local_share "\trw"
    out=ENVIRON["MOWNT_IMPORT_SETTINGS"]
    print "# Automation restored for the original configured relay hosts." > out
    print "SSH_MASTER=yes\nTAILSCALE=auto\nDELTA_LOGIN=~/.ssh/delta-login\nAUTO_PROVISION=yes\nAUTO_FORCE=yes\nDIRECT_FALLBACK=yes" > out
    print "SMB_REMOTE=" sp[1] "\nSMB_SHARE=" sp[2] > out
    print "RCLONE_CONFIG=" (confs==1 ? conf : "~/.config/rclone/rclone.conf") > out
    close(out)
}
' < "$SOURCE" > "$TMP/mounts.tsv" || die 'unsupported or ambiguous legacy layout; no configuration was imported'
chmod 600 "$TMP/mounts.tsv" "$TMP/automation.conf"
ln "$TMP/mounts.tsv" "$DEST/mounts.tsv"
created_mounts=1
ln "$TMP/automation.conf" "$DEST/automation.conf"
committed=1
printf 'Imported private configuration into %s\n' "$DEST"
printf 'SSH aliases, local credential files, and optional login helpers remain in place.\n'
