#!/usr/bin/env bash
# =============================================================================
# Security Kit — shared installer library (sourced by install.sh / hermes.sh)
#
# LIVE BY DESIGN — nothing third-party is cloned or copied into this repo:
#   * kit skills      → SYMLINKED from this checkout (bootstrap pulls it every run)
#   * curated upstream → install/upstream-skills.tsv, ONE list for both hosts. Claude Code:
#                        shallow checkouts in $SEC_UPSTREAM (pulled by sec-update on session
#                        start) SYMLINKED per repo by sec-init; Hermes: hub installs + `hermes
#                        skills update`. Only listed skills exist → nothing duplicates.
#   * MCP servers     → handed off to the Skill Starter Kit (gitleaks, osv-scanner, zizmor,
#                        Playwright/CDP); this kit adds no new MCP of its own.
# =============================================================================

SEC_BIN="$HOME/.local/bin"
SEC_CONF="$HOME/.config/security-kit"
KIT_SKILLS="security-kit red-team attack-surface exploit-verify harden-stack fuzz-harness prod-debug stealth-mode"
SEC_UPSTREAM="${SEC_UPSTREAM:-${XDG_DATA_HOME:-$HOME/.local/share}/security-kit/upstream}"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  · %s ✓\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*"; }

kit_self_update() {  # $1 = kit root
    local root="$1" before after
    [ "${KIT_NO_PULL:-0}" = 1 ] && { say "▶ self-update skipped (KIT_NO_PULL=1)"; return 0; }
    git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { say "▶ self-update skipped — not a git clone"; return 0; }
    say "▶ self-update: pulling latest Security Kit"
    if [ -n "$(git -C "$root" status --porcelain)" ]; then warn "local changes — not pulling (commit/stash to get updates)"; return 0; fi
    before="$(git -C "$root" rev-parse --short HEAD)"
    git -C "$root" pull --ff-only --quiet 2>/dev/null || { warn "pull failed (offline/diverged) — using local copy"; return 0; }
    after="$(git -C "$root" rev-parse --short HEAD)"
    [ "$before" = "$after" ] && ok "already at latest ($after)" || ok "updated $before → $after"
}

# Symlink one kit skill dir into a host skills dir (live link, never a copy).
link_skill() {  # link_skill <src-dir> <dst-dir>
    local src="$1" dst="$2"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then ok "$(basename "$dst") linked"; return 0; fi
    [ -e "$dst" ] && rm -rf "$dst"          # replace a stale copy/old link
    ln -s "$src" "$dst" && ok "$(basename "$dst") → $src"
}

# ---- curated upstream skills (install/upstream-skills.tsv) ----------------------------------
upstream_rows()  { grep -v '^#' "$1/install/upstream-skills.tsv" | awk -F'\t' 'NF>=3'; }   # ident hosts trust owns
upstream_repos() { upstream_rows "$1" | cut -f1 | cut -d/ -f1-2 | sort -u; }
upstream_dir()   { printf '%s/%s\n' "$SEC_UPSTREAM" "$(printf '%s' "$1" | tr '/' '_')"; }

# Clone or fast-forward every upstream repo (shallow, one commit deep: always the latest HEAD).
sync_upstream_checkouts() {  # $1 = kit root
    local base="${SEC_GIT_BASE:-https://github.com}" repo d
    mkdir -p "$SEC_UPSTREAM"
    for repo in $(upstream_repos "$1"); do
        d="$(upstream_dir "$repo")"
        if [ -d "$d/.git" ]; then
            if git -C "$d" fetch --depth 1 --quiet origin HEAD 2>/dev/null && git -C "$d" reset --hard --quiet FETCH_HEAD; then
                ok "$repo @ $(git -C "$d" rev-parse --short HEAD)"
            else warn "$repo: fetch failed — keeping $(git -C "$d" rev-parse --short HEAD 2>/dev/null)"; fi
        else
            git clone --depth 1 --quiet "$base/$repo.git" "$d" 2>/dev/null && ok "$repo cloned @ $(git -C "$d" rev-parse --short HEAD)" \
                || warn "$repo: clone failed (offline?) — re-run the installer"
        fi
    done
}

