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
# The one list of kit skills (install/lib.sh). Read, not sourced: lib.sh redefines ok().
KIT_SKILLS="$(sed -n 's/^KIT_SKILLS="\(.*\)"$/\1/p' install/lib.sh)"
nk=$(echo $KIT_SKILLS | wc -w | tr -d ' ')

echo "── bash syntax ──"
for f in install/*.sh bin/* tests/run.sh; do
    if bash -n "$f" 2>/tmp/sherr; then ok "$f"; else bad "$f: $(cat /tmp/sherr)"; fi
done
# bash 3.2 in a UTF-8 locale treats high bytes as name chars: a $var glued to a non-ASCII char is an unbound variable under set -u
utf_lint() {  # a function, not $(…): bash 3.2 misparses case patterns inside command substitution
    local f
    git ls-files | while read -r f; do
        case "$f" in *.sh) ;; *) head -1 "$f" 2>/dev/null | grep -q bash || continue ;; esac
        perl -ne 'print "$ARGV:$. " if /(?<!\\)\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]/' "$f"
    done
}
utf="$(cd "$(dirname "$0")/.." && utf_lint)"
[ -z "$utf" ] && ok "no \$var glued to a non-ASCII char (bash 3.2 + UTF-8 locale crash)" || bad "\$var followed by non-ASCII — write \${var}: $utf"

echo "── kit skills ──"
[ "$nk" -gt 0 ] && ok "$nk kit skills read from install/lib.sh" || bad "cannot read KIT_SKILLS from install/lib.sh"
for s in $KIT_SKILLS; do
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
for k in $KIT_SKILLS; do
    grep -v '^#' install/upstream-skills.tsv | cut -f1 | sed 's#.*/##' | grep -qx "$k" && collide="$collide $k"
done
[ -z "$collide" ] && ok "no upstream/kit skill name collision" || bad "collision with kit skill:$collide"
# the map skill must name the ownership router (one owner per job)
grep -q "one owner per job" skills/security-kit/SKILL.md && ok "ownership map present in security-kit" || bad "security-kit missing ownership map"
# every kit skill in lib.sh is tested here, checked BY NAME by sec-doctor, and listed in the map + README
grep -q 'KIT_SKILLS="$(sed' bin/sec-doctor && ok "sec-doctor reads KIT_SKILLS from install/lib.sh" || bad "sec-doctor does not read install/lib.sh KIT_SKILLS"
hard=""
for k in $KIT_SKILLS; do [ "$k" = security-kit ] && continue; grep -qE "[|(]$k[|)]" bin/sec-doctor && hard="$hard $k"; done
! grep -qE '\-eq [0-9]+ \]' bin/sec-doctor && [ -z "$hard" ] && ok "sec-doctor has no hard-coded skill list or count" || bad "sec-doctor hard-codes skills or a count:$hard"
# run sec-doctor against a fake HOME: all linked → n/n by name; one missing → named in the output
dhome="$(mktemp -d)"
mkdir -p "$dhome/.claude/skills" "$dhome/.hermes/skills/security"
for k in $KIT_SKILLS; do ln -s "$KIT_ROOT/skills/$k" "$dhome/.claude/skills/$k"; ln -s "$KIT_ROOT/skills/$k" "$dhome/.hermes/skills/security/$k"; done
dout="$(cd "$dhome" && HOME="$dhome" PATH=/usr/bin:/bin bash "$KIT_ROOT/bin/sec-doctor" 2>&1)"
[ "$(printf '%s\n' "$dout" | grep -c "$nk/$nk kit skills linked ✓")" -eq 2 ] && ok "sec-doctor: $nk/$nk kit skills linked on both hosts" || bad "sec-doctor did not report $nk/$nk on both hosts"
last="${KIT_SKILLS##* }"; rm "$dhome/.hermes/skills/security/$last"
dout="$(cd "$dhome" && HOME="$dhome" PATH=/usr/bin:/bin bash "$KIT_ROOT/bin/sec-doctor" 2>&1)"
printf '%s\n' "$dout" | grep -q "$((nk-1))/$nk kit skills linked, missing: $last" && ok "sec-doctor names a missing kit skill ($last)" || bad "sec-doctor did not name the missing kit skill $last"
rm -rf "$dhome"
missing=""
for k in $KIT_SKILLS; do
    [ "$k" = security-kit ] && continue
    grep -q "| $k |" skills/security-kit/SKILL.md && grep -q "\*\*$k\*\*" README.md || missing="$missing $k"
