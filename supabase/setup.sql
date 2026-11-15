-- そなえ帳：家族共有のためのテーブルと関数
-- Supabase の SQL Editor に貼り付けて「Run」を押してください。

create table if not exists public.families (
  id uuid primary key,
  data jsonb not null default '{}'::jsonb,
  version bigint not null default 0,
  updated_at timestamptz not null default now()
);

-- テーブルへの直接アクセスは禁止（下の関数だけを通して読み書きする）
alter table public.families enable row level security;
revoke all on public.families from anon, authenticated;

-- 家族のデータを読む（招待リンクに入っているIDを知っている人だけが読める）
create or replace function public.sonae_get(fid uuid)
returns table(data jsonb, version bigint)
language sql security definer set search_path = public as $$
  select f.data, f.version from public.families f where f.id = fid;
$$;

-- 家族のデータを書く（他の人が先に更新していたら -1 を返し、アプリ側で合わせ直して再送する）
create or replace function public.sonae_put(fid uuid, new_data jsonb, base_version bigint)
returns bigint
language plpgsql security definer set search_path = public as $$
declare v bigint;
begin
  if octet_length(new_data::text) > 500000 then
    raise exception 'data too large';
  end if;
  insert into public.families as f (id, data, version)
    values (fid, new_data, 1)
  on conflict (id) do update
    set data = excluded.data, version = f.version + 1, updated_at = now()
    where f.version = base_version
  returning f.version into v;
  return coalesce(v, -1);
end;
$$;

grant execute on function public.sonae_get(uuid) to anon, authenticated;
grant execute on function public.sonae_put(uuid, jsonb, bigint) to anon, authenticated;
