#!/usr/bin/env bash
# sec-review behaviour tests with a stub `claude` (no network, no account needed).
# Sourced by tests/run.sh (uses its ok/bad helpers) or run directly.
set -uo pipefail
ROOT="${ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
type ok >/dev/null 2>&1 || { P=0; F=0; ok() { P=$((P+1)); echo "  ✓ $*"; }; bad() { F=$((F+1)); echo "  ✗ $*"; }; STANDALONE=1; }
SR="$ROOT/bin/sec-review"
T="$(mktemp -d "${TMPDIR:-/tmp}/sec-review-test.XXXXXX")"
STUB="$T/stub"; mkdir -p "$STUB"
cat > "$STUB/claude" <<'SH'
#!/bin/sh
if [ "$1" = auth ]; then
  if [ -n "${STUB_SIGNED_IN:-}" ] || [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then echo '{"loggedIn": true, "authMethod": "claude.ai"}'; else echo '{"loggedIn": false}'; fi; exit 0
fi
cat > "$STUB_DIR/prompt.txt"; echo "${CLAUDECODE:-unset}" > "$STUB_DIR/cc.txt"; echo call >> "$STUB_DIR/calls"; echo "${CLAUDE_CODE_OAUTH_TOKEN:-login}" > "$STUB_DIR/cred.txt"
printf '# Security review\n\n# Vuln 1: SQLi: `app.js:3`\n* Severity: HIGH\n\n%s\n' "$STUB_VERDICT"
SH
chmod +x "$STUB/claude"
export PATH="$ROOT/bin:$PATH" STUB_DIR="$STUB" XDG_CACHE_HOME="$T/cache" SEC_REVIEW_CLAUDE="$STUB/claude" CLAUDECODE=1 SEC_REVIEW_TOKEN_FILE="$T/token/oauth-token"
calls() { [ -f "$STUB/calls" ] && wc -l < "$STUB/calls" | tr -d ' ' || echo 0; }

git init -q --bare "$T/remote.git"
git init -q "$T/repo" && cd "$T/repo"
git config user.email t@example.com; git config user.name t; git config commit.gpgsign false
echo 'const a = 1;' > app.js; git add app.js; git commit -qm base
git remote add origin "$T/remote.git"; git push -q origin HEAD:refs/heads/main 2>/dev/null
git branch -q --set-upstream-to=origin/main 2>/dev/null
echo 'db.query("select * from t where id=" + req.query.id);' >> app.js; git commit -qam "add query"
echo 'UNCOMMITTED_MARKER' > wip.txt

out="$(STUB_VERDICT='SECURITY-REVIEW: PASS' "$SR" 2>&1)"; rc=$?
[ $rc = 0 ] && grep -q "signed in here" <<<"$out" && [ "$(calls)" = 0 ] && ok "signed out → skipped visibly, push allowed" || bad "signed-out skip ($rc): $out"

export STUB_SIGNED_IN=1
out="$(STUB_VERDICT='SECURITY-REVIEW: PASS' "$SR" 2>&1)"; rc=$?
[ $rc = 0 ] && grep -q "passed" <<<"$out" && [ "$(calls)" = 1 ] && ok "PASS verdict → allowed" || bad "pass ($rc): $out"
grep -q 'req.query.id' "$STUB/prompt.txt" && ! grep -q UNCOMMITTED_MARKER "$STUB/prompt.txt" && ok "reviews the unpushed commits only (never uncommitted work)" || bad "prompt range wrong"
grep -q '^OBJECTIVE:' "$STUB/prompt.txt" && grep -q 'SECURITY-REVIEW: PASS' "$STUB/prompt.txt" && ok "prompt = official instructions + verdict line" || bad "prompt missing OBJECTIVE/verdict"
[ "$(cat "$STUB/cc.txt")" = unset ] && ok "CLAUDECODE unset for the reviewer (works inside a Claude Code session)" || bad "CLAUDECODE leaked"
out="$(STUB_VERDICT='SECURITY-REVIEW: PASS' "$SR" 2>&1)"
[ "$(calls)" = 1 ] && grep -q "already passed" <<<"$out" && ok "same diff → cached, no second review" || bad "cache miss: $out"

# review token: its own one-year `claude setup-token` token, so the reviewer never renews the Claude Code login
echo '// token 1' >> app.js; git commit -qam tok1
out="$(STUB_VERDICT='SECURITY-REVIEW: PASS' "$SR" 2>&1)"
[ "$(cat "$STUB/cred.txt")" = login ] && ok "no token file → reviews on the Claude Code login (unchanged)" || bad "used a token without a file"
out="$(printf 'not-a-token\n' | "$SR" --save-token 2>&1)"; rc=$?
[ $rc != 0 ] && [ ! -e "$T/token/oauth-token" ] && ok "--save-token refuses something that isn't a setup-token" || bad "saved a bad token ($rc): $out"
out="$(printf 'sk-ant-oat01-TESTTOKEN_abc-123\n' | "$SR" --save-token 2>&1)"; rc=$?
[ $rc = 0 ] && [ "$(stat -f %Lp "$T/token/oauth-token" 2>/dev/null || stat -c %a "$T/token/oauth-token")" = 600 ] && ! grep -q TESTTOKEN <<<"$out" && ok "--save-token stores it mode 600 and never prints it" || bad "save-token ($rc): $out"
unset STUB_SIGNED_IN
echo '// token 2' >> app.js; git commit -qam tok2
out="$(STUB_VERDICT='SECURITY-REVIEW: PASS' "$SR" 2>&1)"; rc=$?
[ $rc = 0 ] && [ "$(cat "$STUB/cred.txt")" = sk-ant-oat01-TESTTOKEN_abc-123 ] && ok "token file → the review runs on the token (signed out of the login is fine)" || bad "token not used ($rc): $out"
out="$("$SR" --status 2>&1)"; grep -q "review token" <<<"$out" && ok "--status names the review token" || bad "--status silent about the token"
touch -t "$(date -d '-340 days' +%Y%m%d%H%M 2>/dev/null || date -v-340d +%Y%m%d%H%M)" "$T/token/oauth-token"
echo '// token 3' >> app.js; git commit -qam tok3
out="$(STUB_VERDICT='SECURITY-REVIEW: PASS' "$SR" 2>&1)"
grep -q "expires in" <<<"$out" && [ "$(cat "$STUB/cred.txt")" != login ] && ok "token near a year old → still used, with a renew warning" || bad "no renew warning: $out"
touch -t "$(date -d '-366 days' +%Y%m%d%H%M 2>/dev/null || date -v-366d +%Y%m%d%H%M)" "$T/token/oauth-token"
export STUB_SIGNED_IN=1
echo '// token 4' >> app.js; git commit -qam tok4
out="$(STUB_VERDICT='SECURITY-REVIEW: PASS' "$SR" 2>&1)"
grep -q "expired" <<<"$out" && [ "$(cat "$STUB/cred.txt")" = login ] && ok "expired token → falls back to the login, visibly" || bad "expired token handling: $out"
CLAUDE_CODE_OAUTH_TOKEN=from-env "$SR" --status >/dev/null 2>&1
echo '// token 5' >> app.js; git commit -qam tok5
out="$(CLAUDE_CODE_OAUTH_TOKEN=from-env STUB_VERDICT='SECURITY-REVIEW: PASS' "$SR" 2>&1)"
[ "$(cat "$STUB/cred.txt")" = from-env ] && ok "a CLAUDE_CODE_OAUTH_TOKEN already set wins over the file" || bad "env token overridden"
rm -rf "$T/token"

"$SR" --install-hook 2>/dev/null
[ -x .git/hooks/pre-push ] && grep -q 'security-kit: sec-review' .git/hooks/pre-push && ok "--install-hook writes the pre-push hook" || bad "hook not installed"
echo 'eval(req.body.code);' >> app.js; git commit -qam "add eval"
out="$(STUB_VERDICT='SECURITY-REVIEW: BLOCK 1' git push origin HEAD:refs/heads/main 2>&1)"; rc=$?
[ $rc != 0 ] && grep -q "push blocked" <<<"$out" && [ "$(git rev-parse origin/main)" != "$(git rev-parse HEAD)" ] && ok "real git push with a HIGH finding → blocked" || bad "block ($rc): $out"
out="$(SEC_REVIEW=off git push -q origin HEAD:refs/heads/main 2>&1)"; rc=$?
[ $rc = 0 ] && [ "$(git ls-remote "$T/remote.git" refs/heads/main | cut -f1)" = "$(git rev-parse HEAD)" ] && ok "SEC_REVIEW=off git push → pushed" || bad "override ($rc): $out"
echo '// safe' >> app.js; git commit -qam safe
out="$(STUB_VERDICT='**SECURITY-REVIEW: PASS**' git push origin HEAD:refs/heads/main 2>&1)"; rc=$?
[ $rc = 0 ] && grep -q "passed" <<<"$out" && ok "real git push with PASS (markdown-wrapped verdict) → pushed" || bad "pass push ($rc): $out"
echo '// odd' >> app.js; git commit -qam odd
out="$(STUB_VERDICT='no verdict here' git push origin HEAD:refs/heads/main 2>&1)"; rc=$?
[ $rc = 0 ] && grep -q "didn't finish" <<<"$out" && ok "reviewer without a verdict → skipped visibly, push allowed" || bad "no-verdict ($rc): $out"

git init -q "$T/repo2" && cd "$T/repo2" && printf '#!/bin/sh\necho mine\n' > .git/hooks/pre-push && chmod +x .git/hooks/pre-push
"$SR" --install-hook 2>/dev/null; grep -q 'echo mine' .git/hooks/pre-push && ! grep -q sec-review .git/hooks/pre-push && ok "foreign pre-push hook never clobbered" || bad "clobbered a foreign hook"

cd / && rm -rf "$T"
if [ "${STANDALONE:-0}" = 1 ]; then echo "── $P passed · $F failed"; [ "$F" = 0 ]; fi
