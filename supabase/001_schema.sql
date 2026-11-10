-- Run once in the Supabase SQL editor. Then configure household_access (README).
begin;
create table public.household_access(singleton boolean primary key default true check(singleton), user_id uuid not null unique references auth.users(id));
create table public.locations(id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 1 and 100),sort_order integer not null default 0);
create unique index locations_name on public.locations(lower(name));
create table public.groups(id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 1 and 100),sort_order integer not null default 0);
create unique index groups_name on public.groups(lower(name));
create table public.products(id uuid primary key default gen_random_uuid(),name text not null check(length(trim(name)) between 1 and 150),default_location_id uuid not null references public.locations(id) on delete restrict,group_id uuid references public.groups(id) on delete set null,group_ids uuid[] not null default '{}',note text not null default '' check(length(note)<=1000),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create unique index products_name on public.products(lower(name));
create index products_location on public.products(default_location_id);
create index products_group on public.products(group_id);
create index products_groups on public.products using gin(group_ids);
update public.products set group_ids=array[group_id] where group_id is not null and cardinality(group_ids)=0;
create table public.stock(product_id uuid primary key references public.products(id) on delete cascade,location_id uuid not null references public.locations(id) on delete restrict,quantity integer not null default 0 check(quantity between 0 and 1000000));
create index stock_location on public.stock(location_id);
create table public.shopping(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id) on delete cascade,quantity integer not null check(quantity between 1 and 1000000),note text not null default '' check(length(note)<=1000),done boolean not null default false,stock_applied boolean not null default false,created_at timestamptz not null default now());
create unique index shopping_one_active on public.shopping(product_id) where not done;
create index shopping_product on public.shopping(product_id);
create table public.command_receipts(id uuid primary key,created_at timestamptz not null default now());

