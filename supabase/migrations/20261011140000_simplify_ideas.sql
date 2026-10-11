-- Simplification (owner decision 2026-10-11): the app is single-user on one
-- device, so edits are last-write-wins and creates are not deduplicated.
-- Removes create-retry records and the version column; existing ideas and
-- sources are kept.

drop function public.create_idea(uuid, text, text, text, text, text, text[], text);
drop table app_private.idea_create_operations;

alter table public.ideas drop constraint ideas_version_check;
alter table public.ideas drop column version;

-- Identity is immutable; every edit advances updated_at.
create or replace function app_private.ideas_before_update() returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.id is distinct from old.id
     or new.owner_id is distinct from old.owner_id
     or new.created_at is distinct from old.created_at then
    raise exception 'idea identity is immutable' using errcode = '42501';
  end if;
  new.updated_at := greatest(now(), old.updated_at);
  return new;
end
$$;

-- Creates an idea and its optional text source in one transaction.
create function public.create_idea(
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
  v_idea public.ideas;
  v_source public.sources;
begin
  insert into public.ideas (title, description, notes, location, category, tags)
    values (p_title, p_description, p_notes, p_location, p_category, p_tags)
    returning * into v_idea;
  if p_original_text is not null then
    insert into public.sources (idea_id, kind, original_text)
      values (v_idea.id, 'text', p_original_text)
      returning * into v_source;
  end if;
  return to_jsonb(v_idea) - 'owner_id' || jsonb_build_object(
    'sources',
    case when v_source.id is null then '[]'::jsonb
    else jsonb_build_array(jsonb_build_object(
      'id', v_source.id, 'kind', v_source.kind,
      'original_text', v_source.original_text, 'created_at', v_source.created_at))
    end
  );
end
$$;

-- Re-created so its row type matches the table without version.
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

revoke all on function public.create_idea(text, text, text, text, text, text[], text)
  from public, anon;
grant execute on function public.create_idea(text, text, text, text, text, text[], text)
  to authenticated;
