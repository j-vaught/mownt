#!/bin/bash
# Isolated blackbox checks. No real SSH or mount operation is invoked.
# Test fixtures deliberately contain literal shell substitutions and tildes.
# shellcheck disable=SC2016,SC2088
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/mownt-test.XXXXXXXX")
SANDBOX=$(CDPATH='' cd -- "$SANDBOX" && pwd -P)
cleanup() {
    local pid command
    if [ -f "$SANDBOX/home/.mock-rclone-pid" ]; then
        read -r pid < "$SANDBOX/home/.mock-rclone-pid"
        if [[ "$pid" =~ ^[0-9]+$ ]]; then
            command=$(ps -p "$pid" -o command= 2>/dev/null) || command=''
            case "$command" in *"$SANDBOX/mockbin/rclone"*) kill -TERM "$pid" 2>/dev/null || true ;; esac
        fi
    fi
    rm -rf -- "$SANDBOX"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
REAL_STAT=$(command -v stat)
export REAL_STAT
export HOME="$SANDBOX/home"
export XDG_CONFIG_HOME="$HOME/.config"
export MOCK_LOG="$SANDBOX/commands.log"
export MOCK_MOUNTS="$SANDBOX/mounts"
export MOCK_FAIL_SSH=0 MOCK_FAIL_SSHFS=0 MOCK_STALE=0 MOCK_GUARD_FAIL=0
export MOCK_UNMOUNT_FAIL=0 MOCK_TS_UP=1 MOCK_RELAY_REPAIR=0
export MOCK_HELPER_MISSING=0 MOCK_RELAY_NOT_READY=0
export MOCK_REMOTE_STALE=0
mkdir -p "$HOME/.config/mownt" "$SANDBOX/mockbin"
chmod 700 "$HOME/.config/mownt"
CONFIG="$HOME/.config/mownt/mounts.tsv"
AUTOMATION="$HOME/.config/mownt/automation.conf"
OUTPUT="$SANDBOX/output"
: > "$MOCK_LOG"
: > "$MOCK_MOUNTS"

cat > "$SANDBOX/mockbin/ssh" <<'MOCK'
#!/bin/bash
printf 'ssh %s\n' "$*" >> "$MOCK_LOG"
[ "$MOCK_FAIL_SSH" != 1 ] || exit 255
alias=''
operation=''
next=''
open=0
for argument in "$@"; do
    if [ -n "$next" ]; then
        [ "$next" != operation ] || operation=$argument
        next=''
        continue
    fi
    case "$argument" in
        -O) next=operation ;;
        -o|-S|-p|-l|-F) next=skip ;;
        -fN|-MNf|-Nf|-M) open=1 ;;
        -*) ;;
        *) [ -n "$alias" ] || alias=$argument ;;
    esac
done
[ "$alias" != unavailable ] || exit 255
if [ "$operation" = check ]; then [ -f "$HOME/.mock-master-$alias" ]; exit $?; fi
if [ "$open" = 1 ]; then : > "$HOME/.mock-master-$alias"; exit 0; fi
case "$*" in *"mountpoint -q --"*) [ "$MOCK_GUARD_FAIL" != 1 ] || exit 1 ;; esac
case "$*" in
    *" sync "*|*"'sync'"*)
        incoming="$HOME/.mock-relay-sync-$alias.new"
        cat > "$incoming"
        if cmp -s "$incoming" "$HOME/.mock-relay-sync-$alias"; then status=unchanged; else status=changed; fi
        mv "$incoming" "$HOME/.mock-relay-sync-$alias"
        printf '%s\n' "$status"
        exit 0 ;;
    *" setup "*|*"'setup'"*) cat > /dev/null; exit 0 ;;
    *" reload "*|*"'reload'"*|*" mount "*|*"'mount'"*)
        cat > /dev/null
        [ "$MOCK_GUARD_FAIL" != 1 ] || exit 1
        [ "$alias" != unmounted ] || [ "$MOCK_RELAY_REPAIR" = 1 ] || exit 1
        case "$*" in *"'mount'"*) [ "$MOCK_REMOTE_STALE" != 1 ] || exit 1 ;; esac
        : > "$HOME/.mock-relay-ready-$alias"
        exit 0 ;;
    *" check "*|*"'check'"*)
        cat > /dev/null
        [ "$MOCK_GUARD_FAIL" != 1 ] || exit 1
        [ "$MOCK_RELAY_NOT_READY" != 1 ] || [ -f "$HOME/.mock-relay-ready-$alias" ] || exit 1
        [ "$alias" != unmounted ] || [ -f "$HOME/.mock-relay-ready-$alias" ] || exit 1
        exit 0 ;;
    *"cat >"*|*"cat > "*) cat > "$HOME/.mock-helper-payload-$alias"; : > "$HOME/.mock-helper-$alias"; exit 0 ;;
