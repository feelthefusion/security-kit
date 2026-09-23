#!/usr/bin/env bash
# Security Kit — self-test.  bash tests/run.sh
# Proves: scripts are valid bash, every kit skill has a SKILL.md whose frontmatter name matches
# its dir, the upstream manifest parses, and required templates/CLIs exist.
set -uo pipefail
cd "$(dirname "$0")/.."
KIT_ROOT="$(pwd)"
pass=0; fail=0
ok()  { printf '  ✓ %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '  ✗ %s\n' "$*"; fail=$((fail+1)); }

echo "── bash syntax ──"
for f in install/*.sh bin/* tests/run.sh; do
    if bash -n "$f" 2>/tmp/sherr; then ok "$f"; else bad "$f: $(cat /tmp/sherr)"; fi
done

echo "── kit skills ──"
for s in security-kit red-team attack-surface exploit-verify harden-stack fuzz-harness prod-debug stealth-mode; do
    f="$KIT_ROOT/skills/$s/SKILL.md"
    [ -f "$f" ] || { bad "$s: SKILL.md missing"; continue; }
    nm=$(awk -F': ' '/^name:/{print $2; exit}' "$f" | tr -d '"' | tr -d "'")
    [ "$nm" = "$s" ] && ok "$s (name matches)" || bad "$s: frontmatter name '$nm' != dir '$s'"
done

echo "── upstream manifest ──"
total=0
while IFS=$'\t' read -r ident hosts trust _; do
    case "$ident" in ''|\#*) continue ;; esac
    echo "$hosts" | grep -qE '^(both|claude|hermes)$' || { bad "bad hosts '$hosts' on $ident"; continue; }
    echo "$ident" | grep -qE '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/.+/.+$' || bad "bad identifier: $ident"
    total=$((total+1))
done < install/upstream-skills.tsv
[ "$total" -gt 0 ] && ok "$total upstream rows parse (ident/hosts/trust)"

echo "── cohesion: no two skills compete ──"
# upstream skill names must be unique (one vulnerability class per skill)
dupes=$(grep -v '^#' install/upstream-skills.tsv | cut -f1 | sed 's#.*/##' | sort | uniq -d)
[ -z "$dupes" ] && ok "upstream skill names unique" || bad "duplicate upstream skills: $dupes"
# upstream names must not collide with kit skills (workflow layer vs technique layer)
collide=""
for k in security-kit red-team attack-surface exploit-verify harden-stack fuzz-harness prod-debug stealth-mode; do
    grep -v '^#' install/upstream-skills.tsv | cut -f1 | sed 's#.*/##' | grep -qx "$k" && collide="$collide $k"
done
[ -z "$collide" ] && ok "no upstream/kit skill name collision" || bad "collision with kit skill:$collide"
# the map skill must name the ownership router (one owner per job)
grep -q "one owner per job" skills/security-kit/SKILL.md && ok "ownership map present in security-kit" || bad "security-kit missing ownership map"

echo "── templates & CLIs ──"
for f in templates/robots.txt templates/crawler-blocklist.txt templates/stealth-headers.md templates/github/security-kit-sync.yml templates/github/security-review.yml bin/sec-doctor bin/sec-review bin/sec-update bin/sec-settings install/init-project.sh; do
    [ -f "$f" ] && ok "$f" || bad "$f missing"
done
grep -q "Disallow: /" templates/robots.txt && ok "robots.txt blocks all" || bad "robots.txt missing Disallow"
grep -q "GPTBot" templates/crawler-blocklist.txt && ok "crawler blocklist has AI crawlers" || bad "crawler blocklist missing GPTBot"
# PR review workflow: Claude plan (OAuth token, no API key), secret-gated via a gate job
# (`secrets` isn't allowed in a job-level if), actions pinned to a commit (zizmor)
grep -q "anthropics/claude-code-action@[0-9a-f]\{40\}" templates/github/security-review.yml && ok "security-review.yml: official claude-code-action, hash-pinned" || bad "security-review.yml action not hash-pinned"
grep -q "claude_code_oauth_token: \${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}" templates/github/security-review.yml && ok "security-review.yml runs on the Claude plan (OAuth token)" || bad "security-review.yml not on the OAuth token"
grep -q "needs.gate.outputs.enabled == 'true'" templates/github/security-review.yml && ok "security-review.yml secret-gated via gate job" || bad "security-review.yml not gated"
! grep -qE "CLAUDE_API_KEY|anthropic_api_key|if: \\$\\{\\{ *secrets\." templates/github/*.yml && ok "no API key and no secrets-in-if anywhere in the templates" || bad "API key or secrets-in-if left in templates"
! grep -qE "uses: [^@]+@v[0-9]" templates/github/*.yml && ok "every template action is hash-pinned" || bad "unpinned action in templates"
# one-command install: bootstrap must default to both hosts, no flag required
grep -q 'TARGET="${1:-both}"' install/bootstrap.sh && ok "bootstrap defaults to both hosts" || bad "bootstrap not defaulting to both"
grep -q "gh secret set CLAUDE_CODE_OAUTH_TOKEN" install/init-project.sh && ok "sec-init auto-sets CLAUDE_CODE_OAUTH_TOKEN from env" || bad "sec-init missing auto-secret-set"
grep -q 'sec-review" --install-hook' install/init-project.sh && ok "sec-init installs the pre-push review hook" || bad "sec-init missing the pre-push hook"

echo "── sec-review (automatic push review, stub claude) ──"
while IFS= read -r line; do
    case "$line" in *"  ✓ "*) ok "${line#*✓ }" ;; *"  ✗ "*) bad "${line#*✗ }" ;; esac
done < <(ROOT="$KIT_ROOT" bash "$KIT_ROOT/tests/sec-review.sh" 2>&1)

echo "── stealth toggle (dry) ──"
tmp="$(mktemp -d)"
cd "$tmp" && git init -q .
KIT_ROOT="$KIT_ROOT" bash "$KIT_ROOT/bin/sec-settings" stealth on >/dev/null 2>&1 || bad "stealth on non-zero exit"
[ -f "$tmp/public/robots.txt" ] && ok "stealth on → public/robots.txt" || bad "public/robots.txt missing"
KIT_ROOT="$KIT_ROOT" bash "$KIT_ROOT/bin/sec-settings" stealth off >/dev/null 2>&1 || bad "stealth off non-zero exit"
[ ! -f "$tmp/public/robots.txt" ] && ok "stealth off → robots.txt removed" || bad "robots.txt still present"
rm -rf "$tmp"

echo ""
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "✓ all green" || { echo "✗ $fail failure(s)"; exit 1; }