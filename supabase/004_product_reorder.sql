-- Run once after the existing Supabase migrations.
begin;

alter table public.products add column if not exists sort_order integer not null default 0;
with ranked as (
  select id, row_number() over(order by created_at, id)-1 as n
  from public.products
)
update public.products p set sort_order=ranked.n from ranked where ranked.id=p.id;

create or replace function public.set_product_sort_order() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.sort_order=0 and exists(select 1 from public.products) then
  new.sort_order:=(select coalesce(max(sort_order)+1,0) from public.products);
 end if;
 return new;
end$$;
drop trigger if exists products_sort_order on public.products;
create trigger products_sort_order before insert on public.products
for each row execute function public.set_product_sort_order();

create or replace function public.pantry_snapshot() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_household() then raise exception 'Kein autorisierter Haushaltszugang.'; end if;
 return jsonb_build_object(
  'locations',coalesce((select jsonb_agg(x order by sort_order,name) from public.locations x),'[]'),
  'groups',coalesce((select jsonb_agg(x order by sort_order,name) from public.groups x),'[]'),
  'products',coalesce((select jsonb_agg(x order by sort_order,name,id) from public.products x),'[]'),
  'stock',coalesce((select jsonb_agg(x) from public.stock x),'[]'),
  'shopping',coalesce((select jsonb_agg(x order by created_at,id) from public.shopping x),'[]')
 );
end$$;

create or replace function public.pantry_reorder_product(request_id uuid, product_id uuid, direction integer)
returns void language plpgsql security definer set search_path='' as $$
declare current_order integer; neighbor_id uuid; neighbor_order integer; step integer;
begin
 if not public.is_household() then raise exception 'Kein autorisierter Haushaltszugang.'; end if;
 if direction not in (-1,1) then raise exception 'Ungültige Sortierrichtung.'; end if;
 if request_id is null then raise exception 'Aktions-ID fehlt.'; end if;
 if exists(select 1 from public.command_receipts where id=request_id) then return; end if;
 select sort_order into current_order from public.products where id=product_id for update;
 if current_order is null then raise exception 'Produkt nicht gefunden.'; end if;
 step:=case when direction<0 then -1 else 1 end;
 select id,sort_order into neighbor_id,neighbor_order from public.products
  where (step<0 and sort_order<current_order) or (step>0 and sort_order>current_order)
  order by case when step<0 then sort_order end desc, case when step>0 then sort_order end asc limit 1 for update;
 if neighbor_id is not null then
  update public.products set sort_order=neighbor_order where id=product_id;
  update public.products set sort_order=current_order where id=neighbor_id;
 end if;
 insert into public.command_receipts(id) values(request_id);
end$$;

revoke all on function public.pantry_reorder_product(uuid,uuid,integer) from public,anon;
grant execute on function public.pantry_reorder_product(uuid,uuid,integer) to authenticated;
commit;