esac
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
            if [ "$MOCK_STALE" = once ] && [ ! -f "$HOME/.mock-health-failed" ]; then
                : > "$HOME/.mock-health-failed"
                exit 1
            fi
            ;;
    esac
fi
exec "$REAL_STAT" "$@"
MOCK
cat > "$SANDBOX/mockbin/umount" <<'MOCK'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >> "$MOCK_LOG"
force=0
for argument in "$@"; do
    target=$argument
    case "$argument" in force|-f|-uz) force=1 ;; esac
done
[ "$MOCK_UNMOUNT_FAIL" != 2 ] || exit 1
[ "$MOCK_UNMOUNT_FAIL" != 1 ] || [ "$force" = 1 ] || exit 1
awk -v p="$target" '$3 != p' "$MOCK_MOUNTS" > "$MOCK_MOUNTS.new"
mv "$MOCK_MOUNTS.new" "$MOCK_MOUNTS"
MOCK
cp "$SANDBOX/mockbin/umount" "$SANDBOX/mockbin/fusermount"
cp "$SANDBOX/mockbin/umount" "$SANDBOX/mockbin/fusermount3"
cp "$SANDBOX/mockbin/umount" "$SANDBOX/mockbin/diskutil"
cat > "$SANDBOX/mockbin/tailscale" <<'MOCK'
#!/bin/bash
printf 'tailscale %s\n' "$*" >> "$MOCK_LOG"
case "$1" in status) [ "$MOCK_TS_UP" = 1 ] ;; up) exit 0 ;; *) exit 1 ;; esac
MOCK
cat > "$SANDBOX/mockbin/rclone" <<'MOCK'
#!/bin/bash
printf 'rclone %s\n' "$*" >> "$MOCK_LOG"
case "$*" in *"obscure -"*) cat > /dev/null; printf 'fake-test-obscured-new\n'; exit 0 ;; esac
source_path=''
target=''
for argument in "$@"; do
    case "$argument" in *:*) [ -n "$source_path" ] || source_path=$argument ;; "$HOME"/mnt/*) [ -n "$target" ] || target=$argument ;; esac
done
[ -n "$source_path" ] && [ -n "$target" ] || exit 1
if [ "$(uname -s)" = Darwin ]; then
    printf '127.0.0.1:/mownt-test on %s (nfs, nodev, nosuid)\n' "$target" >> "$MOCK_MOUNTS"
else
    printf '%s on %s type fuse.rclone (rw,nodev,nosuid,user_id=%s)\n' "$source_path" "$target" "$(id -u)" >> "$MOCK_MOUNTS"
fi
printf '%s\n' "$$" > "$HOME/.mock-rclone-pid"
while :; do sleep 1; done
MOCK
cat > "$SANDBOX/mockbin/pkill" <<'MOCK'
#!/bin/bash
printf 'FORBIDDEN process-wide kill %s\n' "$*" >> "$MOCK_LOG"
exit 99
MOCK
cp "$SANDBOX/mockbin/pkill" "$SANDBOX/mockbin/killall"
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
    export MOCK_UNMOUNT_FAIL=0 MOCK_TS_UP=1 MOCK_RELAY_REPAIR=0
    export MOCK_HELPER_MISSING=0 MOCK_RELAY_NOT_READY=0
    export MOCK_REMOTE_STALE=0
    rm -f "$HOME"/.mock-master-* "$HOME"/.mock-relay-* "$HOME"/.mock-helper-* "$HOME/.mock-health-failed"
    rm -f "$HOME/.config/rclone/rclone.conf"
    chmod 700 "$HOME/.config/mownt"
    rm -f "$CONFIG"
    config
    printf 'SSH_MASTER=no\nTAILSCALE=off\nAUTO_PROVISION=no\nAUTO_FORCE=no\nDIRECT_FALLBACK=no\n' > "$AUTOMATION"
    chmod 600 "$AUTOMATION"
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
[ ! -e "$HOME/.config/mownt/state" ] || fail 'dry-run created control socket state'
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

for setting in 'SSH_MASTER=$(touch-pwned)' 'TAILSCALE=auto;execute' 'SMB_REMOTE=-option' 'SMB_SHARE=../escape' 'RCLONE_CONFIG=~/../escape' 'DELTA_LOGIN=~/bin/$(touch-pwned)' 'EXEC=execute' 'source=execute'; do
    reset
    printf '%s\n' "$setting" > "$AUTOMATION"
    run 2 up
    no_actions
done
pass 'automation settings are validated data without shell evaluation'

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
for option in StrictHostKeyChecking=yes ForwardAgent=no ForwardX11=no ClearAllForwardings=yes PermitLocalCommand=no ControlPath=none idmap=user nosuid,nodev; do
    grep -Fq -- "$option" "$MOCK_LOG" || fail "secure mount option missing $option"
done
if grep -Eq '(^|[, =])(default_permissions|allow_other)([, =]|$)' "$MOCK_LOG"; then
    fail 'SSHFS must preserve remote group authorization and local user isolation'
fi
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
grep -Eq '^(umount|diskutil|fusermount3?) ' "$MOCK_LOG" || fail 'stale expected mount was not recovered automatically'
if grep -Eq 'force| -f | -uz ' "$MOCK_LOG"; then fail 'disabled forced recovery still forced an unmount'; fi
: > "$MOCK_LOG"
pass 'live mounts are idempotent and stale expected mounts recover within configured limits'
if [ "$(uname -s)" = Darwin ]; then
    printf 'available:/remote/data on %s (macfuse, nodev, nosuid)\n' "$HOME/mnt/example" > "$MOCK_MOUNTS"
else
    printf 'available:/remote/data on %s type fuse.sshfs (rw,nodev,nosuid)\n' "$HOME/mnt/example" > "$MOCK_MOUNTS"
fi
export MOCK_STALE=2
BEFORE=$SECONDS
run 0 status --dry-run
run 0 up --dry-run
[ "$((SECONDS - BEFORE))" -lt 4 ] || fail 'mounted dry-run launched a blocked health probe'
no_actions
pass 'mounted dry-run avoids health probes and recovery side effects'
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

reset
mkdir -p "$HOME/.config/mownt/state/.operation-lock"
chmod 700 "$HOME/.config/mownt/state"
run 1 up
no_actions
[ -d "$HOME/.config/mownt/state/.operation-lock" ] || fail 'contending command removed another operation lock'
rmdir "$HOME/.config/mownt/state/.operation-lock"
pass 'concurrent local operation lock prevents mount and credential mutations'

write_smb_config() {
    mkdir -p "$HOME/.config/rclone"
    chmod 700 "$HOME/.config/rclone"
    cat > "$HOME/.config/rclone/rclone.conf" <<'CONFIG'
[unrelated]
type = local

[perception]
type = smb
host = files.example
user = fixture-user
pass = fake-test-obscured-old

[another]
type = local
CONFIG
    chmod 600 "$HOME/.config/rclone/rclone.conf"
}
perception_config() {
    printf 'perception\trelay\t%s\t~/mnt/share\t~/mnt/automated-relay\tro\n' "$1" > "$CONFIG"
}
automated() { rm "$AUTOMATION"; }
no_secret_log() {
    if grep -Eq 'fake-test-password|fake-test-obscured-(old|new)' "$MOCK_LOG" "$OUTPUT"; then fail 'credential appeared in command arguments or output'; fi
}

reset
automated
perception_config available
write_smb_config
rm -rf "$HOME/.config/mownt/state"
run 0 up --dry-run
run 0 -setup --dry-run
run 0 -pw --dry-run
no_actions
[ ! -e "$HOME/.config/mownt/state" ] || fail 'automatic dry-run created state'
[ ! -e "$HOME/mnt/automated-relay" ] || fail 'automatic dry-run created a mountpoint'
no_secret_log
pass 'all automatic dry-run actions stay offline and do not prompt or create state'

reset
automated
printf 'theia\tfirst\tavailable\t/remote/first\t~/mnt/master-first\tro\ntheia\tsecond\tavailable\t/remote/second\t~/mnt/master-second\tro\n' > "$CONFIG"
run 0 doctor
no_actions
run 0 up
[ "$(grep -Ec '(^| )-fN( |$)' "$MOCK_LOG")" -eq 1 ] || fail 'multiple mounts opened multiple SSH masters'
[ "$(grep -c '^sshfs ' "$MOCK_LOG")" -eq 2 ] || fail 'both master-backed mounts were not made'
: > "$MOCK_MOUNTS"
: > "$MOCK_LOG"
run 0 up
if grep -Eq '(^| )-fN( |$)' "$MOCK_LOG"; then fail 'an existing SSH master was reopened'; fi
pass 'one SSH master per alias is shared across mounts and reused by later invocations'

reset
automated
printf 'delta\tdelta-home\tdelta\t/remote/home\t~/mnt/delta-home\tro\n' > "$CONFIG"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
cat > "$HOME/.ssh/delta-login" <<'HELPER'
#!/bin/bash
printf '%s\n' "$*" >> "$HOME/delta-helper.log"
: > "$HOME/.mock-master-$1"
HELPER
chmod 700 "$HOME/.ssh/delta-login"
run 0 up
[ "$(cat "$HOME/delta-helper.log")" = delta ] || fail 'trusted Delta login helper was not used'
pass 'Delta uses the trusted login helper for its shared authenticated connection'

reset
automated
perception_config unmounted,available
write_smb_config
export MOCK_HELPER_MISSING=1 MOCK_RELAY_NOT_READY=1 MOCK_RELAY_REPAIR=1 MOCK_TS_UP=0
run 0 up
grep -Eq '^tailscale up' "$MOCK_LOG" || fail 'inactive private network was not started'
cmp -s "$ROOT/libexec/mownt-relay" "$HOME/.mock-helper-payload-unmounted" || fail 'relay did not receive the exact shipped helper'
grep -Eq "'setup'" "$MOCK_LOG" || fail 'missing relay tools were not provisioned'
grep -Eq "'(mount|reload)'" "$MOCK_LOG" || fail 'missing backing share was not mounted'
grep -Eq '^sshfs unmounted:' "$MOCK_LOG" || fail 'repaired preferred relay was not selected'
[ -s "$HOME/.mock-relay-sync-unmounted" ] || fail 'selected SMB credentials were not synchronized'
if grep -Fq '[unrelated]' "$HOME/.mock-relay-sync-unmounted"; then fail 'unrelated credential section crossed to relay'; fi
no_secret_log
pass 'private networking, verified helper setup, credential sync, and backing-share repair run automatically'

reset
automated
perception_config unmounted,available
write_smb_config
export MOCK_RELAY_NOT_READY=1
run 0 up
grep -Eq '^sshfs available:' "$MOCK_LOG" || fail 'failed backing-share repair did not fail over'
if grep -Eq '^sshfs unmounted:' "$MOCK_LOG"; then fail 'failed backing share reached SSHFS'; fi
pass 'a relay whose backing share cannot recover fails over to the next candidate'

reset
automated
perception_config available
write_smb_config
export MOCK_RELAY_NOT_READY=1 MOCK_REMOTE_STALE=1
run 0 up
grep -Eq "'reload'" "$MOCK_LOG" || fail 'stale backing mount did not use the scoped reload action'
grep -Eq '^sshfs available:' "$MOCK_LOG" || fail 'recovered backing mount was not used'
pass 'a stale backing share is reloaded before mounting its relay'

reset
automated
perception_config available
write_smb_config
run 0 up
sed 's/fake-test-obscured-old/fake-test-obscured-new/' "$HOME/.config/rclone/rclone.conf" > "$SANDBOX/changed-config"
cat "$SANDBOX/changed-config" > "$HOME/.config/rclone/rclone.conf"
: > "$MOCK_MOUNTS"
: > "$MOCK_LOG"
run 0 up
grep -Fq 'fake-test-obscured-new' "$HOME/.mock-relay-sync-available" || fail 'healthy relay did not receive changed local credentials'
if grep -Fq '[unrelated]' "$HOME/.mock-relay-sync-available"; then fail 'healthy relay received unrelated credentials'; fi
no_secret_log
pass 'a healthy relay receives current scoped credentials on the next mount'
: > "$MOCK_MOUNTS"
: > "$MOCK_LOG"
run 0 up
if grep -Eq "'reload'" "$MOCK_LOG"; then fail 'healthy relay with unchanged credentials was restarted'; fi
no_secret_log
pass 'healthy unchanged relay credentials preserve the existing backing mount'

reset
automated
perception_config unavailable
write_smb_config
run 0 up
grep -Eq '^rclone ' "$MOCK_LOG" || fail 'unusable relays did not trigger the direct fallback'
no_secret_log
run 0 down
pass 'direct share mounting remains available when every relay fails'

reset
automated
run 0 up
if [ "$(uname -s)" = Darwin ]; then
    printf 'other:/data on %s (macfuse, nodev, nosuid)\n' "$HOME/mnt/foreign" >> "$MOCK_MOUNTS"
else
    printf 'other:/data on %s type fuse.sshfs (rw,nodev,nosuid)\n' "$HOME/mnt/foreign" >> "$MOCK_MOUNTS"
fi
: > "$MOCK_LOG"
export MOCK_STALE=once MOCK_UNMOUNT_FAIL=1
run 0 up
grep -Eq 'force| -f | -uz ' "$MOCK_LOG" || fail 'stale expected mount did not use its configured force fallback'
grep -Fq 'other:/data' "$MOCK_MOUNTS" || fail 'automatic recovery changed an unrelated mount'
if grep -Eq '^FORBIDDEN|^(umount|diskutil|fusermount3?) .*foreign' "$MOCK_LOG"; then fail 'recovery affected an unrelated mount or process'; fi
pass 'stale recovery escalates only for the exact expected mount and preserves unrelated mounts and processes'

reset
automated
perception_config available,unavailable
write_smb_config
run 1 -setup
grep -Eq "'sync'" "$MOCK_LOG" || fail 'legacy setup did not synchronize a reachable relay'
if grep -Eq '^sshfs |^rclone ' "$MOCK_LOG"; then fail 'setup unexpectedly created a local mount'; fi
no_secret_log
pass 'legacy setup configures reachable relays and reports any failed candidate'

reset
automated
perception_config available
write_smb_config
printf 'fake-test-password\nfake-test-password\n' > "$SANDBOX/password-input"
chmod 600 "$SANDBOX/password-input"
run 0 -pw < "$SANDBOX/password-input"
grep -Fq 'pass = fake-test-obscured-new' "$HOME/.config/rclone/rclone.conf" || fail 'password rotation did not update the selected local block'
grep -Fq '[unrelated]' "$HOME/.config/rclone/rclone.conf" || fail 'password rotation removed unrelated local credentials'
grep -Fq 'fake-test-obscured-new' "$HOME/.mock-relay-sync-available" || fail 'password rotation did not sync relays over stdin'
no_secret_log
pass 'legacy password rotation uses stdin, preserves unrelated local config, and synchronizes only the selected block'

reset
automated
perception_config available,unavailable
write_smb_config
run 1 -pw < "$SANDBOX/password-input"
grep -Fq 'pass = fake-test-obscured-new' "$HOME/.config/rclone/rclone.conf" || fail 'partial relay failure lost the successful local password update'
grep -Fq 'fake-test-obscured-new' "$HOME/.mock-relay-sync-available" || fail 'partial relay failure skipped the reachable relay'
no_secret_log
pass 'password rotation reports failed relays while updating the reachable relay and local private block'

reset
automated
perception_config available
write_smb_config
cp "$HOME/.config/rclone/rclone.conf" "$SANDBOX/password-before"
printf 'fake-test-password\ndifferent-test-password\n' > "$SANDBOX/mismatched-password-input"
run 1 -pw < "$SANDBOX/mismatched-password-input"
cmp -s "$HOME/.config/rclone/rclone.conf" "$SANDBOX/password-before" || fail 'mismatched password input changed stored credentials'
no_secret_log
pass 'mismatched password input leaves existing credentials intact'

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
[ -x "$PREFIX/share/mownt/libexec/mownt-relay" ] || fail 'installed relay helper is missing'
[ -f "$PREFIX/share/mownt/automation.example.conf" ] || fail 'installed automation example is missing'
actual=0
/bin/bash "$PREFIX/bin/mownt" --config "$CONFIG" doctor > "$OUTPUT" 2>&1 || actual=$?
[ "$actual" = 0 ] || fail 'installed command cannot find its helper for offline doctor'
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

UNSAFE_PREFIX="$HOME/unsafe-helper-prefix"
mkdir -p "$UNSAFE_PREFIX/share/mownt/libexec"
ln -s "$SANDBOX/outside-helper" "$UNSAFE_PREFIX/share/mownt/libexec/mownt-relay"
install_run 1 --prefix "$UNSAFE_PREFIX" --force
[ ! -e "$SANDBOX/outside-helper" ] || fail 'installer followed a relay-helper symlink'
[ ! -e "$UNSAFE_PREFIX/bin/mownt" ] || fail 'installer partly wrote the command before validating the helper target'
pass 'installer validates the helper target before writing any release files'

printf 'All %s isolated checks passed.\n' "$COUNT"
