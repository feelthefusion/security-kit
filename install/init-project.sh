#!/usr/bin/env bash
# =============================================================================
# Security Kit — per-repo init.   cd <app repo> && sec-init      (idempotent; re-run anytime)
#
#   .agents/security-context.md    threat model, attack surface, auth stack, key checklist —
#                                  auto-drafted from the repo (Drizzle/Prisma tables, routes,
#                                  deps, Railway link); edit it
#   .agents/security-kit.env       per-repo env (gitignored)
#   sec/                           threats/, attacks/, regressions/ — the security workbench
#   sec/stealth/                   stealth config (sec-settings stealth on)
#   AGENTS.md / CLAUDE.md          marked Security Kit block
#   verify.sh                      marked `security review` step IF the Skill Starter Kit gate exists
#   .github/workflows/             webhook receiver for kit pushes → auto-re-sync
# =============================================================================
set -euo pipefail
SELF="${BASH_SOURCE[0]}"; while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
KIT_ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO"
echo "── sec-init · $REPO"
mkdir -p .agents sec/threats sec/attacks sec/regressions sec/stealth

# --- security-context.md (only drafted once; yours afterwards) -----------------
if [ ! -f .agents/security-context.md ]; then
    python3 - "$REPO" > .agents/security-context.md <<'PY'
import json, os, re, subprocess, sys
root = sys.argv[1]
pkg = {}
try: pkg = json.load(open(os.path.join(root, "package.json")))
except Exception: pass
deps = {**pkg.get("dependencies", {}), **pkg.get("devDependencies", {})}
has = lambda *names: [n for n in names if n in deps]
# Find routes
routes = []
for dp, dn, fn in os.walk(root):
    dn[:] = [d for d in dn if d not in ("node_modules", ".git", "dist", "build", ".next", ".claude", "worktrees", "migrations", "sec")]
    for f in fn:
        if f.endswith((".ts", ".js")):
            try: txt = open(os.path.join(dp, f), encoding="utf-8", errors="ignore").read()
            except Exception: continue
            for m in re.finditer(r'(?:router\.(?:get|post|put|patch|delete)|app\.(?:get|post|put|patch|delete))\s*\(\s*["\']([^\s"\'()]+)["\']', txt):
                routes.append((m.group(1), os.path.relpath(os.path.join(dp, f), root)))
            for m in re.finditer(r'export\s+(?:async\s+)?function\s+(?:GET|POST|PUT|PATCH|DELETE)', txt):
                routes.append(("→ /api (App Router)", os.path.relpath(os.path.join(dp, f), root)))
# Webhook / callback routes
webhooks = [r for r in routes if any(w in r[0] for w in ("webhook","callback","hook","event"))]
# Railway
railway = ""
try:
    out = subprocess.run(["railway", "status"], cwd=root, capture_output=True, text=True, timeout=15)
    if out.returncode == 0: railway = " ".join(out.stdout.split())[:200]
except Exception: pass
# Auth stack
auth_deps = has("next-auth","@auth/core","better-auth","lucia","clerk","@clerk/nextjs","kinde","@kinde-oss/kinde-auth-nextjs")
# Email / SMS / push (marketing-kit attack surface)
email = has("resend","nodemailer","postmark","@sendgrid/mail","mailgun.js")
sms = has("telnyx","twilio")
push = has("expo-server-sdk","web-push","firebase-admin")
has_ai = has("openai","@anthropic-ai/sdk","@google/generative-ai")
ws = has("ws","socket.io","pusher","@pusher/pusher")
files = has("multer","@uploadthing","busboy","formidable")
# GraphQL
gql_dep = has("@apollo/server","graphql-yoga","mercurius","@nestjs/graphql","type-graphql","gql")
routes_str = "\n".join(f"- `{r[0]}` — {r[1]}" for r in routes[:40]) or "- none detected (static / none found)"
webhooks_str = "\n".join(f"- `{r[0]}` — {r[1]}" for r in webhooks) or "- none detected"
mob = ""
mdirs = ["mobile", "apps", "app", "mobile-app", "native"]
for dp, dn, fn in os.walk(root):
    dn[:] = [d for d in dn if d not in ("node_modules", ".git", "dist", "build", ".next", ".claude", "worktrees")]
    if "app.json" in fn and any(m in dp.lower() for m in mdirs):
        try: ex = json.load(open(os.path.join(dp, "app.json"))).get("expo", {})
        except Exception: ex = {}
        if ex:
            ios = ex.get("ios", {}); andr = ex.get("android", {})
            mob += f"- `{os.path.relpath(dp, root)}` — {ex.get('name','?')} · iOS `{ios.get('bundleIdentifier','?')}` · Android `{andr.get('package','?')}`\n"
