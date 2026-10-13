#!/bin/bash
# Isolated blackbox checks. No real SSH or mount operation is invoked.
# Test fixtures deliberately contain literal shell substitutions and tildes.
# shellcheck disable=SC2016,SC2088
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/mownt-test.XXXXXXXX")
SANDBOX=$(CDPATH='' cd -- "$SANDBOX" && pwd -P)
trap 'rm -rf -- "$SANDBOX"' EXIT HUP INT TERM
REAL_STAT=$(command -v stat)
export REAL_STAT
export HOME="$SANDBOX/home"
export XDG_CONFIG_HOME="$HOME/.config"
export MOCK_LOG="$SANDBOX/commands.log"
export MOCK_MOUNTS="$SANDBOX/mounts"
export MOCK_FAIL_SSH=0 MOCK_FAIL_SSHFS=0 MOCK_STALE=0 MOCK_GUARD_FAIL=0
mkdir -p "$HOME/.config/mownt" "$SANDBOX/mockbin"
chmod 700 "$HOME/.config/mownt"
CONFIG="$HOME/.config/mownt/mounts.tsv"
OUTPUT="$SANDBOX/output"
: > "$MOCK_LOG"
: > "$MOCK_MOUNTS"

cat > "$SANDBOX/mockbin/ssh" <<'MOCK'
#!/bin/bash
printf 'ssh %s\n' "$*" >> "$MOCK_LOG"
[ "$MOCK_FAIL_SSH" != 1 ] || exit 255
case "$*" in *"mountpoint -q --"*) [ "$MOCK_GUARD_FAIL" != 1 ] || exit 1 ;; esac
for argument in "$@"; do
    [ "$argument" != unavailable ] || exit 255
    [ "$argument" != unmounted ] || exit 1
