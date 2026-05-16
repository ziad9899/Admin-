-- ============================================================
-- 20260516_017_admin_console.sql
-- Phase 9: Admin moderation console.
--
-- Introduces:
--   * admin_users          — allow-list of moderator accounts.
--   * mod_audit_log        — append-only record of every admin action.
--   * _is_admin(uuid)      — cheap gate reused by every admin RPC.
--   * _admin_audit(...)    — internal helper, never exposed to clients.
--   * 11 admin_* RPCs      — reports queue, post/user review, ban,
--                            resolve-report, chat review (gated by
--                            an existing report on the chat), audit
--                            log readback, admin roster readback.
--
-- All admin RPCs are SECURITY DEFINER + check _is_admin(auth.uid())
-- at the top, and granted to `authenticated` (NOT service_role) so a
-- moderator can sign in with email/password from the web admin app
-- without the client ever holding the service_role key.
-- ============================================================

set check_function_bodies = off;

-- ============================================================
-- TABLES
-- ============================================================

create table if not exists public.admin_users (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text not null,
  role       text not null default 'admin' check (role in ('admin','super_admin')),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

create index if not exists admin_users_email_idx on public.admin_users(email);

create table if not exists public.mod_audit_log (
  id          bigserial primary key,
  admin_id    uuid references auth.users(id) on delete set null,
  action      text not null,
  target_type text,
  target_id   bigint,
  target_uid  uuid,
  reason      text,
  metadata    jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists mod_audit_log_admin_time_idx
  on public.mod_audit_log(admin_id, created_at desc);
create index if not exists mod_audit_log_target_idx
  on public.mod_audit_log(target_type, target_id);

-- ============================================================
-- _is_admin(uuid) — stable, used in every admin RPC's first line.
-- ============================================================
create or replace function public._is_admin(p_uid uuid)
returns boolean
language sql stable
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.admin_users where user_id = p_uid
  );
$$;

-- ============================================================
-- _admin_audit — internal helper. Revoked from anon/authenticated
-- so only other SECURITY DEFINER functions in this file can call it.
-- ============================================================
create or replace function public._admin_audit(
  p_admin       uuid,
  p_action      text,
  p_target_type text default null,
  p_target_id   bigint default null,
  p_target_uid  uuid default null,
  p_reason      text default null,
  p_metadata    jsonb default null
) returns bigint
language sql security definer
set search_path = public, pg_temp
as $$
  insert into public.mod_audit_log(
    admin_id, action, target_type, target_id, target_uid, reason, metadata
  ) values (
    p_admin, p_action, p_target_type, p_target_id, p_target_uid, p_reason, p_metadata
  )
  returning id;
$$;

-- ============================================================
-- 1. admin_list_reports — queue of moderation reports.
--    p_status NULL returns all statuses; default is 'open'.
-- ============================================================
create or replace function public.admin_list_reports(
  p_status text default 'open',
  p_limit  int  default 50,
  p_offset int  default 0
) returns table (
  id                  bigint,
  reporter_numeric_id int,
  target_type         text,
  target_id           bigint,
  target_numeric_id   int,
  reason              text,
  note                text,
  status              text,
  created_at          timestamptz,
  target_preview      text
)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public._is_admin(v_uid) then raise exception 'not_authorized'; end if;
  return query
    select r.id,
           pr_reporter.numeric_id,
           r.target_type,
           r.target_id,
           pr_target.numeric_id,
           r.reason,
           r.note,
           r.status,
           r.created_at,
           case
             when r.target_type = 'post' then
               (select left(p.body, 200) from public.posts p where p.id = r.target_id)
             when r.target_type = 'comment' then
               (select left(c.body, 200) from public.comments c where c.id = r.target_id)
             when r.target_type = 'message' then
               (select left(m.body, 200) from public.messages m where m.id = r.target_id)
             when r.target_type = 'user' then
               '#' || coalesce(pr_target.numeric_id::text, '?')
             else null
           end
      from public.reports r
      left join public.profiles pr_reporter on pr_reporter.id = r.reporter_id
      left join public.profiles pr_target on pr_target.id = r.target_user_id
     where (p_status is null or r.status = p_status)
     order by r.created_at desc
     limit greatest(0, p_limit) offset greatest(0, p_offset);
end;
$$;

-- ============================================================
-- 2. admin_get_post_with_context — post + all comments + all reports.
--    Explicit field lists avoid serializing geography columns.
-- ============================================================
create or replace function public.admin_get_post_with_context(p_post_id bigint)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_post jsonb;
  v_comments jsonb;
  v_reports jsonb;
begin
  if not public._is_admin(v_uid) then raise exception 'not_authorized'; end if;

  select jsonb_build_object(
           'id', p.id,
           'body', p.body,
           'tag', p.tag,
           'proximity', p.proximity,
           'score', p.score,
           'comments_count', p.comments_count,
           'status', p.status,
           'has_image', p.has_image,
           'created_at', p.created_at,
           'expires_at', p.expires_at,
           'edited_at', p.edited_at,
           'author_numeric_id', pr.numeric_id,
           'author_status', pr.status
         )
    into v_post
    from public.posts p
    join public.profiles pr on pr.id = p.user_id
   where p.id = p_post_id;
  if v_post is null then raise exception 'post_not_found'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id,
           'parent_id', c.parent_id,
           'body', c.body,
           'score', c.score,
           'status', c.status,
           'created_at', c.created_at,
           'author_numeric_id', pr.numeric_id,
           'author_status', pr.status
         ) order by c.created_at), '[]'::jsonb)
    into v_comments
    from public.comments c
    join public.profiles pr on pr.id = c.user_id
   where c.post_id = p_post_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id,
           'reason', r.reason,
           'note', r.note,
           'status', r.status,
           'created_at', r.created_at,
           'reporter_numeric_id', pr.numeric_id
         ) order by r.created_at desc), '[]'::jsonb)
    into v_reports
    from public.reports r
    left join public.profiles pr on pr.id = r.reporter_id
   where r.target_type = 'post' and r.target_id = p_post_id;

  return jsonb_build_object(
    'post', v_post,
    'comments', v_comments,
    'reports', v_reports
  );
