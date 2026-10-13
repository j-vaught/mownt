#!/bin/bash
# Synthetic legacy fixtures only. No source file is executed or contacted.
# shellcheck disable=SC2016,SC2088
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/mownt-import-test.XXXXXXXX")
SANDBOX=$(CDPATH='' cd -- "$SANDBOX" && pwd -P)
trap 'rm -rf -- "$SANDBOX"' EXIT HUP INT TERM
export HOME="$SANDBOX/home"
export MOCK_LOG="$SANDBOX/actions"
mkdir -p "$HOME" "$SANDBOX/mockbin"
chmod 700 "$HOME"
SOURCE="$SANDBOX/old-mownt"
OUTPUT="$SANDBOX/output"
DEST="$HOME/private-import"
COUNT=0
: > "$MOCK_LOG"
for command in ssh sshfs rclone mount umount diskutil fusermount fusermount3 tailscale sudo curl wget; do
    cat > "$SANDBOX/mockbin/$command" <<'MOCK'
#!/bin/bash
printf '%s %s\n' "$0" "$*" >> "$MOCK_LOG"
exit 99
MOCK
    chmod 700 "$SANDBOX/mockbin/$command"
done
export PATH="$SANDBOX/mockbin:$PATH"
fail() { printf 'FAIL %s\n' "$*" >&2; cat "$OUTPUT" >&2; exit 1; }
pass() { COUNT=$((COUNT + 1)); printf 'ok %s - %s\n' "$COUNT" "$*"; }
no_actions() {
    [ ! -s "$MOCK_LOG" ] || fail 'import invoked an external network or mount command'
    [ ! -e "$HOME/executed" ] || fail 'legacy source code was executed'
}
run() {
    expected=$1
    shift
    actual=0
    /bin/bash "$ROOT/tools/import-legacy.sh" "$@" > "$OUTPUT" 2>&1 || actual=$?
    [ "$actual" = "$expected" ] || fail "expected exit $expected, got $actual"
    no_actions
}
fixture() {
    cat > "$SOURCE" <<'LEGACY'
#!/bin/bash
RCLONE_CONF="$HOME/.config/rclone/rclone.conf"
REMOTE_SHARE="research:project/share"
REMOTE_PERCEPTION_DIR="mnt/share"
PERCEPTION_BOXES=("relay-a" "relay-b")
mount_original() {
    sshfs_mount theia-home "theia:/home/example" "$HOME/theia-home"
    sshfs_mount theia-work "theia:/work/example" "$HOME/theia-work"
    sshfs_mount delta-home "delta:/u/example" "$HOME/delta-home"
    sshfs_mount delta-scratch "delta:/scratch/example" "$HOME/delta-scratch"
    sshfs_mount delta-projects "delta:/projects/example" "$HOME/delta-projects"
}
case "$1" in
    perception_wang)echo "$HOME/perception_wang";;
esac
LEGACY
    chmod 600 "$SOURCE"
}
reset() {
    rm -rf "$DEST"
    fixture
    : > "$MOCK_LOG"
}
rejected() {
    run 1 "$SOURCE" "$DEST"
    [ ! -e "$DEST/mounts.tsv" ] && [ ! -e "$DEST/automation.conf" ] || fail 'rejected source left configuration files'
    [ ! -e "$DEST/.import.lock" ] || fail 'rejected source left its lock'
}
mode() {
    case "$(uname -s)" in
        Darwin) stat -f '%Lp' "$1" ;;
        Linux) stat -c '%a' -- "$1" ;;
        *) fail 'unsupported test platform' ;;
    esac
}

fixture
run 2
run 2 "$SOURCE"
pass 'usage requires source and explicit output directory'
run 1 "$SANDBOX/missing" "$DEST"
pass 'missing source is refused'

reset
run 0 "$SOURCE" "$DEST"
printf '%s\n' '# Imported literal settings. Keep this file private.' > "$SANDBOX/expected-mounts"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    theia theia-home theia /home/example '~/theia-home' rw \
    theia theia-work theia /work/example '~/theia-work' rw \
    delta delta-home delta /u/example '~/delta-home' rw \
    delta delta-scratch delta /scratch/example '~/delta-scratch' rw \
    delta delta-projects delta /projects/example '~/delta-projects' rw \
    perception perception_wang relay-a,relay-b mnt/share '~/perception_wang' rw >> "$SANDBOX/expected-mounts"
