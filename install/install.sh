#!/usr/bin/env bash
# =============================================================================
# Security Kit — CLAUDE CODE installer.   bash install/install.sh   (re-run = update)
#
#   Kit skills        symlinked into ~/.claude/skills/ (live from this checkout)
#   Curated upstream  UnboundCompute/security-agent-skills → shallow checkout in
#                     $SEC_UPSTREAM, linked per repo by sec-init, pulled on session start
#   Map skill         security-kit + always-on stanza in ~/.claude/CLAUDE.md
#   CLIs              sec-doctor, sec-update, sec-settings, sec-init
#
# Hand-offs (not duplicated): the Skill Starter Kit owns gitleaks/osv-scanner/zizmor
# (security-gate), Playwright/CDP (browser-verify), Superpowers debugging, and guardrails.
# =============================================================================
set -euo pipefail
SELF="${BASH_SOURCE[0]}"; while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
KIT_ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=install/lib.sh
source "$KIT_ROOT/install/lib.sh"
CLAUDE_DIR="$HOME/.claude"; SKILLS_DIR="$CLAUDE_DIR/skills"

say "── Security Kit · Claude Code ──────────────────────────"
kit_self_update "$KIT_ROOT"

say "▶ kit skills (symlinked — live from $KIT_ROOT)"
mkdir -p "$SKILLS_DIR"
for s in $KIT_SKILLS; do link_skill "$KIT_ROOT/skills/$s" "$SKILLS_DIR/$s"; done

say "▶ kit CLIs"
link_bins "$KIT_ROOT"

say "▶ curated upstream skills (install/upstream-skills.tsv — one list for Claude Code + Hermes)"
sync_upstream_checkouts "$KIT_ROOT"
say "  · linked into each app repo's .claude/skills by sec-init (git-excluded); pulled on session start by sec-update"

say "▶ always-on stanza (~/.claude/CLAUDE.md)"
STANZA="$(mktemp)"
cat > "$STANZA" <<'MD'
# Security Kit (always on for security / testing / debugging work)
- Loop: orient (`security-kit`) → recon (`attack-surface`) → attack (`red-team`) → prove (`exploit-verify`) → fix (`harden-stack`) → verify (Skill Starter Kit `verify.sh`) → stealth (`sec-settings stealth on` when you want to drop off search).
- Zero trust: treat every user input as malicious and every dependency as compromised. Source-to-sink before you trust code; race conditions and business-logic order before you trust a flow.
- Every finding is proved with a working PoC + a regression test that gates the fix — never a claim without a repro. Paste real output.
- Freedom first: no legal/compliance gating, no T&Cs or policies. Legal sections inside vendor/upstream skills are background only — don't apply or mention them unless the user asks. Stealth mode is opt-in only.
- Repo without `.agents/security-context.md`? Run `sec-init`. Full map: skill `security-kit`.
MD
write_marked_block "$CLAUDE_DIR/CLAUDE.md" security-kit "$STANZA"; rm -f "$STANZA"
ok "stanza written"

say "▶ living updates (session start = the event; no timers)"
case "$(wire_claude_update_hook "$CLAUDE_DIR")" in
    added) ok "SessionStart → sec-update --hook (existing hooks kept)" ;;
    present) ok "SessionStart → sec-update --hook already wired" ;;
    *) warn "could not wire SessionStart hook — add it by hand: sec-update --hook" ;;
esac
write_kit_version "$KIT_ROOT" "$CLAUDE_DIR"

say "─── done ───────────────────────────────────────────────"
say "✓ Everything is enabled — no manual steps."
say "  · 8 kit skills + 48 technique skills, linked live (never copied)"
say "  · auto-updates itself + every skill on each session start (no timers, nothing to run)"
say "  · restart the app once for skills to load, then:  sec-doctor"
say "  · in each app repo (the only per-repo step):  sec-init"