end;
$$;

-- ============================================================
-- 3. admin_get_user_summary — full picture of one user for review.
-- ============================================================
create or replace function public.admin_get_user_summary(p_numeric_id int)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_target_uid uuid;
  v_profile jsonb;
  v_posts jsonb;
  v_comments jsonb;
  v_reports_against jsonb;
  v_reports_filed_count int;
  v_chats_count int;
begin
  if not public._is_admin(v_uid) then raise exception 'not_authorized'; end if;
  select id into v_target_uid from public.profiles where numeric_id = p_numeric_id;
  if v_target_uid is null then raise exception 'user_not_found'; end if;

  select jsonb_build_object(
           'numeric_id', pr.numeric_id,
           'status', pr.status,
           'city_code', pr.city_code,
           'created_at', pr.created_at,
           'last_seen_at', pr.last_seen_at
         )
    into v_profile
    from public.profiles pr where pr.id = v_target_uid;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id,
           'body', p.body,
           'tag', p.tag,
           'proximity', p.proximity,
           'score', p.score,
           'comments_count', p.comments_count,
           'status', p.status,
           'created_at', p.created_at
         ) order by p.created_at desc), '[]'::jsonb)
    into v_posts
    from public.posts p where p.user_id = v_target_uid;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id,
           'post_id', c.post_id,
           'body', c.body,
           'score', c.score,
           'status', c.status,
           'created_at', c.created_at
         ) order by c.created_at desc), '[]'::jsonb)
    into v_comments
    from public.comments c where c.user_id = v_target_uid;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id,
           'target_type', r.target_type,
           'target_id', r.target_id,
           'reason', r.reason,
           'note', r.note,
           'status', r.status,
           'created_at', r.created_at,
           'reporter_numeric_id', pr.numeric_id
         ) order by r.created_at desc), '[]'::jsonb)
    into v_reports_against
    from public.reports r
    left join public.profiles pr on pr.id = r.reporter_id
   where r.target_user_id = v_target_uid;

  select count(*) into v_reports_filed_count
    from public.reports where reporter_id = v_target_uid;
  select count(*) into v_chats_count
    from public.chats where user_a = v_target_uid or user_b = v_target_uid;

  return jsonb_build_object(
    'profile', v_profile,
    'posts', v_posts,
    'comments', v_comments,
    'reports_against', v_reports_against,
    'reports_filed_count', v_reports_filed_count,
    'chats_count', v_chats_count
  );
