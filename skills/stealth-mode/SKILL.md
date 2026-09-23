---
name: stealth-mode
description: "Make a site invisible to search engines and LLM crawlers — noindex, robot block, per-stack HTTP headers. OPT-IN only: sec-settings stealth on. Use when the user asks to 'drop off search,' 'stop crawlers,' 'hide from AI indexing,' or 'make this site unsearchable.'"
---

# Stealth mode — drop off search

Opt-in feature toggle: `sec-settings stealth on` (enabled per repo). Adds `robots.txt`
disallowing everything, HTTP headers (`X-Robots-Tag`), and a per-stack reference for
edge-level crawler blocking. Off by default; never on without the user asking.

## What it does

When `sec-settings stealth on` runs in a repo:
1. Writes `public/robots.txt` (or the repo root): blocks every `User-Agent: *` plus explicit
   AI/LLM crawler entries (GPTBot, ClaudeBot, CCBot, PerplexityBot, Google-Extended, Bytespider,
   Amazonbot, cohere-ai, Diffbot, Scrapy, and 20+ more).
2. Copies the crawler blocklist to `sec/stealth/crawler-blocklist.txt` for edge-level UA blocking.
3. Copies the per-stack header reference to `sec/stealth/stealth-headers.md` — snippets for
   Express, Next.js, nginx, Cloudflare, and static hosts.
4. The agent then applies the right snippet for the repo's framework (Express middleware,
   Next.js layout/metadata + middleware, nginx config, Cloudflare transform rule, `_headers` file).

## What it does NOT do

- **Does NOT remove already-indexed pages** — Google/Bing cache existing crawls; use Search
  Console > Removals (Google) for that. Stealth prevents FUTURE crawling.
- **Does NOT stop direct access or scraping** — anyone with the URL can still hit it. Stealth
  makes the site invisible to crawler/LLM-driven *discovery*, not to access.
- **Does NOT block scrapers that ignore robots.txt** — the UA-level edge block (see the stack
  snippets in `stealth-headers.md`) catches more of them, but determined scrapers spoof UAs.
  This is a crawl block, not a WAF.
- **Does NOT affect mobile apps** — app store metadata, Firebase/APNs deliverability, and in-app
  browsers are separate (App Store Connect / Play Console for store listings).
- **Does NOT affect email/SMS deliverability** — this is about web crawlers only.

## How to toggle

```bash
sec-settings stealth on     # in an app repo — writes robots.txt + stealth config
sec-settings stealth off    # removes robots.txt; keeps sec/stealth/ config to re-enable
```

The agent applies the right per-stack snippet from `sec/stealth/stealth-headers.md`.

## Crawler UA reference

Blocked crawlers (all disallowed in robots.txt; edge-block candidates in the reference snippets):

| Crawler | Owner | Respects robots.txt? |
|---------|-------|----------------------|
| GPTBot | OpenAI | Yes |
| ChatGPT-User | OpenAI | Yes (plugin) |
| OAI-SearchBot | OpenAI | Yes |
| ClaudeBot / Claude-Web / anthropic-ai | Anthropic | Yes |
| CCBot | Common Crawl | Yes |
| PerplexityBot | Perplexity | Yes |
| Google-Extended | Google | Yes (only blocks AI training, not search index — separate `Googlebot`) |
| Bytespider | ByteDance | Partial |
| Amazonbot | Amazon | Yes |
| Applebot-Extended | Apple | Yes |
| cohere-ai | Cohere | Yes |
| Diffbot / ImagesiftBot | Diffbot | Partial |
| Scrapy / MJ12bot / SemrushBot / AhrefsBot / DotBot | Various | No — block at the edge |

## Honest restrictions

- Search engines and reputable AI crawlers honor robots.txt as a matter of policy. They can
  change that policy at any time with no notice, and they don't offer a legal remedy.
- A crawler that ignores robots.txt and spoofs its UA cannot be stopped at the robots.txt layer.
  Edge-level UA blocking (nginx/Cloudflare) catches most but not a determined adversary with
  residential proxies.
- Archive.org: `archive.org_bot` is in the crawler list. Existing snapshots remain; you can
  request removal at archive.org.

## Works with →
- **security-kit** → map loads this on stealth/noindex/robots tasks.
- **Skill Starter Kit** → verify-gate; guardrails (stealth doesn't touch the gate).
- **Marketing Kit** → your marketing sites are the primary target for stealth mode.