#!/bin/sh
# Tests for infisical-entrypoint.sh. A stub `infisical` binary on PATH keeps this
# fully offline: login/run succeed, `secrets` emits a mix of valid and malformed
# KEY=VALUE lines.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENTRYPOINT="$SCRIPT_DIR/infisical-entrypoint.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$TMP/bin" "$TMP/work"

# Secret lines served by the stub: one valid, one whose NAME is shell code,
# one already-set key, one line with no '=', one invalid key name.
cat > "$TMP/secrets.txt" <<EOF
FRESH_SECRET=from-infisical
EVIL\$(touch $TMP/pwned)=injected
PRESET_SECRET=infisical-value
HEADERLINE
BAD KEY=x
EOF

cat > "$TMP/bin/infisical" <<STUB
#!/bin/sh
case "\$1" in
  secrets) cat "$TMP/secrets.txt" ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$TMP/bin/infisical"

cd "$TMP/work"

# --- Test 1: TILT_* values are data, never glob-expanded --------------------
# '*' must be exported literally, not expanded to a listing of the workdir.
touch "$TMP/work/aaa" "$TMP/work/bbb"
TILT_DB_NAME='*' \
INFISICAL_ENABLED=false \
SERVICE_NAME=test-service \
sh "$ENTRYPOINT" env >"$TMP/env1.out" 2>"$TMP/err1.out" \
  || fail "entrypoint exited nonzero (INFISICAL_ENABLED=false path)"

grep -qxF 'DB_NAME=*' "$TMP/env1.out" || fail "TILT_DB_NAME glob was expanded to filenames"

# --- Test 2: malformed secret lines cannot abort or exploit the entrypoint --
PRESET_SECRET=original \
PATH="$TMP/bin:$PATH" \
INFISICAL_CLIENT_ID=test-id \
INFISICAL_CLIENT_SECRET=test-secret \
INFISICAL_PROJECT_ID=test-project \
SERVICE_NAME=test-service \
sh "$ENTRYPOINT" env >"$TMP/env3.out" 2>"$TMP/err3.out" \
  || fail "entrypoint aborted on malformed secret lines"

[ ! -e "$TMP/pwned" ] || fail "secret key name was executed as shell code"
grep -qx 'FRESH_SECRET=from-infisical' "$TMP/env3.out" \
  || fail "valid secret was not exported"
grep -qx 'PRESET_SECRET=original' "$TMP/env3.out" \
  || fail "pre-existing environment value was overwritten"
! grep -q '^HEADERLINE=' "$TMP/env3.out" \
  || fail "line without '=' was exported as HEADERLINE=HEADERLINE"
grep -q 'Skipping malformed secret key' "$TMP/env3.out" \
  || fail "malformed key was not logged"

echo "all infisical-entrypoint tests passed"