end;
$$;

-- ============================================================
-- 4. admin_remove_post — soft-removes + audits with body snapshot.
-- ============================================================
create or replace function public.admin_remove_post(
  p_post_id bigint,
  p_reason  text
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_body_snapshot text;
begin
  if not public._is_admin(v_uid) then raise exception 'not_authorized'; end if;
  select user_id, left(body, 500) into v_owner, v_body_snapshot
    from public.posts where id = p_post_id;
  if v_owner is null then raise exception 'post_not_found'; end if;

  update public.posts set status = 'removed' where id = p_post_id;

  perform public._admin_audit(
    v_uid, 'remove_post', 'post', p_post_id, v_owner, p_reason,
    jsonb_build_object('body_snapshot', v_body_snapshot)
  );
end;
$$;

-- ============================================================
-- 5. admin_remove_comment — soft-removes + decrements parent count.
-- ============================================================
create or replace function public.admin_remove_comment(
  p_comment_id bigint,
  p_reason     text
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_body_snapshot text;
  v_post_id bigint;
  v_was_active boolean;
begin
  if not public._is_admin(v_uid) then raise exception 'not_authorized'; end if;
  select user_id, post_id, left(body, 500), status = 'active'
    into v_owner, v_post_id, v_body_snapshot, v_was_active
    from public.comments where id = p_comment_id;
  if v_owner is null then raise exception 'comment_not_found'; end if;

  update public.comments set status = 'removed' where id = p_comment_id;
  if v_was_active then
    update public.posts set comments_count = greatest(0, comments_count - 1)
     where id = v_post_id;
  end if;

  perform public._admin_audit(
    v_uid, 'remove_comment', 'comment', p_comment_id, v_owner, p_reason,
    jsonb_build_object('body_snapshot', v_body_snapshot, 'post_id', v_post_id)
  );
end;
$$;

-- ============================================================
-- 6. admin_ban_user — refuses to ban another admin.
-- ============================================================
create or replace function public.admin_ban_user(
  p_numeric_id int,
  p_reason     text
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_target uuid;
begin
  if not public._is_admin(v_uid) then raise exception 'not_authorized'; end if;
  select id into v_target from public.profiles where numeric_id = p_numeric_id;
  if v_target is null then raise exception 'user_not_found'; end if;
  if public._is_admin(v_target) then raise exception 'cannot_ban_admin'; end if;

  update public.profiles set status = 'banned' where id = v_target;
  update public.posts set status = 'removed'
   where user_id = v_target and status = 'active';

  perform public._admin_audit(
    v_uid, 'ban_user', 'user', p_numeric_id::bigint, v_target, p_reason, null
  );
  return v_target;
end;
$$;

-- ============================================================
-- 7. admin_unban_user — does NOT auto-restore previously-removed
-- posts; that would over-reach. Restoring content is a separate
-- decision (and a different RPC, if added later).
-- ============================================================
create or replace function public.admin_unban_user(
  p_numeric_id int,
  p_reason     text
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_target uuid;
begin
  if not public._is_admin(v_uid) then raise exception 'not_authorized'; end if;
  select id into v_target from public.profiles where numeric_id = p_numeric_id;
  if v_target is null then raise exception 'user_not_found'; end if;

  update public.profiles set status = 'active' where id = v_target;
  perform public._admin_audit(
    v_uid, 'unban_user', 'user', p_numeric_id::bigint, v_target, p_reason, null
  );
  return v_target;
end;
$$;

-- ============================================================
-- 8. admin_resolve_report — close out a report row.
-- ============================================================
create or replace function public.admin_resolve_report(
  p_report_id bigint,
  p_action    text,
  p_note      text
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public._is_admin(v_uid) then raise exception 'not_authorized'; end if;
  if p_action not in ('reviewed','dismissed') then raise exception 'bad_action'; end if;
  update public.reports set status = p_action where id = p_report_id;
  if not found then raise exception 'report_not_found'; end if;

  perform public._admin_audit(
    v_uid, 'resolve_report', 'report', p_report_id, null, p_note,
    jsonb_build_object('resolution', p_action)
  );
end;
$$;

-- ============================================================
-- 9. admin_list_chats_with_open_reports
--    A chat appears here only when there is a report against one
--    of its messages OR against one of its two participants.
-- ============================================================
create or replace function public.admin_list_chats_with_open_reports(
  p_limit  int default 50,
  p_offset int default 0
) returns table (
  chat_id              bigint,
  user_a_numeric_id    int,
  user_b_numeric_id    int,
  message_count        bigint,
  message_report_count bigint,
  last_message_at      timestamptz,
  reason_source        text
)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public._is_admin(v_uid) then raise exception 'not_authorized'; end if;
  return query
    with msg_reported as (
      select distinct m.chat_id
        from public.messages m
        join public.reports r
          on r.target_type = 'message' and r.target_id = m.id
       where r.status in ('open', 'reviewed')
    ),
    user_reported as (
      select distinct c.id as chat_id
        from public.chats c
        join public.reports r
          on r.target_user_id in (c.user_a, c.user_b)
       where r.target_type = 'user' and r.status in ('open', 'reviewed')
    ),
    candidates as (
      select chat_id, 'message'::text as reason from msg_reported
      union
      select chat_id, 'user'::text    as reason from user_reported
    )
    select c.id,
           pa.numeric_id,
           pb.numeric_id,
           (select count(*) from public.messages m where m.chat_id = c.id),
           (select count(*) from public.reports r
              join public.messages m on m.id = r.target_id
             where r.target_type = 'message'
               and m.chat_id = c.id
               and r.status in ('open', 'reviewed')),
           c.last_message_at,
           string_agg(distinct cand.reason, ',' order by cand.reason)
      from candidates cand
      join public.chats c on c.id = cand.chat_id
      join public.profiles pa on pa.id = c.user_a
      join public.profiles pb on pb.id = c.user_b
     group by c.id, pa.numeric_id, pb.numeric_id, c.last_message_at
     order by c.last_message_at desc nulls last
     limit greatest(0, p_limit) offset greatest(0, p_offset);
end;
$$;

-- ============================================================
-- 10. admin_open_chat_for_review
--     Hard gate: refuses unless there is at least one report
--     (open or reviewed) tied to this chat. Writes audit log
--     BEFORE returning the messages so the access is recorded
--     even if the caller crashes mid-read.
-- ============================================================
create or replace function public.admin_open_chat_for_review(
  p_chat_id bigint,
  p_reason  text
) returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_chat public.chats;
  v_has_report boolean;
  v_messages jsonb;
  v_a_numeric int;
  v_b_numeric int;
begin
  if not public._is_admin(v_uid) then raise exception 'not_authorized'; end if;
  select * into v_chat from public.chats where id = p_chat_id;
  if v_chat.id is null then raise exception 'chat_not_found'; end if;

  select exists (
    select 1 from public.reports r
     where r.status in ('open', 'reviewed')
       and (
         (r.target_type = 'message' and r.target_id in
            (select id from public.messages where chat_id = p_chat_id))
         or
         (r.target_type = 'user' and r.target_user_id in (v_chat.user_a, v_chat.user_b))
       )
  ) into v_has_report;
  if not v_has_report then raise exception 'no_open_report_against_chat'; end if;

  select numeric_id into v_a_numeric from public.profiles where id = v_chat.user_a;
  select numeric_id into v_b_numeric from public.profiles where id = v_chat.user_b;

  perform public._admin_audit(
    v_uid, 'open_chat_for_review', 'chat', p_chat_id, null, p_reason, null
  );

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id,
           'sender_numeric_id', pr.numeric_id,
           'is_user_a', m.sender_id = v_chat.user_a,
           'body', m.body,
           'created_at', m.created_at,
           'read_at', m.read_at,
           'reported', exists (
             select 1 from public.reports r
              where r.target_type = 'message' and r.target_id = m.id
           )
         ) order by m.created_at), '[]'::jsonb)
    into v_messages
    from public.messages m
    join public.profiles pr on pr.id = m.sender_id
   where m.chat_id = p_chat_id;

  return jsonb_build_object(
    'chat_id', p_chat_id,
    'user_a_numeric_id', v_a_numeric,
    'user_b_numeric_id', v_b_numeric,
    'created_at', v_chat.created_at,
    'status', v_chat.status,
    'messages', v_messages
  );
end;
$$;

-- ============================================================
-- 11. admin_list_audit_log — read-back of moderator actions.
-- ============================================================
create or replace function public.admin_list_audit_log(
  p_limit  int default 100,
  p_offset int default 0
) returns table (
  id           bigint,
  admin_email  text,
  action       text,
  target_type  text,
  target_id    bigint,
  reason       text,
  metadata     jsonb,
  created_at   timestamptz
)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public._is_admin(v_uid) then raise exception 'not_authorized'; end if;
  return query
    select ml.id, au.email, ml.action, ml.target_type, ml.target_id,
           ml.reason, ml.metadata, ml.created_at
      from public.mod_audit_log ml
      left join public.admin_users au on au.user_id = ml.admin_id
     order by ml.created_at desc
     limit greatest(0, p_limit) offset greatest(0, p_offset);
end;
$$;

-- ============================================================
-- 12. admin_list_admins — roster of current moderators.
-- ============================================================
create or replace function public.admin_list_admins()
returns table (user_id uuid, email text, role text, created_at timestamptz)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public._is_admin(v_uid) then raise exception 'not_authorized'; end if;
  return query
    select au.user_id, au.email, au.role, au.created_at
      from public.admin_users au
     order by au.created_at;
end;
$$;

-- ============================================================
-- RLS — both tables have RLS on but NO policies, so anon and
-- authenticated cannot read them directly. Admin RPCs reach them
-- via SECURITY DEFINER (which bypasses RLS as the function owner).
-- ============================================================
alter table public.admin_users   enable row level security;
alter table public.mod_audit_log enable row level security;

-- ============================================================
-- GRANTS
-- ============================================================
-- Postgres grants EXECUTE on functions to PUBLIC by default. Each admin
-- RPC already gates internally on _is_admin(auth.uid()), but for
-- defense-in-depth we revoke PUBLIC/anon access so unauth callers
-- can't even reach the gate.
revoke all on function public._is_admin(uuid) from public, anon;
grant execute on function public._is_admin(uuid) to authenticated;

revoke all on function public._admin_audit(uuid, text, text, bigint, uuid, text, jsonb)
  from public, anon, authenticated;

revoke execute on function public.admin_list_reports(text, int, int)              from public, anon;
revoke execute on function public.admin_get_post_with_context(bigint)             from public, anon;
revoke execute on function public.admin_get_user_summary(int)                     from public, anon;
revoke execute on function public.admin_remove_post(bigint, text)                 from public, anon;
revoke execute on function public.admin_remove_comment(bigint, text)              from public, anon;
revoke execute on function public.admin_ban_user(int, text)                       from public, anon;
revoke execute on function public.admin_unban_user(int, text)                     from public, anon;
revoke execute on function public.admin_resolve_report(bigint, text, text)        from public, anon;
revoke execute on function public.admin_list_chats_with_open_reports(int, int)    from public, anon;
revoke execute on function public.admin_open_chat_for_review(bigint, text)        from public, anon;
revoke execute on function public.admin_list_audit_log(int, int)                  from public, anon;
revoke execute on function public.admin_list_admins()                             from public, anon;

grant execute on function public.admin_list_reports(text, int, int)              to authenticated;
grant execute on function public.admin_get_post_with_context(bigint)             to authenticated;
grant execute on function public.admin_get_user_summary(int)                     to authenticated;
grant execute on function public.admin_remove_post(bigint, text)                 to authenticated;
grant execute on function public.admin_remove_comment(bigint, text)              to authenticated;
grant execute on function public.admin_ban_user(int, text)                       to authenticated;
grant execute on function public.admin_unban_user(int, text)                     to authenticated;
grant execute on function public.admin_resolve_report(bigint, text, text)        to authenticated;
grant execute on function public.admin_list_chats_with_open_reports(int, int)    to authenticated;
grant execute on function public.admin_open_chat_for_review(bigint, text)        to authenticated;
grant execute on function public.admin_list_audit_log(int, int)                  to authenticated;
grant execute on function public.admin_list_admins()                             to authenticated;