create function public.is_household() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.household_access where user_id=(select auth.uid()))$$;
revoke all on function public.is_household() from public,anon;
grant execute on function public.is_household() to authenticated;
alter table public.household_access enable row level security;
alter table public.command_receipts enable row level security;
do $$declare t text;begin foreach t in array array['locations','groups','products','stock','shopping'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('create policy household_read on public.%I for select to authenticated using ((select public.is_household()))',t);
 execute format('revoke all on public.%I from anon, authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
end loop;end$$;
revoke all on public.household_access,public.command_receipts from anon,authenticated;

create function public.pantry_snapshot() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not public.is_household() then raise exception 'Kein autorisierter Haushaltszugang.';end if;
 return jsonb_build_object('locations',coalesce((select jsonb_agg(x order by sort_order,name) from public.locations x),'[]'),'groups',coalesce((select jsonb_agg(x order by sort_order,name) from public.groups x),'[]'),'products',coalesce((select jsonb_agg(x order by created_at,id) from public.products x),'[]'),'stock',coalesce((select jsonb_agg(x) from public.stock x),'[]'),'shopping',coalesce((select jsonb_agg(x order by created_at,id) from public.shopping x),'[]'));
end$$;

-- All mutations take one household lock. This deliberately serializes this small
-- private household's writes, including checkout, movement and metadata deletion.
create function public.pantry_command(request_id uuid,command jsonb) returns void language plpgsql security definer set search_path='' as $$
declare op text:=command->>'op'; target uuid:=(command->>'id')::uuid; p jsonb; item public.shopping%rowtype; n integer; loc uuid; tab text;
begin
 if not public.is_household() then raise exception 'Kein autorisierter Haushaltszugang.';end if;
 perform 1 from public.household_access where singleton for update;
 if request_id is null then raise exception 'Aktions-ID fehlt.';end if;
 if exists(select 1 from public.command_receipts where id=request_id) then return;end if;
 case op
 when 'quantity' then
  n:=(command->>'delta')::integer;if n is null or n not in (-1,1) then raise exception 'Ungültige Mengenänderung.';end if;
  select default_location_id into strict loc from public.products where id=target;
  insert into public.stock(product_id,location_id,quantity) values(target,loc,greatest(0,n)) on conflict(product_id) do update set quantity=greatest(0,stock.quantity+n),location_id=case when stock.quantity=0 then loc else stock.location_id end;
 when 'move' then
  update public.stock set location_id=(command->>'location_id')::uuid where product_id=target;
  if not found then raise exception 'Bestand nicht gefunden.';end if;
 when 'product' then
  p:=command->'product';target:=(p->>'id')::uuid;
  if exists(select 1 from public.products where id=target) then
   update public.products set name=trim(p->>'name'),default_location_id=(p->>'default_location_id')::uuid,group_id=(select value::uuid from jsonb_array_elements_text(coalesce(p->'group_ids','[]')) value limit 1),group_ids=coalesce((select array_agg(value::uuid) from jsonb_array_elements_text(coalesce(p->'group_ids','[]')) value),'{}'),note=coalesce(p->>'note',''),updated_at=now() where id=target;
  else
   insert into public.products(id,name,default_location_id,group_id,group_ids,note) values(target,trim(p->>'name'),(p->>'default_location_id')::uuid,(select value::uuid from jsonb_array_elements_text(coalesce(p->'group_ids','[]')) value limit 1),coalesce((select array_agg(value::uuid) from jsonb_array_elements_text(coalesce(p->'group_ids','[]')) value),'{}'),coalesce(p->>'note',''));
   n:=coalesce((command->>'initial')::integer,0);if n<0 or n>1000000 then raise exception 'Ungültige Anfangsmenge.';end if;
   if n>0 then insert into public.stock(product_id,location_id,quantity) values(target,(p->>'default_location_id')::uuid,n);end if;
  end if;
 when 'delete_product' then
  if exists(select 1 from public.stock where product_id=target and quantity>0) or exists(select 1 from public.shopping where product_id=target and not done) then raise exception 'Zuerst den Bestand aufbrauchen und aktive Einkäufe abschließen.';end if;
  delete from public.products where id=target;
 when 'shopping' then
  n:=(command->>'quantity')::integer;
  insert into public.shopping(product_id,quantity,note) values(target,n,coalesce(command->>'note','')) on conflict(product_id) where not done do update set quantity=excluded.quantity,note=excluded.note;
 when 'complete' then
  select * into strict item from public.shopping where id=target for update;
  if not item.done then
   if coalesce((command->>'add')::boolean,false) and not item.stock_applied then
    n:=(command->>'quantity')::integer;if n is null or n<1 or n>1000000 then raise exception 'Ungültige Einkaufsmenge.';end if;
    select default_location_id into strict loc from public.products where id=item.product_id;
    insert into public.stock(product_id,location_id,quantity) values(item.product_id,loc,n) on conflict(product_id) do update set quantity=stock.quantity+n,location_id=case when stock.quantity=0 then loc else stock.location_id end;
    update public.shopping set stock_applied=true where id=target;
   end if;
   update public.shopping set done=true where id=target;
  end if;
 when 'undo' then
  if exists(select 1 from public.shopping a join public.shopping b on a.product_id=b.product_id where a.id=target and b.id<>target and not b.done) then raise exception 'Dieses Produkt steht bereits auf der Einkaufsliste.';end if;
  update public.shopping set done=false where id=target;
 when 'delete_shopping' then delete from public.shopping where id=target;
 when 'named' then
  tab:=command->>'table';if tab not in ('locations','groups') then raise exception 'Ungültige Auswahl.';end if;
  execute format('insert into public.%I(id,name,sort_order) values($1,$2,coalesce((select max(sort_order)+1 from public.%I),0)) on conflict(id) do update set name=excluded.name',tab,tab) using target,trim(command->>'name');
 when 'reorder_named' then
  tab:=command->>'table';if tab not in ('locations','groups') then raise exception 'Ungültige Auswahl.';end if;
  execute format('update public.%I set sort_order=sort_order+$2 where id=$1',tab) using target,case when (command->>'direction')::integer<0 then -1 else 1 end;
 when 'delete_named' then
  tab:=command->>'table';if tab not in ('locations','groups') then raise exception 'Ungültige Auswahl.';end if;
  -- Empty stock records carry no location meaning; active stock and defaults remain protected by FKs.
  if tab='locations' then delete from public.stock where location_id=target and quantity=0;end if;
  execute format('delete from public.%I where id=$1',tab) using target;
 else raise exception 'Unbekannte Aktion.';
 end case;
 insert into public.command_receipts(id) values(request_id);
end$$;
revoke all on function public.pantry_command(uuid,jsonb),public.pantry_snapshot() from public,anon;
grant execute on function public.pantry_command(uuid,jsonb),public.pantry_snapshot() to authenticated;
insert into public.locations(name) values('Kühlschrank'),('Gefrierschrank'),('Vorratsschrank'),('Obstkorb');
insert into public.groups(name) values('Aufschnitt'),('Milchprodukte'),('Brotaufstrich'),('Getränke');
alter publication supabase_realtime add table public.locations,public.groups,public.products,public.stock,public.shopping;
commit;
