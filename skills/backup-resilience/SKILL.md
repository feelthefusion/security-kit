---
name: backup-resilience
description: "Use for backups, restore and disaster recovery of a site or app: database backups (pg_dump), file/bucket mirrors, settings and secrets snapshots, retention, off-site copies in a separate cloud account, encryption, host ban or outage recovery, backup monitoring dashboards and alerts, kill switches, restore guides and restore drills. Owns the rule 'backups are private, encrypted and off-host': three independent copies on three trust boundaries, never in a public bucket; production writes off-site with a write-only credential and never prunes it; the local copy sits on an encrypted disk outside cloud sync."
---

# Backup resilience: survive losing the host, the account or the bucket

A backup that lives on the same host, in the same cloud account, or in the site's public bucket is
not a backup. It disappears with the host (outage, ban, deleted project), it is reachable by the
same compromised credential, or it is published to the world. This skill owns where backups go,
what they contain, how long they are kept, how you know they are fresh, and how you restore.

## 1. Three copies, three trust boundaries

| Copy | Where | Why it survives |
|------|-------|-----------------|
| 1. Production | The live DB, file bucket and host settings | It is the source; the provider's own snapshots are a bonus, not a plan. |
| 2. Local | A machine the owner controls (always-on desktop, home server, NAS) with full-disk encryption on, the backup folder outside any cloud-synced folder | Survives losing the cloud account, a ban, or a billing lockout. |
| 3. Off-site | A **private** bucket in a **separate** cloud account with its own credentials | Survives losing the local machine. Production holds only a write credential for it, so production cannot read or delete it (see "Who can delete the off-site copy"). |

Never:
- on the same host or volume as production;
- in the same cloud account as production with the same credentials;
- in a public bucket, CDN or static path (see `data-exposure`). Do not reuse the site's upload
  client or bucket variable for backups, even "temporarily". Backup code builds its own client
  from its own settings and is off unless every one of those settings is present.

### Who can delete the off-site copy

Production must never hold a credential that can delete (or read) the off-site history, or one
compromise of production, or one bad deploy of a prune step, wipes every off-site copy. So:

- **Production writes with a write-only credential.** Scope it to the one backup bucket with
  put-object and the multipart upload actions only. Where the provider has no write-only scope,
  or the upload tool needs it, put + list is the most it gets. Never get, never delete. Every
  dump goes to a new timestamped key, so a put never overwrites an older copy; turn on
  versioning or object lock where the provider offers it as a second belt.
- **Pruning never runs with the production credential.** Pick one of these two options:
  1. **Bucket lifecycle rules** (simplest): the provider deletes by prefix and age, for example
     `hourly/` after 1 day and `daily/` after 30 days, with the writer putting the first dump of
     each day under `daily/` as well. Nobody holds a delete credential at all.
  2. **A separate prune job with its own credential** (list + delete on that bucket only),
     run from the owner's machine (the local backup host), never from production. That
     credential lives only on that machine, never in the production env.
- Restores and restore drills read the off-site copy with a separate read credential kept on the
  owner's machine, not in production.

### Encryption for off-site copies
- AES-256-GCM (authenticated), a fresh random IV per file, the auth tag stored with the file, a
  small header with format version and key id so keys can rotate.
- The key never lives in the bucket. It lives in the production host's env (to write) and on the
  local machine (to restore). Losing the key means losing the off-site copy, so store it in two
  places the owner controls.
- Stream: `pg_dump | encrypt | multipart upload`. Never buffer a whole dump in memory. On any
  failure, kill the dump child process and abort the multipart upload.

## 2. What to back up

| Stream | Schedule | Format and notes |
|--------|----------|------------------|
| Full DB dump | Hourly | `pg_dump -Fc` (custom format: compressed, selective restore). Check each dump with `pg_restore --list` (non-empty TOC) before counting it as a success. |
| Files / bucket mirror | Every 15 min | Exact mirror of the upload bucket to local disk. Before overwriting or deleting a local file, move the old version to a `replaced/` or `deleted/` safety folder kept for 90 days, so a bad sync or a mass delete upstream cannot wipe the mirror. |
| Settings and secrets snapshot | Hourly, versioned only on change | All host env vars, service settings (build/start commands, replicas, regions, domains, cron), DNS zone export, deploy keys. **Local machine only**, directory mode 700, files 600, never uploaded anywhere (and never synced, see below). This is what turns "rebuild from scratch" into hours instead of days. |
| Off-site encrypted DB dump | Hourly | Same dump, encrypted, to the separate-account private bucket. |

### Protect the local copy

The local machine holds plaintext database dumps and a snapshot of every production secret, so it
is as sensitive as production itself. File modes 700/600 do nothing once the disk leaves the
owner's hands. Required:

- **Full-disk encryption on**: FileVault (macOS, check `fdesetup status`), LUKS (Linux) or
  BitLocker (Windows). No exceptions for an "always-on desktop at home".
- **Backup folders outside cloud sync**: never under iCloud Drive (including synced Desktop and
  Documents), Dropbox, OneDrive, Google Drive or any other synced folder. A sync client turns the
  local copy into a fourth, unplanned copy in someone else's account.