cmp -s "$SANDBOX/expected-mounts" "$DEST/mounts.tsv" || fail 'legacy mount mapping differs'
awk -F '\t' '!/^#/ && NF != 6 { exit 1 }' "$DEST/mounts.tsv" || fail 'mounts must have six fields'
pass 'all six legacy mounts preserve aliases and local and remote paths'
for setting in SSH_MASTER=yes TAILSCALE=auto 'DELTA_LOGIN=~/.ssh/delta-login' AUTO_PROVISION=yes AUTO_FORCE=yes DIRECT_FALLBACK=yes SMB_REMOTE=research SMB_SHARE=project/share 'RCLONE_CONFIG=~/.config/rclone/rclone.conf'; do
    grep -Fqx -- "$setting" "$DEST/automation.conf" || fail "missing automation setting $setting"
done
pass 'share remote and rclone path map to automation settings'
[ "$(mode "$DEST")" = 700 ] || fail 'output directory is not private'
[ "$(mode "$DEST/mounts.tsv")" = 600 ] || fail 'mount table is not private'
[ "$(mode "$DEST/automation.conf")" = 600 ] || fail 'automation file is not private'
[ ! -e "$DEST/.import.lock" ] || fail 'successful import left its lock'
pass 'directory and files use private permissions and clean up the lock'
cp "$DEST/mounts.tsv" "$SANDBOX/saved-mounts"
cp "$DEST/automation.conf" "$SANDBOX/saved-automation"
run 1 "$SOURCE" "$DEST"
cmp -s "$DEST/mounts.tsv" "$SANDBOX/saved-mounts" || fail 'existing mount table changed'
cmp -s "$DEST/automation.conf" "$SANDBOX/saved-automation" || fail 'existing automation changed'
pass 'repeated import refuses to overwrite existing configuration'

reset
sed '/^RCLONE_CONF=/d' "$SOURCE" > "$SANDBOX/changed"
mv "$SANDBOX/changed" "$SOURCE"
run 0 "$SOURCE" "$DEST"
grep -Fqx 'RCLONE_CONFIG=~/.config/rclone/rclone.conf' "$DEST/automation.conf" || fail 'default rclone path missing'
pass 'omitted optional rclone path receives the documented default'

reset
cat >> "$SOURCE" <<'PAYLOAD'
touch "$HOME/executed"
ssh hostile.example
rclone mount hostile:share "$HOME/evil"
ignored=$(touch "$HOME/executed")
PAYLOAD
run 0 "$SOURCE" "$DEST"
pass 'unrelated source shell code is read without execution'

for assignment in \
    'REMOTE_SHARE="$(touch "$HOME/executed"):share"' \
    'REMOTE_SHARE="research:../private"' \
    'REMOTE_SHARE="research:/absolute"' \
    'REMOTE_PERCEPTION_DIR="mnt/../private"' \
    'REMOTE_PERCEPTION_DIR="$(touch "$HOME/executed")"' \
    'PERCEPTION_BOXES=(relay-a -oProxyCommand=evil)' \
    'PERCEPTION_BOXES=($(touch "$HOME/executed"))' \
    'RCLONE_CONF="$HOME/../private/rclone.conf"'; do
    reset
    key=${assignment%%=*}
    awk -v key="$key" 'index($0,key "=") != 1 { print }' "$SOURCE" > "$SANDBOX/changed"
    printf '%s\n' "$assignment" >> "$SANDBOX/changed"
    mv "$SANDBOX/changed" "$SOURCE"
    rejected
done
pass 'shell expansions and unsafe assignment values are rejected without execution'

for filter in \
    '/sshfs_mount delta-projects/d' \
    '/^PERCEPTION_BOXES=/d' \
    '/perception_wang)echo/d' \
    '/^REMOTE_SHARE=/d'; do
    reset
    sed "$filter" "$SOURCE" > "$SANDBOX/changed"
    mv "$SANDBOX/changed" "$SOURCE"
    rejected
done
pass 'partial legacy layouts are refused without importing partial files'

reset
printf '%s\n' 'REMOTE_SHARE="other:share"' >> "$SOURCE"
rejected
reset
printf '%s\n' 'sshfs_mount theia-home "other:/home/example" "$HOME/other-home"' >> "$SOURCE"
rejected
pass 'duplicate assignments and duplicate mounts are refused'

reset
sed 's|"theia:/home/example"|"theia:/home/../private"|' "$SOURCE" > "$SANDBOX/changed"
mv "$SANDBOX/changed" "$SOURCE"
rejected
reset
sed 's|"\$HOME/theia-home"|"\$(touch private)/theia-home"|' "$SOURCE" > "$SANDBOX/changed"
mv "$SANDBOX/changed" "$SOURCE"
rejected
pass 'unsafe remote and local mount paths are refused'

