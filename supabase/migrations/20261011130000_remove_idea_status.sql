-- Owner decision (2026-10-11): ideas are not marked done. Removes the status
-- column (its check constraint and column grants go with it) and the status
-- argument of create_idea. Existing ideas are kept.
--
-- Retry fingerprints no longer include status, so retrying a create that was
-- first sent before this migration (within its 24-hour window) gets
-- operation_key_reused instead of the earlier idea.

drop function public.create_idea(uuid, text, text, text, text, text, text[], text, text);

alter table public.ideas drop column status;

-- Creates an idea and its optional text source in one transaction, or returns
-- the idea an earlier call with the same operation key created.
--
-- Errors (SQLSTATE PT409, returned by the Data API as HTTP 409):
--   operation_key_reused  same key, different content
--   idea_deleted          the key's idea was deleted; it is never recreated
-- The key can be reused for a new idea once its record expires (24 hours).
create function public.create_idea(
  p_operation_key uuid,
  p_title text,
  p_description text default null,
  p_notes text default null,
  p_location text default null,
  p_category text default null,
  p_tags text[] default '{}',
  p_original_text text default null
) returns jsonb
language plpgsql volatile security invoker set search_path = ''
as $$
declare
  v_owner uuid := auth.uid();
  v_fingerprint text;
  v_operation app_private.idea_create_operations;
  v_idea_id uuid;
  v_created boolean := false;
  v_idea jsonb;
begin
  if v_owner is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_operation_key is null then
    raise exception 'operation key required' using errcode = '22004';
  end if;

  v_fingerprint := encode(sha256(convert_to(jsonb_build_object(
    'title', p_title, 'description', p_description, 'notes', p_notes,
    'location', p_location, 'category', p_category, 'tags', to_jsonb(p_tags),
    'original_text', p_original_text
  )::text, 'UTF8')), 'hex');

  -- Serialises concurrent calls with the same key; the primary key backs it up.
  perform pg_advisory_xact_lock(hashtextextended(v_owner::text || '/' || p_operation_key::text, 0));
  delete from app_private.idea_create_operations
    where owner_id = v_owner and expires_at <= now();

  select * into v_operation from app_private.idea_create_operations
    where owner_id = v_owner and operation_key = p_operation_key;

  if found then
    if v_operation.fingerprint <> v_fingerprint then
      raise exception 'operation_key_reused' using errcode = 'PT409';
    end if;
    v_idea_id := v_operation.idea_id;
  else
    insert into public.ideas (title, description, notes, location, category, tags)
      values (p_title, p_description, p_notes, p_location, p_category, p_tags)
      returning id into v_idea_id;
    if p_original_text is not null then
      insert into public.sources (idea_id, kind, original_text)
        values (v_idea_id, 'text', p_original_text);
    end if;
    insert into app_private.idea_create_operations (operation_key, fingerprint, idea_id)
      values (p_operation_key, v_fingerprint, v_idea_id);
    v_created := true;
  end if;

  select to_jsonb(i) - 'owner_id' || jsonb_build_object('sources', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', s.id, 'kind', s.kind, 'original_text', s.original_text, 'created_at', s.created_at
        ) order by s.created_at, s.id)
      from public.sources s where s.idea_id = i.id and s.owner_id = v_owner
    ), '[]'::jsonb))
    into v_idea
    from public.ideas i where i.id = v_idea_id and i.owner_id = v_owner;

  if v_idea is null then
    raise exception 'idea_deleted' using errcode = 'PT409';
  end if;
  return jsonb_build_object('created', v_created, 'idea', v_idea);
end
$$;

-- Re-created so its row type matches the table without status.
create or replace function public.list_ideas(
  p_limit integer,
  p_before_created_at timestamptz default null,
  p_before_id uuid default null
) returns setof public.ideas
language sql stable security invoker set search_path = ''
as $$
  select * from public.ideas i
  where i.owner_id = (select auth.uid())
    and (p_before_created_at is null
         or (i.created_at, i.id) < (p_before_created_at, p_before_id))
  order by i.created_at desc, i.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 101)
$$;

revoke all on function public.create_idea(uuid, text, text, text, text, text, text[], text)
  from public, anon;
grant execute on function public.create_idea(uuid, text, text, text, text, text, text[], text)
  to authenticated;
