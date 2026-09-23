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
  if [ -n "${STUB_SIGNED_IN:-}" ]; then echo '{"loggedIn": true, "authMethod": "claude.ai"}'; else echo '{"loggedIn": false}'; fi; exit 0
fi
cat > "$STUB_DIR/prompt.txt"; echo "${CLAUDECODE:-unset}" > "$STUB_DIR/cc.txt"; echo call >> "$STUB_DIR/calls"
printf '# Security review\n\n# Vuln 1: SQLi: `app.js:3`\n* Severity: HIGH\n\n%s\n' "$STUB_VERDICT"
SH
chmod +x "$STUB/claude"
export PATH="$ROOT/bin:$PATH" STUB_DIR="$STUB" XDG_CACHE_HOME="$T/cache" SEC_REVIEW_CLAUDE="$STUB/claude" CLAUDECODE=1
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
