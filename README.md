# Qurb Admin — لوحة تحكم قُرب

Moderation console for the [Qurb](https://github.com/ziad9899/Qurb) hyperlocal Arabic social app. Built as a separate Flutter Web app so the operator-facing binary is fully isolated from the consumer app shipped on the App Store / Play Store.

## What it does

- **Reports queue** — every report filed in the main app shows up here. Filter by status (open / reviewed / dismissed / all), see the age of each report, and one-click resolve.
- **Post review** — open any reported post to see its full body, all comments, and every report filed against it. Remove the post or jump to the author for a deeper look.
- **User review** — full picture of one user (by numeric_id): profile, posts, comments, reports against them, reports they filed, chat count. Ban / unban with a recorded reason.
- **Chats with reports** — only chats that have an open or reviewed report appear. Admins cannot freely browse private DMs.
- **Gated chat review** — opening any chat requires entering a reason. The server refuses unless an open report ties to this chat, and the access is written to the audit log before messages are returned.
- **Audit log** — every moderator action is recorded with admin email, action, target, reason, and timestamp.

## Architecture

```
┌────────────────────────┐         ┌────────────────────────┐
│   Qurb Admin (Web)     │         │    Qurb (iOS/Android)  │
│   email + password     │         │    anonymous signup    │
└──────────┬─────────────┘         └──────────┬─────────────┘
           │                                   │
           │     same project, different RPCs  │
           │                                   │
           ▼                                   ▼
     ┌─────────────────────────────────────────────┐
     │            Supabase (Postgres)              │
     │                                             │
     │   admin_*  RPCs  ←  gated by _is_admin()    │
     │   reports / posts / comments / messages     │
     │   mod_audit_log  (append-only)              │
     └─────────────────────────────────────────────┘
```

- The admin client never touches `service_role`. Every admin action goes through a `SECURITY DEFINER` RPC that first checks `_is_admin(auth.uid())`.
- A non-admin user who signs in (e.g. by guessing the URL) gets `not_authorized` from every action — the UI is technically reachable but functionally inert.
- All twelve admin RPCs are revoked from `anon` and `public`, and granted to `authenticated`, so an unauthenticated caller can't even reach the gate.

## Setup

### 1. Apply the database migration

The required schema lives in `supabase/migrations/20260516_017_admin_console.sql`. Apply it to the Supabase project that backs the main app — via `supabase db push`, the SQL editor, or the Management API.

The migration creates:
- `admin_users` — allow-list of moderator accounts (deny-all RLS)
- `mod_audit_log` — append-only record (deny-all RLS)
- `_is_admin(uuid)` / `_admin_audit(...)` helpers
- Twelve `admin_*` RPCs

### 2. Create the first admin user

In the Supabase dashboard:

1. Authentication → Users → "Add user" with email + password (set "Auto-confirm email")
2. Copy the new user's UUID
3. In the SQL editor:

```sql
insert into public.admin_users (user_id, email, role)
values ('<uuid-here>', '<email>', 'super_admin');

-- verify
select public._is_admin('<uuid-here>') as is_admin;
```

### 3. Configure Supabase URL + anon key

`lib/core/config/supabase_config.dart` reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from `--dart-define` at build time, falling back to constants in the file. Override per-environment:

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://YOUR.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

The anon key is safe to embed — RLS and the `_is_admin` gate protect the data.

## Develop

```bash
flutter pub get
flutter run -d chrome
```

The dev server opens Chrome at `http://localhost:<port>`. Sign in with the admin email + password you created.

## Build for production

```bash
flutter build web --release
```

Output lands in `build/web/`. Deploy that folder to any static host — GitHub Pages, Cloudflare Pages, Vercel, S3 + CloudFront.

If hosting under a subpath (e.g. `/admin/`):

```bash
flutter build web --release --base-href /admin/
```

## Security notes

- Rotate the admin password before sharing the URL with another operator.
- Do not commit Supabase Management API PATs or `service_role` keys to this repo. `.gitignore` excludes `apply_*.ps1`, `setup_*.ps1`, and similar local-only helper scripts that typically carry secrets.
- All admin actions are recorded in `mod_audit_log` with `admin_id`, `action`, `target_*`, `reason`, and a timestamp. Treat the audit log as legal evidence (KSA Cybercrime Law Article 6, PDPL).
- Private chat access is doubly gated: server refuses unless a related report exists, and the read is recorded *before* messages are returned so the access is logged even if the client crashes mid-read.

## License

Private — internal moderation tooling.