done
exit 0
MOCK
cat > "$SANDBOX/mockbin/sshfs" <<'MOCK'
#!/bin/bash
printf 'sshfs %s\n' "$*" >> "$MOCK_LOG"
[ "$MOCK_FAIL_SSHFS" != 1 ] || exit 1
case "$*" in *unavailable:*) exit 1 ;; esac
source_path=''
target=''
for argument in "$@"; do
    case "$argument" in
        *:*) [ -n "$source_path" ] || source_path=$argument ;;
        "$HOME"/*) [ -n "$target" ] || target=$argument ;;
    esac
done
[ -n "$source_path" ] && [ -n "$target" ] || exit 1
if [ "$(uname -s)" = Darwin ]; then
    printf '%s on %s (macfuse, nodev, nosuid)\n' "$source_path" "$target" >> "$MOCK_MOUNTS"
else
    printf '%s on %s type fuse.sshfs (rw,nodev,nosuid)\n' "$source_path" "$target" >> "$MOCK_MOUNTS"
fi
MOCK
cat > "$SANDBOX/mockbin/mount" <<'MOCK'
#!/bin/bash
cat "$MOCK_MOUNTS"
MOCK
cat > "$SANDBOX/mockbin/stat" <<'MOCK'
#!/bin/bash
if [ "$#" = 1 ]; then
    case "$1" in
        "$HOME"/mnt/*)
            [ "$MOCK_STALE" != 1 ] || exit 1
            [ "$MOCK_STALE" != 2 ] || exec sleep 30
            ;;
    esac
fi
exec "$REAL_STAT" "$@"
MOCK
cat > "$SANDBOX/mockbin/umount" <<'MOCK'
#!/bin/bash
printf 'umount %s\n' "$*" >> "$MOCK_LOG"
: > "$MOCK_MOUNTS"
MOCK
cat > "$SANDBOX/mockbin/fusermount" <<'MOCK'
#!/bin/bash
printf 'fusermount %s\n' "$*" >> "$MOCK_LOG"
: > "$MOCK_MOUNTS"
MOCK
cat > "$SANDBOX/mockbin/diskutil" <<'MOCK'
#!/bin/bash
printf 'diskutil %s\n' "$*" >> "$MOCK_LOG"
: > "$MOCK_MOUNTS"
MOCK
cp "$SANDBOX/mockbin/fusermount" "$SANDBOX/mockbin/fusermount3"
chmod 700 "$SANDBOX/mockbin/"*
export PATH="$SANDBOX/mockbin:$PATH"

COUNT=0
fail() { printf 'FAIL %s\n' "$*" >&2; cat "$OUTPUT" >&2; exit 1; }
pass() { COUNT=$((COUNT + 1)); printf 'ok %s - %s\n' "$COUNT" "$*"; }
run() {
    expected=$1
    shift
    actual=0
    /bin/bash "$ROOT/bin/mownt" --config "$CONFIG" "$@" > "$OUTPUT" 2>&1 || actual=$?
    [ "$actual" = "$expected" ] || fail "expected exit $expected, got $actual for $*"
}
config() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' theia example "${1:-available}" /remote/data "${2:-~/mnt/example}" rw > "$CONFIG"
    chmod 600 "$CONFIG"
}
no_actions() { [ ! -s "$MOCK_LOG" ] || fail 'unexpected network or mount action'; }
reset() {
    : > "$MOCK_LOG"
    : > "$MOCK_MOUNTS"
    export MOCK_FAIL_SSH=0 MOCK_FAIL_SSHFS=0 MOCK_STALE=0 MOCK_GUARD_FAIL=0
    chmod 700 "$HOME/.config/mownt"
    rm -f "$CONFIG"
    config
}

reset
run 0 --help
no_actions
pass 'help requires no network or mount'
run 2 up --force
no_actions
pass 'force is refused outside down'
run 2 --unknown
no_actions
pass 'unknown options fail'

run 0 up --dry-run
no_actions
[ ! -e "$HOME/mnt" ] || fail 'dry-run created a mountpoint'
pass 'dry-run has no network, mount, or directory side effects'
run 0 doctor
no_actions
pass 'doctor is offline'
run 0 up -theia --dry-run
run 1 up -delta --dry-run
no_actions
pass 'legacy group selectors preserve selection semantics'

printf 'touch "%s"\n' "$SANDBOX/executed" > "$CONFIG"
run 2 up
[ ! -e "$SANDBOX/executed" ] || fail 'configuration was executed'
no_actions
pass 'shell content in configuration is rejected as data'

for alias in '-oProxyCommand=evil' 'host;touch-pwned' '$(touch-pwned)' 'host,,second'; do
    reset
    config "$alias"
    run 2 up
    no_actions
done
pass 'unsafe and empty SSH aliases are rejected'

for remote in '/data;touch-pwned' '/data/../secret' '/data/$(touch-pwned)'; do
    reset
    printf 'theia\texample\tavailable\t%s\t~/mnt/example\trw\n' "$remote" > "$CONFIG"
    run 2 up
    no_actions
done
pass 'unsafe remote paths are rejected'

for local_path in '/tmp/mownt-escape' '~/../escape' '~/mnt/../escape' '~other/data' '~/mnt/path with spaces'; do
    reset
    config available "$local_path"
    run 2 up
    no_actions
done
pass 'mount targets remain within the permitted home path grammar'

reset
chmod 644 "$CONFIG"
run 2 up
no_actions
pass 'group or world readable configuration is rejected'
reset
chmod 755 "$HOME/.config/mownt"
run 2 up
no_actions
pass 'shared configuration directory is rejected'
reset
chmod 777 "$HOME/.config"
run 2 up
no_actions
chmod 700 "$HOME/.config"
pass 'writable configuration ancestors are rejected'
reset
mv "$CONFIG" "$SANDBOX/linked-config"
ln -s "$SANDBOX/linked-config" "$CONFIG"
run 2 up
no_actions
pass 'symlink configuration is rejected'

reset
mkdir -p "$HOME/mnt" "$SANDBOX/outside"
ln -s "$SANDBOX/outside" "$HOME/mnt/symlink"
config available '~/mnt/symlink/nested'
run 1 up
no_actions
pass 'symlink mount ancestors are rejected'

reset
mkdir -p "$HOME/mnt/nonempty"
printf 'keep me\n' > "$HOME/mnt/nonempty/important"
config available '~/mnt/nonempty'
run 1 up
[ "$(cat "$HOME/mnt/nonempty/important")" = 'keep me' ] || fail 'existing data changed'
if grep -Eq '^sshfs ' "$MOCK_LOG"; then fail 'mounted over existing data'; fi
pass 'nonempty mountpoint is preserved'

reset
export MOCK_FAIL_SSHFS=1
run 1 up
pass 'SSHFS failure produces an operation failure'

reset
config unavailable,available
run 0 up
grep -Eq '^sshfs unavailable:' "$MOCK_LOG" || fail 'first alias was not checked'
grep -Eq '^sshfs available:' "$MOCK_LOG" || fail 'fallback alias was not mounted'
for option in StrictHostKeyChecking=yes ForwardAgent=no ForwardX11=no ClearAllForwardings=yes PermitLocalCommand=no ControlPath=none idmap=user nosuid,nodev,default_permissions; do
    grep -Fq -- "$option" "$MOCK_LOG" || fail "secure mount option missing $option"
done
pass 'aliases fail over in priority order with secure mount options'

reset
mkdir -p "$HOME/mnt/example"
if [ "$(uname -s)" = Darwin ]; then
    printf 'someone:/other on %s (macfuse, nodev, nosuid)\n' "$HOME/mnt/example" > "$MOCK_MOUNTS"
else
    printf 'someone:/other on %s type fuse.sshfs (rw,nodev,nosuid)\n' "$HOME/mnt/example" > "$MOCK_MOUNTS"
fi
run 1 up
if grep -Eq '^sshfs |^umount |^diskutil |^fusermount ' "$MOCK_LOG"; then fail 'foreign mount was modified'; fi
run 1 down
if grep -Eq '^umount |^diskutil |^fusermount ' "$MOCK_LOG"; then fail 'foreign mount was unmounted'; fi
pass 'an unrelated existing mount is preserved'

reset
mkdir -p "$HOME/mnt/example"
if [ "$(uname -s)" = Darwin ]; then
    printf 'available:/remote/data on %s (apfs, local)\n' "$HOME/mnt/example" > "$MOCK_MOUNTS"
else
    printf 'available:/remote/data on %s type ext4 (rw)\n' "$HOME/mnt/example" > "$MOCK_MOUNTS"
fi
run 1 down
no_actions
pass 'a matching source on a non-SSHFS filesystem is refused'

reset
run 0 up
: > "$MOCK_LOG"
run 0 up
no_actions
run 0 status
no_actions
export MOCK_STALE=1
run 1 status
run 1 up
no_actions
pass 'live mounts are idempotent and stale mounts require manual down'
export MOCK_STALE=2
BEFORE=$SECONDS
run 1 status
[ "$((SECONDS - BEFORE))" -lt 12 ] || fail 'blocked health probe exceeded its deadline'
no_actions
export MOCK_STALE=0
pass 'a blocked health probe returns a stale failure within its deadline'
run 0 down
if grep -Eq 'force| -f | -uz ' "$MOCK_LOG"; then fail 'ordinary down forced an unmount'; fi
[ ! -s "$MOCK_MOUNTS" ] || fail 'ordinary down did not detach the mount'
pass 'ordinary down detaches only the selected expected mount without force'

reset
printf 'perception\trelay\tunmounted,available\t/remote/mounted\t~/mnt/relay\tro\n' > "$CONFIG"
run 0 up
[ "$(grep -c '^ssh ' "$MOCK_LOG")" -eq 2 ] || fail 'relay guards did not check both candidates'
grep -Eq '^ssh .*mountpoint -q --' "$MOCK_LOG" || fail 'relay prerequisite was not checked'
grep -Fq -- "mountpoint -q -- '/remote/mounted'" "$MOCK_LOG" || fail 'absolute relay guard changed'
if grep -Eq '^sshfs unmounted:' "$MOCK_LOG"; then fail 'bare relay directory was mounted'; fi
grep -Eq '^sshfs available:' "$MOCK_LOG" || fail 'mounted relay fallback was not selected'
pass 'perception requires a remote mountpoint and fails over from an unmounted relay'

reset
printf 'perception\trelay\tavailable\t/remote/mounted\t~/mnt/relay\tro\n' > "$CONFIG"
export MOCK_GUARD_FAIL=1
run 1 up
if grep -Eq '^sshfs ' "$MOCK_LOG"; then fail 'relay prerequisite failure reached SSHFS'; fi
pass 'missing remote mountpoint fails closed'

for remote in '~/mnt/share' 'mnt/share'; do
    reset
    printf 'perception\trelay\tunmounted,available\t%s\t~/mnt/relay\tro\n' "$remote" > "$CONFIG"
    run 0 up
    grep -Fq -- "mountpoint -q -- \"\$HOME\"/'mnt/share'" "$MOCK_LOG" || fail 'relative relay guard must expand remote HOME only'
    grep -Eq '^sshfs available:mnt/share ' "$MOCK_LOG" || fail 'relative SSHFS path was not normalized'
    if grep -Eq '^sshfs unmounted:' "$MOCK_LOG"; then fail 'relative path bypassed relay guard'; fi
done
pass 'relative relay paths use remote HOME and preserve guarded failover'

for remote in '~/../secret' 'mnt/../secret' 'mnt/./share' 'mnt/$(touch-pwned)' "mnt/share'" '~'; do
    reset
    printf 'perception\trelay\tavailable\t%s\t~/mnt/relay\tro\n' "$remote" > "$CONFIG"
    run 2 up
    no_actions
done
pass 'relative relay paths reject traversal and shell injection'

reset
printf 'theia\tgood\tavailable\t/remote/data\t~/mnt/good\trw\ntheia\tbad\tunavailable\t/remote/data\t~/mnt/bad\trw\n' > "$CONFIG"
run 1 up
grep -Eq '^sshfs available:' "$MOCK_LOG" || fail 'healthy entry was not attempted'
grep -Eq '^sshfs unavailable:' "$MOCK_LOG" || fail 'failing entry was not attempted'
pass 'one failed entry makes the aggregate command fail'

reset
run 0 down
no_actions
pass 'down succeeds safely when already absent'

install_run() {
    expected=$1
    shift
    actual=0
    /bin/bash "$ROOT/install.sh" "$@" > "$OUTPUT" 2>&1 || actual=$?
    [ "$actual" = "$expected" ] || fail "installer expected exit $expected, got $actual"
}
PREFIX="$HOME/tools"
cp "$CONFIG" "$SANDBOX/config-before-install"
if [ "$(uname -s)" = Darwin ]; then
    CONFIG_METADATA=$("$REAL_STAT" -f '%u %Lp' "$CONFIG")
else
    CONFIG_METADATA=$("$REAL_STAT" -c '%u %a' "$CONFIG")
fi
install_run 1 --prefix "$SANDBOX/outside-home"
install_run 1 --prefix "$HOME/../escape"
mkdir -p "$HOME/writable-prefix"
chmod 777 "$HOME/writable-prefix"
install_run 1 --prefix "$HOME/writable-prefix/tools"
[ ! -e "$HOME/writable-prefix/tools" ] || fail 'installer wrote into an unsafe prefix'
pass 'installer rejects outside, traversing, and writable prefixes'
install_run 0 --prefix "$PREFIX" --dry-run
[ ! -e "$PREFIX" ] || fail 'installer dry-run wrote files'
pass 'installer dry-run is read-only'
install_run 0 --prefix "$PREFIX"
[ -x "$PREFIX/bin/mownt" ] || fail 'installed command is missing'
cmp -s "$CONFIG" "$SANDBOX/config-before-install" || fail 'installer changed live configuration'
if [ "$(uname -s)" = Darwin ]; then
    [ "$("$REAL_STAT" -f '%u %Lp' "$CONFIG")" = "$CONFIG_METADATA" ] || fail 'installer changed config metadata'
else
    [ "$("$REAL_STAT" -c '%u %a' "$CONFIG")" = "$CONFIG_METADATA" ] || fail 'installer changed config metadata'
fi
pass 'installer installs the command'
printf 'preserve\n' > "$PREFIX/bin/mownt"
install_run 1 --prefix "$PREFIX"
[ "$(cat "$PREFIX/bin/mownt")" = preserve ] || fail 'installer clobbered without force'
pass 'installer refuses an existing target'
install_run 0 --prefix "$PREFIX" --force
[ -x "$PREFIX/bin/mownt" ] || fail 'explicit reinstall failed'
pass 'installer supports an explicit forced reinstall'
rm "$PREFIX/bin/mownt"
ln -s "$SANDBOX/outside-target" "$PREFIX/bin/mownt"
install_run 1 --prefix "$PREFIX" --force
[ ! -e "$SANDBOX/outside-target" ] || fail 'installer followed target symlink'
pass 'installer refuses symlink targets even with force'
ln -s "$SANDBOX/outside" "$HOME/symlink-prefix"
install_run 1 --prefix "$HOME/symlink-prefix/nested"
[ ! -e "$SANDBOX/outside/nested" ] || fail 'installer followed prefix symlink'
pass 'installer refuses symlink ancestors'

printf 'All %s isolated checks passed.\n' "$COUNT"
