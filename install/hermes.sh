#!/usr/bin/env bash
# =============================================================================
# Security Kit — HERMES installer.   bash install/hermes.sh   (re-run = update)
#
#   kit skills      symlinked into ~/.hermes/skills/security/ (live from this checkout)
#   vendor skills   `hermes skills install <owner/repo/path>` + `hermes skills update`
#                   each run (curated white-box technique skills)
#   Hand-offs       the Skill Starter Kit owns gitleaks/osv-scanner/zizmor (security-gate),
#                   Superpowers debugging, guardrails — not reinstalled here.
# =============================================================================
set -euo pipefail
SELF="${BASH_SOURCE[0]}"; while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
KIT_ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=install/lib.sh
source "$KIT_ROOT/install/lib.sh"
HH="${HERMES_HOME:-$HOME/.hermes}"
SKILLS_DIR="$HH/skills/security"

say "── Security Kit · Hermes ───────────────────────────────"
kit_self_update "$KIT_ROOT"
HAVE_HERMES=0; command -v hermes >/dev/null 2>&1 && HAVE_HERMES=1
[ "$HAVE_HERMES" = 1 ] || warn "hermes CLI not on PATH — skills get linked; config steps are printed instead"

say "▶ kit skills (symlinked — live from $KIT_ROOT)"
mkdir -p "$SKILLS_DIR"
for s in $KIT_SKILLS; do link_skill "$KIT_ROOT/skills/$s" "$SKILLS_DIR/$s"; done

say "▶ kit CLIs"
link_bins "$KIT_ROOT"

say "▶ curated upstream skills (Hermes skills hub — installed from the vendor repo, updated every run)"
sync_upstream_checkouts "$KIT_ROOT"
if [ "$HAVE_HERMES" = 1 ]; then
    SKROOT="${HERMES_HOME:-$HOME/.hermes}/skills"
    while IFS=$'\t' read -r ident hosts trust; do
        case "$ident" in ''|\#*) continue ;; esac
        case "$hosts" in both|hermes) ;; *) continue ;; esac
        name="${ident##*/}"
        have() { [ -n "$(find "$SKROOT" -maxdepth 3 -path "*/$1/SKILL.md" -print -quit 2>/dev/null)" ]; }
        if have "$name"; then ok "$name present"; continue; fi
        force=""; [ "$trust" = official ] && force="--force"
        out="$(hermes skills install "$ident" --category security --yes $force 2>&1)"
        # `hermes skills install` exits 0 even when its scanner blocks — trust the directory, not the exit code.
        if have "$name"; then
            ok "$name installed${force:+ (official, scanner override)}"
        else
            warn "$name NOT installed: $(printf '%s' "$out" | grep -v '^ *$' | tail -1 | cut -c1-110)"
        fi
    done < <(upstream_rows "$KIT_ROOT")
    hermes skills update >/dev/null 2>&1 && ok "hermes skills update (all hub skills at latest)" || warn "hermes skills update failed — run it manually"
else
    say "  · (hermes CLI not found — run the installer again once Hermes is on PATH)"
fi

say "▶ living updates (session start = the event; no timers)"
if [ "$HAVE_HERMES" = 1 ]; then
    case "$(wire_hermes_update_hook)" in
        added) ok "on_session_start → sec-update --hook (existing hooks kept)"
               say "    Hermes asks once before running a new hook — approve it the first time you start hermes in a terminal" ;;
        present) ok "on_session_start → sec-update --hook already wired" ;;
        *) warn "could not wire on_session_start hook — see hermes hooks --help" ;;
    esac
fi
write_kit_version "$KIT_ROOT" "$HH"
say "─── done ───────────────────────────────────────────────"
say "Start a NEW Hermes session. Then:  sec-doctor   ·   in each app repo:  sec-init"