reset
run 1 "$SOURCE" "$SANDBOX/outside"
run 1 "$SOURCE" "$HOME"
run 1 "$SOURCE" "$HOME/../escape"
run 1 "$SOURCE" "$HOME/./escape"
run 1 "$SOURCE" "$HOME/path with spaces"
pass 'output stays strictly beneath HOME with a safe path grammar'

reset
mkdir "$SANDBOX/foreign"
ln -s "$SANDBOX/foreign" "$DEST"
run 1 "$SOURCE" "$DEST"
[ ! -e "$SANDBOX/foreign/mounts.tsv" ] || fail 'wrote through symlink directory'
rm "$DEST"
mkdir "$HOME/linked-parent"
ln -s "$SANDBOX/foreign" "$HOME/linked-parent/link"
run 1 "$SOURCE" "$HOME/linked-parent/link/child"
[ ! -e "$SANDBOX/foreign/child" ] || fail 'wrote through symlink ancestor'
pass 'symlink output directories and ancestors are refused'

reset
mkdir "$DEST"
chmod 755 "$DEST"
run 1 "$SOURCE" "$DEST"
[ "$(mode "$DEST")" = 755 ] || fail 'existing directory permissions were changed'
rm -rf "$DEST"
mkdir "$HOME/shared-parent"
chmod 777 "$HOME/shared-parent"
run 1 "$SOURCE" "$HOME/shared-parent/import"
[ ! -e "$HOME/shared-parent/import" ] || fail 'created output beneath a shared ancestor'
pass 'shared output permissions and writable ancestors are refused'

reset
mkdir "$DEST"
chmod 700 "$DEST"
printf 'preserve\n' > "$SANDBOX/preserve"
ln -s "$SANDBOX/preserve" "$DEST/mounts.tsv"
run 1 "$SOURCE" "$DEST"
[ "$(cat "$SANDBOX/preserve")" = preserve ] || fail 'existing symlink target changed'
[ -L "$DEST/mounts.tsv" ] || fail 'existing output symlink changed'
[ ! -e "$DEST/automation.conf" ] || fail 'no-clobber failure wrote automation'
pass 'existing output symlinks are preserved and refused'

reset
sed 's|RCLONE_CONF=.*|RCLONE_CONF="/private/example/rclone.conf"|; s|REMOTE_PERCEPTION_DIR=.*|REMOTE_PERCEPTION_DIR="/srv/share"|' "$SOURCE" > "$SANDBOX/changed"
mv "$SANDBOX/changed" "$SOURCE"
run 0 "$SOURCE" "$DEST"
grep -Fqx 'RCLONE_CONFIG=/private/example/rclone.conf' "$DEST/automation.conf" || fail 'absolute rclone config path changed'
awk -F '\t' '$1 == "perception" { if ($4 != "/srv/share") exit 1; found=1 } END { if (!found) exit 1 }' "$DEST/mounts.tsv" || fail 'absolute relay path changed'
pass 'explicit absolute config and relay paths are preserved'

reset
mkdir "$DEST"
chmod 700 "$DEST"
printf 'preserve automation\n' > "$DEST/automation.conf"
run 1 "$SOURCE" "$DEST"
[ "$(cat "$DEST/automation.conf")" = 'preserve automation' ] || fail 'existing standalone automation file changed'
[ ! -e "$DEST/mounts.tsv" ] || fail 'no-clobber failure wrote mount table'
pass 'standalone existing automation file prevents all output'

reset
mkdir "$DEST"
chmod 700 "$DEST"
ln -s "$SANDBOX/missing-target" "$DEST/automation.conf"
run 1 "$SOURCE" "$DEST"
[ -L "$DEST/automation.conf" ] || fail 'dangling output symlink changed'
[ ! -e "$SANDBOX/missing-target" ] || fail 'dangling output symlink target was created'
[ ! -e "$DEST/mounts.tsv" ] || fail 'dangling symlink failure wrote mount table'
pass 'dangling output symlinks are refused without output'

reset
mkdir "$DEST"
chmod 700 "$DEST"
mkdir "$DEST/.import.lock"
run 1 "$SOURCE" "$DEST"
[ -d "$DEST/.import.lock" ] || fail 'existing import lock was removed'
[ ! -e "$DEST/mounts.tsv" ] && [ ! -e "$DEST/automation.conf" ] || fail 'concurrent import produced output'
pass 'existing import lock prevents concurrent writes'

printf 'All %s legacy import checks passed.\n' "$COUNT"