mob = mob or "- none detected"
print(f"""# Security context — {os.path.basename(root)}
<!-- Drafted by sec-init from the repo. Every Security Kit skill reads this; keep it TRUE and short.
     Edit freely — sec-init never overwrites it. -->

## Surface — what is reachable from outside
- Host: ? (domain, CDN, Railway URL)
- Routes found ({len(routes)}):
{routes_str}
- Webhook / callback routes (prime targets — signature verification, idempotency, replay):
{webhooks_str}
- GraphQL: {"YES — " + ", ".join(gql_dep) if gql_dep else "none"}
- WebSocket / real-time: {", ".join(ws) if ws else "none"}
- File uploads: {"YES — " + ", ".join(files) if files else "none"}
- AI / LLM endpoints: {"YES — " + ", ".join(has_ai) if has_ai else "none"}

## Auth — how trust is established
- Stack: {", ".join(auth_deps) if auth_deps else "? (none detected)"}
- Session: ? (cookie, JWT, hybrid)
- API auth: ? (bearer token, API key, session cookie)
- MFA: ? (TOTP, passkey, SMS — if present, what guards account recovery against it?)

## Data — what flows where
- DB: Postgres{" on Railway (" + railway + ")" if railway else ""}; ORM: {", ".join(has("drizzle-orm","@prisma/client","prisma","knex","kysely","typeorm")) or "?"}
- Key tables: ? (confirm: users/contacts, orders/payments, outbox, campaigns)
- Secrets / env: ? (where? .env / Railway / vault — what a RCE or SSR leak could grab)

## Channels (Marketing Kit attack surface — red-team AND verify these)
- Email: {", ".join(email) if email else "none"} · webhook route: ? · signature verification: ?
- SMS: {", ".join(sms) if sms else "none"} · webhook route: ? · signature verification: ?
- Push: {", ".join(push) if push else "none"} · FCM/APNs key rotation: ?

## Mobile
- Apps: {mob}- Mobile secrets: ? (what's in the binary — API keys, tokens, feature flags)
- App links / deep links: ? (verified by domain, or hijackable?)

## Auth checklist (fill with Y/N — yellow = not yet)
- [ ] Every route has auth check (no bypassable /api/admin via HTTP method)
- [ ] Object ownership checked on read, not just write (IDOR)
- [ ] Webhooks: signature verified BEFORE payload touches any handler
- [ ] Webhooks: idempotency (nonce/timestamp bound) — no replay
- [ ] Payments: idempotency + state machine locked to valid transitions
- [ ] Query params / body: parameterized (no raw string concatenation into SQL)
- [ ] User input never reaches eval/exec/child_process unsanitised
- [ ] File uploads: type validated server-side, stored outside the web root
- [ ] Error responses: no stack trace, no secret, no internal path
- [ ] API keys / tokens: rotated on leak, scoped per environment
- [ ] No secret in client bundle (mobile app, JS bundle, SSR leak)
- [ ] Rate limits on every auth and webhook route
- [ ] CSP + CORS explicitly set (not wildcard with credentials)
- [ ] Logs: every auth attempt, webhook arrival, payment state change, secret access
""")
PY
    echo "  · .agents/security-context.md drafted — fill the ? lines and Y/Ns ✓"
else
    echo "  · .agents/security-context.md exists (kept) ✓"
fi

[ -f .agents/security-kit.env ] || { printf '# Security Kit per-repo env — gitignored\n' > .agents/security-kit.env; echo "  · .agents/security-kit.env created ✓"; }
chmod 600 .agents/security-kit.env

# --- .gitignore -------------------------------------------------------------------------
touch .gitignore
grep -qxF '.agents/security-kit.env' .gitignore || { printf '\n# Security Kit (per-repo env)\n.agents/security-kit.env\n' >> .gitignore; echo "  · .gitignore += .agents/security-kit.env ✓"; }

# --- agent instructions block --------------------------------------------------------
BLOCK="$(mktemp)"
cat > "$BLOCK" <<'MD'
## Security Kit
- Security context: `.agents/security-context.md` (threat model, routes, auth, channels, checklist). Read it before any security, testing or debugging task.
- Loop: skill `security-kit` → orient → recon (`attack-surface`) → attack (`red-team`) → prove (`exploit-verify`) → fix (`harden-stack`) → verify (Skill Starter Kit `verify.sh`) → stealth (`sec-settings stealth on` when needed).
- Zero trust: every user input is malicious, every dependency is compromised. Source-to-sink before you trust code; race condition and business-logic order before you trust a flow.
- Every finding is proved with a PoC + regression test — never a claim without a repro. Findings go in `sec/attacks/<id>/`; regressions go in `sec/regressions/`.
- Freedom first: no legal/compliance gating, no T&Cs or policies. Legal sections inside vendor/upstream skills are background only. Stealth mode is opt-in only: `sec-settings stealth on|off`.
MD
python3 - "$REPO" "$BLOCK" <<'PY'
import os, re, sys
root, blockf = sys.argv[1:3]
block = open(blockf).read().strip()
mk_s, mk_e = "<!-- security-kit:start -->", "<!-- security-kit:end -->"
def upsert(path):
    txt = open(path).read() if os.path.exists(path) else ""
    txt = re.sub(re.escape(mk_s) + r".*?" + re.escape(mk_e) + r"\n?", "", txt, flags=re.S).rstrip()
    open(path, "w").write((txt + "\n\n" if txt else "") + f"{mk_s}\n{block}\n{mk_e}\n")
    return os.path.basename(path)
