-- Task 003: manual ideas with an optional exact text source.
--
-- Every row is owned by the Supabase Auth user that created it. The API acts as
-- that user (user token, security-invoker functions), so row-level security,
-- column grants, constraints and triggers below are the authoritative rules for
-- both the API and direct Data API callers. No privileged runtime path exists.
--
-- Text rules shared with the API and the app (contracts/idea_validation_cases.json):
-- lengths count Unicode code points; "trimmed" means no leading or trailing
-- character from the explicit whitespace set in app_private.is_trimmed.

create schema app_private;
comment on schema app_private is
  'Helpers and bookkeeping for public functions; not exposed through the Data API.';
revoke all on schema app_private from public;
grant usage on schema app_private to authenticated;

-- Whitespace set: U+0009-000D, U+0020, U+0085, U+00A0, U+1680, U+2000-200A,
-- U+2028, U+2029, U+202F, U+205F, U+3000, U+FEFF.
create function app_private.is_trimmed(value text) returns boolean
language sql immutable strict parallel safe set search_path = ''
as $$
  select value !~ '^[\u0009-\u000D \u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]'
     and value !~ '[\u0009-\u000D \u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]$'
$$;

create function app_private.has_text(value text) returns boolean
language sql immutable strict parallel safe set search_path = ''
as $$
  select value ~ '[^\u0009-\u000D \u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]'
$$;

-- Optional canonical text: null, or trimmed with 1..max_length code points.
create function app_private.is_optional_text(value text, max_length integer) returns boolean
language sql immutable parallel safe set search_path = ''
as $$
  select value is null
      or (char_length(value) between 1 and max_length and app_private.is_trimmed(value))
$$;

-- At most 20 tags, each trimmed with 1..50 code points, no case-insensitive duplicates.
create function app_private.are_valid_tags(tags text[]) returns boolean
language sql immutable strict parallel safe set search_path = ''
as $$
  select coalesce(array_ndims(tags), 1) = 1
     and cardinality(tags) <= 20
     and array_position(tags, null) is null
     and not exists (
       select 1 from unnest(tags) as tag
       where char_length(tag) not between 1 and 50 or not app_private.is_trimmed(tag)
     )
     and (select count(distinct lower(tag)) from unnest(tags) as tag) = cardinality(tags)
$$;

revoke all on all functions in schema app_private from public;
grant execute on all functions in schema app_private to authenticated;

-- --- ideas ------------------------------------------------------------------

create table public.ideas (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null,
  description text,
  notes text,
  location text,
  category text,
  tags text[] not null default '{}',
  status text not null default 'saved',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  constraint ideas_id_owner_key unique (id, owner_id),
  constraint ideas_title_check
    check (char_length(title) between 1 and 200 and app_private.is_trimmed(title)),
  constraint ideas_description_check check (app_private.is_optional_text(description, 10000)),
  constraint ideas_notes_check check (app_private.is_optional_text(notes, 10000)),
  constraint ideas_location_check check (app_private.is_optional_text(location, 300)),
  constraint ideas_category_check check (
    category in (
      'food', 'activity', 'travel', 'film-series', 'recipe', 'product', 'book', 'place', 'other'
    )
  ),
  constraint ideas_tags_check check (app_private.are_valid_tags(tags)),
  constraint ideas_status_check check (status in ('saved', 'done')),
  constraint ideas_version_check check (version >= 1),
  constraint ideas_timestamps_check check (updated_at >= created_at)
);

create index ideas_owner_created_idx on public.ideas (owner_id, created_at desc, id desc);

-- Identity is immutable; every successful edit increments the version and
-- advances updated_at. Clients cannot write these columns (see grants).
create function app_private.ideas_before_update() returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.id is distinct from old.id
     or new.owner_id is distinct from old.owner_id
     or new.created_at is distinct from old.created_at then
    raise exception 'idea identity is immutable' using errcode = '42501';
  end if;
  new.version := old.version + 1;
  new.updated_at := greatest(now(), old.updated_at);
  return new;
