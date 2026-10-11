-- Optional category filter for the collection.

drop function public.list_ideas(integer, timestamptz, uuid);

create function public.list_ideas(
  p_limit integer,
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_category text default null
) returns setof public.ideas
language sql stable security invoker set search_path = ''
as $$
  select * from public.ideas i
  where i.owner_id = (select auth.uid())
    and (p_category is null or i.category = p_category)
    and (p_before_created_at is null
         or (i.created_at, i.id) < (p_before_created_at, p_before_id))
  order by i.created_at desc, i.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 101)
$$;

revoke all on function public.list_ideas(integer, timestamptz, uuid, text) from public, anon;
grant execute on function public.list_ideas(integer, timestamptz, uuid, text) to authenticated;
