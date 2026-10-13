#!/bin/bash
# Execute relay-helper safety paths without a network or mount operation.
# A private executable copy changes only the fixed PATH assignment so dependency
# mocks can exercise the actual checksum, credential, lock, and write logic.
# The shipped helper keeps its fixed system PATH. Linux metadata is mocked on macOS.
# Fixtures deliberately include literal remote tildes and malicious shell text.
# shellcheck disable=SC2016,SC2088
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
SANDBOX=$(mktemp -d "$ROOT/tests/.relay-test.XXXXXXXX")
SANDBOX=$(CDPATH='' cd -- "$SANDBOX" && pwd -P)
trap 'rm -rf -- "$SANDBOX"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
REAL_STAT=$(command -v stat)
REAL_MV=$(command -v mv)
REAL_AWK=$(command -v awk)
REAL_CHMOD=$(command -v chmod)
REAL_SYSTEM=$(uname -s)
export REAL_STAT REAL_MV REAL_AWK REAL_CHMOD REAL_SYSTEM
export HOME="$SANDBOX/home"
export MOCK_ARCH=x86_64
export MOCK_FAIL_MV=0
mkdir -p "$HOME/.config/rclone" "$HOME/.local/bin" "$SANDBOX/mockbin"
chmod 700 "$HOME" "$HOME/.config" "$HOME/.config/rclone" "$HOME/.local" "$HOME/.local/bin"
OUTPUT="$SANDBOX/output"
CONFIG="$HOME/.config/rclone/rclone.conf"
COUNT=0
fail() { printf 'FAIL relay %s\n' "$*" >&2; cat "$OUTPUT" >&2; exit 1; }
pass() { COUNT=$((COUNT + 1)); printf 'ok relay %s - %s\n' "$COUNT" "$*"; }
cat > "$SANDBOX/mockbin/uname" <<'MOCK'
#!/bin/bash
case "$1" in -s) printf 'Linux\n' ;; -m) printf '%s\n' "$MOCK_ARCH" ;; *) exit 1 ;; esac
MOCK
cat > "$SANDBOX/mockbin/stat" <<'MOCK'
#!/bin/bash
if [ "$REAL_SYSTEM" = Darwin ] && [ "$1" = -c ]; then
    format=${2//%a/%Lp}
    format=${format//%h/%l}
    shift 2
    [ "${1:-}" != -- ] || shift
    exec "$REAL_STAT" -f "$format" "$@"
fi
exec "$REAL_STAT" "$@"
MOCK
cat > "$SANDBOX/mockbin/curl" <<'MOCK'
#!/bin/bash
printf 'curl %s\n' "$*" >> "$HOME/download.log"
while [ "$#" -gt 0 ]; do
    case "$1" in -o|--output) shift; printf 'invalid archive fixture\n' > "$1"; exit 0 ;; esac
    shift
done
exit 1
MOCK
cat > "$SANDBOX/mockbin/unzip" <<'MOCK'
#!/bin/bash
printf 'unzip %s\n' "$*" >> "$HOME/unzip.log"
exit 1
MOCK
cat > "$SANDBOX/mockbin/mv" <<'MOCK'
#!/bin/bash
[ "$MOCK_FAIL_MV" != 1 ] || exit 1
exec "$REAL_MV" "$@"
MOCK
cat > "$SANDBOX/mockbin/awk" <<'MOCK'
#!/bin/bash
printf 'awk %s\n' "$*" >> "$HOME/argv.log"
exec "$REAL_AWK" "$@"
MOCK
cat > "$SANDBOX/mockbin/chmod" <<'MOCK'
#!/bin/bash
arguments=()
for argument in "$@"; do
    [ "$argument" = -- ] || arguments+=("$argument")
done
exec "$REAL_CHMOD" "${arguments[@]}"
MOCK
chmod 700 "$SANDBOX/mockbin/"*
export PATH="$SANDBOX/mockbin:$PATH"
export MOWNT_TEST_PATH="$PATH"
grep -Fxq 'PATH=/usr/local/bin:/usr/bin:/bin' "$ROOT/libexec/mownt-relay" || fail 'helper PATH contract changed'
sed 's|^PATH=/usr/local/bin:/usr/bin:/bin$|PATH="$MOWNT_TEST_PATH"|' "$ROOT/libexec/mownt-relay" > "$SANDBOX/mownt-relay"
run() {
    expected=$1
    shift
    actual=0
    /bin/bash "$SANDBOX/mownt-relay" "$@" > "$OUTPUT" 2>&1 || actual=$?
    [ "$actual" = "$expected" ] || fail "expected exit $expected, got $actual for $*"
}
write_binary() {
    cat > "$HOME/.local/bin/rclone" <<'MOCK'
#!/bin/bash
printf 'rclone %s\n' "$*" >> "$HOME/rclone.log"
exit 0
MOCK
    chmod 700 "$HOME/.local/bin/rclone"
}
write_config() {
    cat > "$CONFIG" <<'CONFIG'
[unrelated]
type = local

[perception]
type = smb
host = files.example
user = test-user
pass = old-test-obscured

[another]
type = local
CONFIG
    chmod 600 "$CONFIG"
}
write_config
cp "$CONFIG" "$SANDBOX/original-config"
run 1 setup perception share '~/mnt/share'
[ -s "$HOME/download.log" ] || fail 'setup did not reach the download verification path'
[ ! -e "$HOME/unzip.log" ] || fail 'archive was unpacked before checksum verification'
[ ! -e "$HOME/.local/bin/rclone" ] || fail 'checksum mismatch installed an executable'
cmp -s "$CONFIG" "$SANDBOX/original-config" || fail 'checksum failure changed credentials'
pass 'a real checksum mismatch prevents unpacking, installation, and credential changes'

write_binary
DOWNLOADS=$(wc -l < "$HOME/download.log")
run 0 setup perception share '~/mnt/share'
[ "$(wc -l < "$HOME/download.log")" = "$DOWNLOADS" ] || fail 'setup downloaded despite a trusted installed binary'
pass 'setup reuses an existing private executable'
rm "$HOME/.local/bin/rclone"
export MOCK_ARCH=unsupported
run 1 setup perception share '~/mnt/share'
[ "$(wc -l < "$HOME/download.log")" = "$DOWNLOADS" ] || fail 'unsupported architecture reached the downloader'
export MOCK_ARCH=x86_64
write_binary
pass 'unsupported architecture fails before downloading'
mkdir "$HOME/.config/rclone/.mownt-lock"
run 1 sync perception share '~/mnt/share' < /dev/null
cmp -s "$CONFIG" "$SANDBOX/original-config" || fail 'lock contention changed the config'
rmdir "$HOME/.config/rclone/.mownt-lock"
pass 'credential lock contention preserves the existing file'

cat > "$SANDBOX/block" <<'CONFIG'
[perception]
type = smb
host = files.example
user = replacement-user
pass = replacement-test-obscured
CONFIG
run 0 sync perception share '~/mnt/share' < "$SANDBOX/block"
grep -Fxq changed "$OUTPUT" || fail 'sync did not report a changed credential block'
grep -Fq 'user = replacement-user' "$CONFIG" || fail 'selected credential block was not updated'
grep -Fq 'pass = replacement-test-obscured' "$CONFIG" || fail 'new credential was not persisted'
grep -Fq '[unrelated]' "$CONFIG" || fail 'unrelated section was removed'
grep -Fq '[another]' "$CONFIG" || fail 'following section was removed'
[ "$(grep -Fc '[perception]' "$CONFIG")" -eq 1 ] || fail 'remote section was duplicated'
if [ "$REAL_SYSTEM" = Darwin ]; then
    [ "$("$REAL_STAT" -f %Lp "$CONFIG")" = 600 ] || fail 'credential file is not private'
else
    [ "$("$REAL_STAT" -c %a "$CONFIG")" = 600 ] || fail 'credential file is not private'
fi
[ ! -d "$HOME/.config/rclone/.mownt-lock" ] || fail 'successful sync left its lock'
if grep -Eq 'replacement-user|replacement-test-obscured' "$OUTPUT" "$HOME/rclone.log" "$HOME/argv.log" 2>/dev/null; then fail 'credentials leaked into output or command arguments'; fi
pass 'stdin credentials update only the selected section with private permissions'

if [ "$REAL_SYSTEM" = Darwin ]; then CONFIG_INODE=$("$REAL_STAT" -f %i "$CONFIG"); else CONFIG_INODE=$("$REAL_STAT" -c %i "$CONFIG"); fi
run 0 sync perception share '~/mnt/share' < "$SANDBOX/block"
grep -Fxq unchanged "$OUTPUT" || fail 'unchanged selected credentials were not recognized'
if [ "$REAL_SYSTEM" = Darwin ]; then
    [ "$("$REAL_STAT" -f %i "$CONFIG")" = "$CONFIG_INODE" ] || fail 'unchanged sync replaced the existing file'
else
    [ "$("$REAL_STAT" -c %i "$CONFIG")" = "$CONFIG_INODE" ] || fail 'unchanged sync replaced the existing file'
fi
pass 'unchanged selected credentials do not rewrite the config or request a reload'

cp "$CONFIG" "$SANDBOX/updated-config"
sed 's/replacement-user/replacement-second/' "$SANDBOX/block" > "$SANDBOX/second-block"
export MOCK_FAIL_MV=1
run 1 sync perception share '~/mnt/share' < "$SANDBOX/second-block"
export MOCK_FAIL_MV=0
cmp -s "$CONFIG" "$SANDBOX/updated-config" || fail 'failed atomic replace damaged the config'
[ ! -d "$HOME/.config/rclone/.mownt-lock" ] || fail 'failed sync left its lock'
pass 'failed atomic replacement preserves credentials and releases the lock'

printf '[perception]\ntype = smb\nhost = files.example\n[unrelated]\ntype = local\n' > "$SANDBOX/bad-block"
run 1 sync perception share '~/mnt/share' < "$SANDBOX/bad-block"
cmp -s "$CONFIG" "$SANDBOX/updated-config" || fail 'multiple-section input changed credentials'
pass 'sync refuses a second remote section without changing existing data'

printf '[perception]\ntype = smb\nhost = files.example\nunsafe_command = execute\n' > "$SANDBOX/bad-block"
run 1 sync perception share '~/mnt/share' < "$SANDBOX/bad-block"
cmp -s "$CONFIG" "$SANDBOX/updated-config" || fail 'unknown credential setting changed config'
pass 'sync refuses unknown credential keys'

printf '[perception]\ntype = smb\nhost = files.example\nuser = test\000name\n' > "$SANDBOX/bad-block"
run 1 sync perception share '~/mnt/share' < "$SANDBOX/bad-block"
cmp -s "$CONFIG" "$SANDBOX/updated-config" || fail 'NUL input changed credentials'
pass 'sync rejects NUL bytes before merging'

awk 'BEGIN {printf "[perception]\ntype = smb\nhost = files.example\npass = "; for (i=0;i<65537;i++) printf "a"; printf "\n"}' > "$SANDBOX/bad-block"
run 1 sync perception share '~/mnt/share' < "$SANDBOX/bad-block"
cmp -s "$CONFIG" "$SANDBOX/updated-config" || fail 'oversized input changed credentials'
pass 'sync bounds credential input size'

mv "$CONFIG" "$SANDBOX/symlink-target"
ln -s "$SANDBOX/symlink-target" "$CONFIG"
run 1 sync perception share '~/mnt/share' < "$SANDBOX/block"
cmp -s "$SANDBOX/symlink-target" "$SANDBOX/updated-config" || fail 'sync followed a credential symlink'
rm "$CONFIG"
mv "$SANDBOX/symlink-target" "$CONFIG"
pass 'sync refuses credential symlinks'

chmod 644 "$CONFIG"
run 1 sync perception share '~/mnt/share' < "$SANDBOX/block"
chmod 600 "$CONFIG"
pass 'sync refuses readable credential files'

for remote_path in '~/../escape' 'mnt/../escape' 'mnt/$(touch-pwned)' 'mnt/share;execute'; do
    run 1 check perception share "$remote_path"
done
pass 'helper rejects unsafe paths before provisioning or mounting'

# Exercise the shipped NUL-aware process scanner with a synthetic proc tree.
# Only the proc directory is replaced; the actual function body runs unchanged.
export MOCK_PROC="$SANDBOX/proc"
mkdir -p "$MOCK_PROC/12345"
cat > "$SANDBOX/cache-check" <<'HEADER'
#!/bin/bash
UID_NOW=$(id -u)
CACHE="$HOME/.cache/mownt/rclone"
HEADER
awk '
    /^cache_user_active\(\) \{/ {active=1}
    active {
        if ($0=="    for process in /proc/[0-9]*; do") print "    for process in \"$MOCK_PROC\"/[0-9]*; do"
        else print
        if ($0=="}") exit
    }
' "$ROOT/libexec/mownt-relay" >> "$SANDBOX/cache-check"
cat >> "$SANDBOX/cache-check" <<'FOOTER'
cache_user_active "${MOCK_DEADLINE:-$((SECONDS + 12))}"
exit $?
FOOTER
grep -Fq 'for process in "$MOCK_PROC"/' "$SANDBOX/cache-check" || fail 'process scanner fixture contract changed'
scan() {
    expected=$1
    actual=0
    /bin/bash "$SANDBOX/cache-check" > "$OUTPUT" 2>&1 || actual=$?
    [ "$actual" = "$expected" ] || fail "cache scanner expected $expected, got $actual"
}
CACHE="$HOME/.cache/mownt/rclone"
printf '/alternate/wrapper\000--cache-dir\000%s\000--extra\000' "$CACHE" > "$MOCK_PROC/12345/cmdline"
scan 0
printf '/alternate/wrapper\000--extra\000--cache-dir=%s\000' "$CACHE" > "$MOCK_PROC/12345/cmdline"
scan 0
pass 'cache reuse detects exact separate and equals arguments even for alternate executables'
printf '/alternate/wrapper\000--cache-dir\000%s-other\000' "$CACHE" > "$MOCK_PROC/12345/cmdline"
scan 1
printf '/bin/bash\000-c\000--cache-dir %s\000' "$CACHE" > "$MOCK_PROC/12345/cmdline"
scan 1
pass 'cache reuse ignores different paths and flag text embedded inside another argument'
chmod 000 "$MOCK_PROC/12345/cmdline"
scan 2
chmod 600 "$MOCK_PROC/12345/cmdline"
pass 'cache reuse fails closed when a current-account process cannot be inspected'
export MOCK_DEADLINE=0
scan 3
unset MOCK_DEADLINE
pass 'cache process inspection enforces its overall deadline'

printf 'All %s executable relay-helper checks passed.\n' "$COUNT"