end
$$;

create trigger ideas_before_update
  before update on public.ideas
  for each row execute function app_private.ideas_before_update();

-- --- sources ----------------------------------------------------------------

-- Evidence a user supplied for an idea. Task 003 supports only exact text.
-- Original text and identity are immutable: clients have no UPDATE grant, and
-- sources are removed only together with their idea.
create table public.sources (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid(),
  idea_id uuid not null,
  kind text not null,
  original_text text,
  created_at timestamptz not null default now(),
  -- A source can only belong to an idea with the same owner.
  constraint sources_idea_owner_fkey foreign key (idea_id, owner_id)
    references public.ideas (id, owner_id) on delete cascade,
  constraint sources_kind_check check (kind = 'text'),
  constraint sources_text_check check (
    kind <> 'text'
    or (
      original_text is not null
      and char_length(original_text) between 1 and 20000
      and app_private.has_text(original_text)
    )
  )
);

create index sources_idea_owner_idx on public.sources (idea_id, owner_id);

-- --- create retries ---------------------------------------------------------

-- One row per create operation key, kept for 24 hours so a retried create
-- returns the original idea instead of a duplicate, and a retry after deletion
-- cannot recreate it. Holds no idea content: only a fingerprint and the ID.
create table app_private.idea_create_operations (
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  operation_key uuid not null,
  fingerprint text not null check (fingerprint ~ '^[0-9a-f]{64}$'),
  idea_id uuid not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours',
  primary key (owner_id, operation_key)
);

-- --- grants and row-level security ------------------------------------------

alter table public.ideas enable row level security;
alter table public.sources enable row level security;
alter table app_private.idea_create_operations enable row level security;

revoke all on public.ideas, public.sources, app_private.idea_create_operations
  from public, anon, authenticated, service_role;

-- Clients may write canonical fields only; ID, owner, timestamps and version
-- come from defaults and the trigger.
grant select, delete on public.ideas to authenticated;
grant insert (title, description, notes, location, category, tags, status) on public.ideas
  to authenticated;
grant update (title, description, notes, location, category, tags, status) on public.ideas
  to authenticated;
grant select on public.sources to authenticated;
grant insert (idea_id, kind, original_text) on public.sources to authenticated;
grant select, delete on app_private.idea_create_operations to authenticated;
grant insert (operation_key, fingerprint, idea_id) on app_private.idea_create_operations
  to authenticated;

create policy ideas_select_own on public.ideas for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy ideas_insert_own on public.ideas for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy ideas_update_own on public.ideas for update to authenticated
  using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy ideas_delete_own on public.ideas for delete to authenticated
  using ((select auth.uid()) = owner_id);

create policy sources_select_own on public.sources for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy sources_insert_own on public.sources for insert to authenticated
  with check ((select auth.uid()) = owner_id);

create policy operations_select_own on app_private.idea_create_operations
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy operations_insert_own on app_private.idea_create_operations
  for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy operations_delete_own on app_private.idea_create_operations
  for delete to authenticated using ((select auth.uid()) = owner_id);

-- --- functions --------------------------------------------------------------

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
  p_status text default 'saved',
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
    'status', p_status, 'original_text', p_original_text
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
    insert into public.ideas (title, description, notes, location, category, tags, status)
      values (p_title, p_description, p_notes, p_location, p_category, p_tags, p_status)
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

-- One page of the caller's ideas, newest first; pass the last row's
-- (created_at, id) to continue after it.
create function public.list_ideas(
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

revoke all on function public.create_idea(uuid, text, text, text, text, text, text[], text, text)
  from public, anon;
revoke all on function public.list_ideas(integer, timestamptz, uuid) from public, anon;
grant execute on function public.create_idea(uuid, text, text, text, text, text, text[], text, text)
  to authenticated;
grant execute on function public.list_ideas(integer, timestamptz, uuid) to authenticated;