- **Excluded from other backup targets** (Time Machine, NAS jobs, cloud PC backup) unless that
  target is itself encrypted and under the owner's control.
- A screen lock and a user account password on the machine; the restore key and the read
  credential for the off-site bucket stay on this encrypted disk (and the second copy of the key
  in the owner's password manager).

## 3. Retention defaults

| Where | DB dumps | Notes |
|-------|----------|-------|
| Local | 24 hourly + 30 daily + 12 monthly | Promote the first dump of each day and month. |
| Off-site | 24 hourly + 30 daily | Bucket lifecycle rules by prefix, or a prune job with its own list + delete credential run from the owner's machine. Never a prune step in the production worker (it holds a write-only credential). |
| File mirror safety folders | 90 days | Pruned by age. |
| Settings snapshots | Every changed version | Small; keep them all or prune by age. |

**Disk guard:** when free space drops below a threshold (for example 50 GB), prune the oldest
monthly, then the oldest daily, then the oldest hourly. Never delete the newest copy of any tier,
and never prune because a run failed. Log every prune.

## 4. Where the jobs run

- Heavy jobs (dumps, encryption, uploads) run on a **worker** process or a scheduled job, never in
  the web process: a 1 GB dump in the web process steals memory and CPU from requests and dies
  with every deploy. The worker only uploads, with the write-only credential; it never prunes the
  off-site bucket.
- Local jobs run under the OS scheduler (launchd, systemd timers, cron) with a lock file so runs
  never overlap.
- Every job has a **kill switch** env var (for example `OFFSITE_BACKUP=off`) that stops it at
  the next run without a deploy. Default off when required settings are missing (fail closed).

## 5. Monitoring: every run reports, one dashboard, one alert per incident

- Every run (local and server) POSTs a report to the app: stream name, status, started and
  finished time, size, object count, duration, error text. The endpoint requires a dedicated
  bearer token (constant-time compare) and returns a JSON body such as `{ok:true}`; reporters
  treat anything else (including an HTML fallback page with status 200) as a failed report.
- An admin **Backups** dashboard shows, per stream: last success, age against its threshold
  (for example hourly stream: warn at 2 h, stale at 3 h; 15-min mirror: stale at 1 h), size and
  duration charts, recent runs with logs, and actions (run now, pause, test restore).
- When a stream goes stale or fails, send **one** alert per incident (not one per check) to the
  admin, and one recovery notice when it is fresh again.

## 6. Restore

- Keep a restore guide next to the local backups (DB restore, file restore, and a config restore
  guide for rebuilding the host from the settings snapshot). Write it for someone stressed at
  3 a.m.: exact commands, where the keys are, how to decrypt, how to point DNS.
- **Restore drills**, at least monthly and after any change to the backup code: restore the latest
  dump into a scratch database, compare row counts of the key tables against production (within
  the expected drift for the dump age), run a few known queries, drop the scratch DB. Record the
  result in the dashboard. A backup that has never been restored is a hope, not a backup.
- At least quarterly, run the drill from the **off-site** copy too (fetch it with the owner's
  read credential, decrypt with the stored key, restore), and restore one file from the mirror's
  safety folders, so every copy, key and credential is proven, not just the local dump.

## 7. Checklist for a new setup

- [ ] Three copies on three trust boundaries; off-site bucket is private and in a separate account
- [ ] Production holds a write-only (or put + list) credential for the off-site bucket: no get, no delete; timestamped keys; versioning or object lock if offered
- [ ] Off-site pruning by bucket lifecycle rules, or by a separate list + delete credential run from the owner's machine; never from production
- [ ] Local machine has full-disk encryption on; backup and settings folders are outside iCloud/Dropbox/OneDrive/Google Drive sync and excluded from unencrypted backup targets
- [ ] No backup code imports the site's upload client, bucket name or public URL
- [ ] Off-site dumps encrypted with AES-256-GCM; key stored in the host env and on the local machine, not in the bucket
- [ ] DB dump hourly in custom format, verified with `pg_restore --list`
- [ ] File mirror every 15 min with replaced/deleted safety folders (90 days)
- [ ] Settings snapshot (env vars, service settings, DNS zone, deploy keys) on the local machine only, 700/600
- [ ] Retention set (24h + 30d + 12m local, 24h + 30d off-site) and the disk guard never deletes the newest copy
- [ ] Heavy jobs run on a worker; local jobs use the OS scheduler with a lock
- [ ] Kill switch env var works and defaults off when settings are missing
- [ ] Every run reports to a token-protected endpoint; reporters require a JSON success body
- [ ] Dashboard shows freshness per stream with thresholds; one alert per incident
- [ ] Restore guides written; a restore drill into a scratch DB passed with row counts compared, monthly, and quarterly from the off-site copy
- [ ] `data-exposure` smoke check confirms no dump is reachable on any public URL

## Works with →
- **data-exposure**: the public-write guard and smoke check that keep backups out of public
  storage; its incident playbook if a backup ever lands somewhere public.
- **prod-debug**: an outage or ban is an incident; the restore guide is its runbook.
- **harden-stack**: the report endpoint's token auth, the kill switch, fail-closed defaults.
- Skill Starter Kit **guardrails** blocks destructive commands (`DROP DATABASE`, `rm -rf` on the
  backup folder) during restore work.
