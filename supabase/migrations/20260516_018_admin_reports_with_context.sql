-- ============================================================
-- 20260516_018_admin_reports_with_context.sql
-- The original admin_list_reports returned reporter / target /
-- preview but no way to navigate from a "comment" or "message"
-- report to its parent post / chat. Admins were forced to either
-- guess or open the user page (wrong context).
--
-- This migration drops the old admin_list_reports and recreates
-- it with two new nullable columns:
--   * post_id  — set for target_type='comment', looked up from
--                comments.post_id
--   * chat_id  — set for target_type='message', looked up from
--                messages.chat_id
--
-- Both null for 'post' and 'user' targets.
-- ============================================================

set check_function_bodies = off;

-- DROP is required: postgres won't let CREATE OR REPLACE change
-- the return-type signature of an existing function.
drop function if exists public.admin_list_reports(text, int, int);

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
  target_preview      text,
  post_id             bigint,   -- new: post containing the reported comment
  chat_id             bigint    -- new: chat containing the reported message
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
           end,
           case when r.target_type = 'comment'
                then (select c.post_id from public.comments c where c.id = r.target_id)
                else null end,
           case when r.target_type = 'message'
                then (select m.chat_id from public.messages m where m.id = r.target_id)
                else null end
      from public.reports r
      left join public.profiles pr_reporter on pr_reporter.id = r.reporter_id
      left join public.profiles pr_target on pr_target.id = r.target_user_id
     where (p_status is null or r.status = p_status)
     order by r.created_at desc
     limit greatest(0, p_limit) offset greatest(0, p_offset);
end;
$$;

revoke execute on function public.admin_list_reports(text, int, int) from public, anon;
grant  execute on function public.admin_list_reports(text, int, int) to authenticated;