claude, agents = os.path.join(root, "CLAUDE.md"), os.path.join(root, "AGENTS.md")
def is_pointer(p):
    return os.path.exists(p) and len(open(p).read().strip().splitlines()) <= 3 and "AGENTS.md" in open(p).read()
target = claude if os.path.exists(claude) and not is_pointer(claude) else agents
print(f"  · {upsert(target)} += Security Kit block ✓")
PY
rm -f "$BLOCK"

# --- curated upstream skills (link into THIS repo only) ---------------------------------
if [ "${SEC_NO_PLUGINS:-0}" != 1 ]; then
    . "$KIT_ROOT/install/lib.sh"
    [ -d "$SEC_UPSTREAM" ] || { echo "  · curated upstream skills: first run — cloning"; sync_upstream_checkouts "$KIT_ROOT" >/dev/null; }
    link_upstream_skills "$KIT_ROOT" .claude/skills claude
    if git rev-parse --git-dir >/dev/null 2>&1; then
        EXCL="$(git rev-parse --git-path info/exclude)"; mkdir -p "$(dirname "$EXCL")"; touch "$EXCL"
        python3 - "$EXCL" "$KIT_ROOT/install/upstream-skills.tsv" <<'PY'
import re, sys
p, man = sys.argv[1], sys.argv[2]
names = sorted({l.split("\t")[0].rsplit("/", 1)[-1] for l in open(man) if l.strip() and not l.startswith("#")})
s, e = "# >>> security-kit curated skills (symlinks into ~/.local/share/security-kit)", "# <<< security-kit curated skills"
txt = re.sub(re.escape(s) + r".*?" + re.escape(e) + r"\n?", "", open(p).read(), flags=re.S).rstrip("\n")
open(p, "w").write((txt + "\n" if txt else "") + s + "\n" + "".join(f"/.claude/skills/{n}\n" for n in names) + e + "\n")
PY
        echo "  · curated skill links git-excluded (.git/info/exclude) ✓"
    fi
fi

# --- Skill Starter Kit verify gate ----------------------------------------------------
if [ -f verify.sh ]; then
    python3 - verify.sh <<'PY'
import re, sys
p = sys.argv[1]; txt = open(p).read()
s, e = "# >>> security-kit", "# <<< security-kit"
txt = re.sub(re.escape(s) + r".*?" + re.escape(e) + r"\n*", "", txt, flags=re.S)
block = f'''{s}
if [ -d sec/regressions ] && ls sec/regressions/*.test.* >/dev/null 2>&1; then
  step "security regression tests"    # Security Kit exploit-verify: regressions that gate every fix
  fail=0
  for t in sec/regressions/*.test.*; do
    case "$t" in
      *.test.ts|*.test.tsx|*.test.js|*.test.jsx)  npx vitest run "$t" --reporter=verbose 2>&1 || fail=$((fail+1)) ;;
      *.test.py) python3 -m pytest "$t" -v 2>&1 || fail=$((fail+1)) ;;
      *.test.sh)  bash "$t" 2>&1 || fail=$((fail+1)) ;;
      *) echo "⚠ $t: unknown test runner — skipped";;
    esac
  done
  [ "$fail" -gt 0 ] && echo "✗ $fail regression test(s) failed" && exit 1 || echo "✓ all regression tests ($(ls sec/regressions/*.test.* 2>/dev/null | wc -l | tr -d ' '))"
fi
{e}
'''
m = re.search(r"^printf '\\n✓ verify passed.*$", txt, flags=re.M)
txt = txt[:m.start()] + block + "\n" + txt[m.start():] if m else txt.rstrip() + "\n\n" + block
open(p, "w").write(txt)
print("  · verify.sh += security regression step ✓")
PY
else
    echo "  · no verify.sh (Skill Starter Kit gate) — regression tests run separately"
fi

# --- GitHub webhook receiver ----------------------------------------------------------
if git remote get-url origin 2>/dev/null | grep -q "github.com"; then
    KIT_SLUG="$(git -C "$KIT_ROOT" remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
    mkdir -p .github/workflows
    sed "s#__KIT_REPO__#${KIT_SLUG:-feelthefusion/security-kit}#" "$KIT_ROOT/templates/github/security-kit-sync.yml" > .github/workflows/security-kit-sync.yml
    echo "  · .github/workflows/security-kit-sync.yml (webhook receiver) ✓"
fi

# --- living-repo stamp ---------------------------------------------------------------
git -C "$KIT_ROOT" rev-parse --short=12 HEAD > .agents/.security-kit-version 2>/dev/null || true
echo "Next: fill the ? lines and Y/Ns in .agents/security-context.md · sec-doctor"