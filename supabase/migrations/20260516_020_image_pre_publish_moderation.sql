-- ============================================================
-- 20260516_020_image_pre_publish_moderation.sql
-- Phase 10 follow-up: shift image posts to pre-publish moderation.
--
-- Why:
--   Apple Guideline 1.2 expects UGC apps to "filter objectionable
--   content before it is posted." We don't have AWS/Cloudflare
--   wired in yet, so the realistic compliance path is human
--   moderation through the admin console with a < 24 h SLA.
--
-- What changes:
--   1. post_images.status default flips from 'active' to
--      'pending_review'. Existing rows are NOT touched — they were
--      already active under the old default.
--   2. posts_feed view filters image posts to those whose
--      post_images.status = 'active'. Text-only posts are unaffected.
--   3. New admin RPCs:
--        admin_list_pending_images  — FIFO queue for moderators
--        admin_approve_image        — flips status to 'active'
--        admin_reject_image         — flips status to 'removed' AND
--                                     marks the parent post.status='removed'
--                                     so the body disappears with the image
-- ============================================================

set check_function_bodies = off;

------------------------------------------------------------
-- 1. Flip the column default. Old rows keep their current status.
------------------------------------------------------------
alter table public.post_images
  alter column status set default 'pending_review';

------------------------------------------------------------
-- 2. Rebuild posts_feed so image posts wait for approval.
--    Column order must match migration 019 exactly (CREATE OR
--    REPLACE VIEW can't reorder columns) — we add no new columns,
--    only tighten the WHERE clause.
------------------------------------------------------------
create or replace view public.posts_feed as
  select
    p.id, p.body, p.tag, p.proximity, p.score, p.comments_count,
    p.has_image, p.created_at, p.expires_at,
    pr.numeric_id as author_numeric_id,
    p.edited_at,
    pi.storage_path as image_path
  from public.posts p
  join public.profiles pr on pr.id = p.user_id
  left join public.post_images pi on pi.post_id = p.id and pi.status = 'active'
  where p.status = 'active'
    and pr.status = 'active'
    and p.expires_at > now()
    -- A post with has_image=true is only visible once its image row
    -- is approved (pi.status='active', enforced by the LEFT JOIN
    -- predicate above making image_path null when not approved).
    -- The poster still sees their own pending image via my_posts.
    and (not p.has_image or pi.storage_path is not null)
    and not exists (
      select 1 from public.blocks b
       where b.blocker_id = auth.uid() and b.blocked_id = p.user_id
    );

------------------------------------------------------------
-- 3. admin_list_pending_images — FIFO queue for moderators.
------------------------------------------------------------
create or replace function public.admin_list_pending_images(
  p_limit  int default 50,
  p_offset int default 0
) returns table (
  post_id           bigint,
  storage_path      text,
  body              text,
  tag               text,
  proximity         text,
  author_numeric_id int,
  byte_size         int,
  width             int,
  height            int,
  created_at        timestamptz
)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public._is_admin(v_uid) then raise exception 'not_authorized'; end if;
  return query
    select pi.post_id,
           pi.storage_path,
           p.body,
           p.tag,
           p.proximity,
           pr.numeric_id,
           pi.byte_size,
           pi.width,
           pi.height,
           pi.created_at
      from public.post_images pi
      join public.posts p on p.id = pi.post_id
      join public.profiles pr on pr.id = pi.user_id
     where pi.status = 'pending_review'
     order by pi.created_at asc        -- FIFO: oldest first
     limit greatest(0, p_limit) offset greatest(0, p_offset);
end;
$$;

------------------------------------------------------------
-- 4. admin_approve_image — flips the image to active so the
--    posts_feed view will start showing it.
------------------------------------------------------------
create or replace function public.admin_approve_image(
  p_post_id bigint,
  p_note    text default null
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
begin
  if not public._is_admin(v_uid) then raise exception 'not_authorized'; end if;
  update public.post_images
     set status = 'active', moderated_at = now()
   where post_id = p_post_id
     and status = 'pending_review'
   returning user_id into v_owner;
  if v_owner is null then raise exception 'image_not_pending'; end if;

  perform public._admin_audit(
    v_uid, 'approve_image', 'post', p_post_id, v_owner, p_note, null
  );
end;
$$;

------------------------------------------------------------
-- 5. admin_reject_image — flips the image to removed and also
--    soft-removes the parent post so the user-visible body
--    disappears alongside the photo. (Otherwise a rejected image
--    would leave a text post with no image, which is confusing.)
------------------------------------------------------------
create or replace function public.admin_reject_image(
  p_post_id bigint,
  p_reason  text
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_storage_path text;
begin
  if not public._is_admin(v_uid) then raise exception 'not_authorized'; end if;
  if coalesce(length(p_reason), 0) < 3 then
    raise exception 'reason_required';
  end if;

  update public.post_images
     set status = 'removed', moderated_at = now()
   where post_id = p_post_id
     and status = 'pending_review'
   returning user_id, storage_path into v_owner, v_storage_path;
  if v_owner is null then raise exception 'image_not_pending'; end if;

  update public.posts set status = 'removed' where id = p_post_id;

  perform public._admin_audit(
    v_uid, 'reject_image', 'post', p_post_id, v_owner, p_reason,
    jsonb_build_object('storage_path', v_storage_path)
  );
end;
$$;

------------------------------------------------------------
-- 6. Grants — admin RPCs go to authenticated only; the internal
--    _is_admin gate inside each one keeps non-admins locked out.
------------------------------------------------------------
revoke execute on function public.admin_list_pending_images(int, int) from public, anon;
revoke execute on function public.admin_approve_image(bigint, text)   from public, anon;
revoke execute on function public.admin_reject_image(bigint, text)    from public, anon;

grant execute on function public.admin_list_pending_images(int, int) to authenticated;
grant execute on function public.admin_approve_image(bigint, text)   to authenticated;
grant execute on function public.admin_reject_image(bigint, text)    to authenticated;
