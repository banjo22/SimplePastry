-- Run once after 004_product_reorder.sql for drag-and-drop ordering.
begin;

create or replace function public.pantry_move_product(request_id uuid, product_id uuid, before_product_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare from_order integer; target_order integer; max_order integer;
begin
 if not public.is_household() then raise exception 'Kein autorisierter Haushaltszugang.'; end if;
 if request_id is null then raise exception 'Aktions-ID fehlt.'; end if;
 if exists(select 1 from public.command_receipts where id=request_id) then return; end if;
 select sort_order into from_order from public.products where id=product_id for update;
 if from_order is null then raise exception 'Produkt nicht gefunden.'; end if;
 if before_product_id is null then
  select coalesce(max(sort_order),0)+1 into target_order from public.products;
 else
  select sort_order into target_order from public.products where id=before_product_id for update;
  if target_order is null then raise exception 'Zielprodukt nicht gefunden.'; end if;
 end if;
 if target_order>from_order then target_order:=target_order-1; end if;
 update public.products set sort_order=sort_order+1 where sort_order>=target_order and sort_order<from_order;
 update public.products set sort_order=sort_order-1 where sort_order<=target_order and sort_order>from_order;
 update public.products set sort_order=target_order where id=product_id;
 insert into public.command_receipts(id) values(request_id);
end$$;

revoke all on function public.pantry_move_product(uuid,uuid,uuid) from public,anon;
grant execute on function public.pantry_move_product(uuid,uuid,uuid) to authenticated;
commit;