done
[ -z "$missing" ] && ok "every kit skill is in the map Components table and README" || bad "missing from the security-kit Components table or README:$missing"
grep -q "Nothing sensitive is ever public" skills/security-kit/SKILL.md && ok "rule: nothing sensitive is ever public" || bad "security-kit missing the data-exposure rule"
grep -q "Backups are private, encrypted and off-host" skills/security-kit/SKILL.md && ok "rule: backups are private, encrypted and off-host" || bad "security-kit missing the backups rule"
# one owner per job: leaked secrets and bundle secrets route to data-exposure
grep -q "hand off to \`data-exposure\`" skills/prod-debug/SKILL.md && ok "prod-debug hands secret leaks to data-exposure" || bad "prod-debug still owns secret leaks"
grep -q "data-exposure" skills/attack-surface/SKILL.md && ! grep -q "Secrets in client bundles (Vite" skills/attack-surface/SKILL.md && ok "attack-surface hands bundle secrets to data-exposure" || bad "attack-surface still owns bundle secrets"
# the always-on and per-repo loops include the exposure check and backups steps
for f in install/install.sh install/init-project.sh skills/security-kit/SKILL.md; do
    grep -q "data-exposure" "$f" && grep -qE "backups( \(|$| →)" "$f" && ok "$f loop has exposure check + backups" || bad "$f loop misses the exposure check or backups step"
done
# data-exposure's guard is an allowlist (fail closed), backups never prune off-site from production
grep -q "PUBLIC_WRITE_ALLOW" skills/data-exposure/SKILL.md && ok "data-exposure guard is an allowlist" || bad "data-exposure guard is not an allowlist"
grep -q "write-only credential" skills/backup-resilience/SKILL.md && grep -q "Full-disk encryption" skills/backup-resilience/SKILL.md && ok "backup-resilience: write-only off-site credential + full-disk encryption" || bad "backup-resilience missing write-only credential or disk encryption"
# no em dashes in the new skills or the sec-doctor kit-skill messages
dash="$(printf '\342\200\224')"   # U+2014, spelled as bytes so this file needs no literal one
emd="$(grep -l "$dash" skills/data-exposure/SKILL.md skills/backup-resilience/SKILL.md 2>/dev/null; grep -n 'kit skills linked' bin/sec-doctor | grep "$dash")"
[ -z "$emd" ] && ok "no em dashes in data-exposure, backup-resilience or sec-doctor skill checks" || bad "em dash left in: $emd"

echo "── templates & CLIs ──"
for f in templates/robots.txt templates/crawler-blocklist.txt templates/stealth-headers.md templates/github/security-kit-sync.yml bin/sec-doctor bin/sec-review bin/sec-update bin/sec-settings install/init-project.sh; do
    [ -f "$f" ] && ok "$f" || bad "$f missing"
done
grep -q "Disallow: /" templates/robots.txt && ok "robots.txt blocks all" || bad "robots.txt missing Disallow"
grep -q "GPTBot" templates/crawler-blocklist.txt && ok "crawler blocklist has AI crawlers" || bad "crawler blocklist missing GPTBot"
# no token anywhere: review runs locally (pre-push sec-review on the Claude Code sign-in)
[ ! -f templates/github/security-review.yml ] && ok "no PR-review workflow template (retired)" || bad "retired security-review.yml template still shipped"
! grep -rqE "gh secret set CLAUDE_CODE_OAUTH_TOKEN|claude setup-token|secrets\.CLAUDE_CODE_OAUTH_TOKEN" install bin templates README.md && ok "nothing asks for a CLAUDE_CODE_OAUTH_TOKEN" || bad "OAuth-token setup still referenced"
! grep -qE "CLAUDE_API_KEY|anthropic_api_key|if: \\$\\{\\{ *secrets\." templates/github/*.yml && ok "no API key and no secrets-in-if anywhere in the templates" || bad "API key or secrets-in-if left in templates"
! grep -qE "uses: [^@]+@v[0-9]" templates/github/*.yml && ok "every template action is hash-pinned" || bad "unpinned action in templates"
# one-command install: bootstrap must default to both hosts, no flag required
grep -q 'TARGET="${1:-both}"' install/bootstrap.sh && ok "bootstrap defaults to both hosts" || bad "bootstrap not defaulting to both"
grep -q 'removed (retired' install/init-project.sh && ok "sec-init removes a kit-seeded PR-review workflow" || bad "sec-init does not retire the PR-review workflow"
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