# Link the curated skills for one host into a skills dir; prune links to skills no longer listed.
link_upstream_skills() {  # $1 = kit root  $2 = skills dir  $3 = host (claude|hermes)
    local ident hosts repo path n src linked=0 missing=0 l
    mkdir -p "$2"
    while IFS=$'\t' read -r ident hosts _; do
        case "$hosts" in both|"$3") ;; *) continue ;; esac
        repo="$(printf '%s' "$ident" | cut -d/ -f1-2)"; path="$(printf '%s' "$ident" | cut -d/ -f3-)"; n="${ident##*/}"
        src="$(upstream_dir "$repo")/$path"
        if [ ! -f "$src/SKILL.md" ]; then missing=$((missing+1)); continue; fi
        if [ -e "$2/$n" ] && [ ! -L "$2/$n" ]; then warn "$n: a real skill dir exists in $2 — left as is"; continue; fi
        ln -sfn "$src" "$2/$n"; linked=$((linked+1))
    done < <(upstream_rows "$1")
    for l in "$2"/*; do   # prune
        [ -L "$l" ] || continue
        case "$(readlink "$l")" in "$SEC_UPSTREAM"/*) ;; *) continue ;; esac
        upstream_rows "$1" | cut -f1 | grep -q "/$(basename "$l")\$" || { rm -f "$l"; say "  · $(basename "$l") unlinked (no longer in the curated set)"; }
    done
    ok "$linked curated upstream skills linked into $2"
    [ "$missing" -gt 0 ] && warn "$missing listed skills not in the local checkouts — run the kit installer (it clones them)"
    return 0
}

link_bins() {  # $1 = kit root
    mkdir -p "$SEC_BIN"
    local b
    for b in sec-doctor sec-update sec-settings; do
        chmod +x "$1/bin/$b"; ln -sfn "$1/bin/$b" "$SEC_BIN/$b"
    done
    chmod +x "$1/install/init-project.sh"; ln -sfn "$1/install/init-project.sh" "$SEC_BIN/sec-init"
    ok "sec-doctor sec-update sec-settings sec-init → $SEC_BIN"
    case ":$PATH:" in *":$SEC_BIN:"*) ;; *) warn "$SEC_BIN is not on PATH — add: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;; esac
}

write_marked_block() {  # write_marked_block <file> <marker> <content-file>
    local f="$1" mk="$2" body="$3" tmp
    mkdir -p "$(dirname "$f")"; touch "$f"; tmp="$(mktemp)"
    awk -v s="<!-- $mk:start -->" -v e="<!-- $mk:end -->" '$0==s{skip=1} !skip{print} $0==e{skip=0}' "$f" > "$tmp"
    { printf '<!-- %s:start -->\n' "$mk"; cat "$body"; printf '<!-- %s:end -->\n' "$mk"; } >> "$tmp"
    mv "$tmp" "$f"
}

# Living updates: the session-start event runs `sec-update --hook`.
wire_claude_update_hook() {  # $1 = claude dir
    local f="$1/settings.json"; mkdir -p "$1"
    python3 - "$f" "$SEC_BIN/sec-update --hook" <<'PY'
import json, os, sys
p, cmd = sys.argv[1:3]
s = json.load(open(p)) if os.path.exists(p) else {}
ss = s.setdefault("hooks", {}).setdefault("SessionStart", [])
if not any("sec-update" in h.get("command", "") for g in ss for h in g.get("hooks", [])):
    ss.append({"hooks": [{"type": "command", "command": cmd, "timeout": 10}]})
    json.dump(s, open(p, "w"), indent=2); open(p, "a").write("\n"); print("added")
else: print("present")
PY
}

wire_hermes_update_hook() {
    local cur merged
    cur="$(hermes config get --json hooks.on_session_start 2>/dev/null || echo null)"
    case "$cur" in *sec-update*) echo present; return ;; esac
    merged="$(python3 -c '
import json, sys
try: cur = json.loads(sys.argv[1]) or []
except Exception: cur = []
if not isinstance(cur, list): cur = []
cur.append({"command": sys.argv[2] + " --hook", "timeout": 10})
print(json.dumps(cur))' "$cur" "$SEC_BIN/sec-update")"
    hermes config set hooks.on_session_start "$merged" >/dev/null 2>&1 && echo added || echo failed
}

write_kit_version() {  # $1 = kit root  $2 = dir
    mkdir -p "$2"
    printf 'revision: %s\ninstalled: %s\nsource: %s\n' \
        "$(git -C "$1" rev-parse --short HEAD 2>/dev/null || echo unknown)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$(git -C "$1" remote get-url origin 2>/dev/null || echo "$1")" > "$2/.security-kit-version"
}

# Stealth mode: sec-settings stealth on|off → writes per-repo stealth config.
# Global default: ~/.config/security-kit/stealth/ has the templates + crawler list.
stealth_on() {  # stealth_on <repo-root>
    local root pub sdir kit_root tmpl
    root="$1"; pub="$root/public"; sdir="$root/sec/stealth"
    mkdir -p "$pub" "$sdir"
    kit_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" 2>/dev/null || kit_root="$HOME/.security-kit"
    tmpl="$kit_root/templates"
    # robots.txt
    cp "$tmpl/robots.txt" "$pub/robots.txt"
    ok "public/robots.txt → block all crawlers + explicit AI crawler disallow"
    # crawler list + per-stack header snippets
    cp "$tmpl/crawler-blocklist.txt" "$sdir/crawler-blocklist.txt"
    cp "$tmpl/stealth-headers.md" "$sdir/stealth-headers.md"
    ok "sec/stealth/ → crawler list + per-stack header snippet reference"
    # note limits
    say "  · limitations (honest): robots.txt is a polite request — reputable crawlers honor it, some don't."
    say "    already-indexed pages need time + a removal request (or expire); stealth doesn't retroactively clean."
    say "    doesn't stop direct URL access, scraping, or archive.org (block those UAs explicitly in the list)."
}

stealth_off() {  # stealth_off <repo-root>
    local root pub
    root="$1"; pub="$root/public"
    rm -f "$pub/robots.txt"
    ok "public/robots.txt removed (crawlers can resume)"
    say "  · sec/stealth/ config kept — re-enable with: sec-settings stealth on"
}