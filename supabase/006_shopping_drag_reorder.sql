-- Run once after the existing Supabase migrations for custom shopping order.
begin;
alter table public.shopping add column if not exists sort_order integer not null default 0;
with ranked as (select id,row_number() over(order by created_at,id)-1 as n from public.shopping)
update public.shopping s set sort_order=ranked.n from ranked where ranked.id=s.id;

create or replace function public.pantry_snapshot() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_household() then raise exception 'Kein autorisierter Haushaltszugang.'; end if;
 return jsonb_build_object('locations',coalesce((select jsonb_agg(x order by sort_order,name) from public.locations x),'[]'),'groups',coalesce((select jsonb_agg(x order by sort_order,name) from public.groups x),'[]'),'products',coalesce((select jsonb_agg(x order by sort_order,name,id) from public.products x),'[]'),'stock',coalesce((select jsonb_agg(x) from public.stock x),'[]'),'shopping',coalesce((select jsonb_agg(x order by sort_order,created_at,id) from public.shopping x),'[]'));
end$$;

create or replace function public.pantry_move_shopping(request_id uuid, shopping_id uuid, before_shopping_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare from_order integer; target_order integer;
begin
 if not public.is_household() then raise exception 'Kein autorisierter Haushaltszugang.'; end if;
 if request_id is null then raise exception 'Aktions-ID fehlt.'; end if;
 if exists(select 1 from public.command_receipts where id=request_id) then return; end if;
 select sort_order into from_order from public.shopping where id=shopping_id for update;
 if from_order is null then raise exception 'Einkauf nicht gefunden.'; end if;
 if before_shopping_id is null then select coalesce(max(sort_order),0)+1 into target_order from public.shopping;
 else select sort_order into target_order from public.shopping where id=before_shopping_id for update; if target_order is null then raise exception 'Zieleintrag nicht gefunden.'; end if; end if;
 if target_order>from_order then target_order:=target_order-1; end if;
 update public.shopping set sort_order=sort_order+1 where sort_order>=target_order and sort_order<from_order;
 update public.shopping set sort_order=sort_order-1 where sort_order<=target_order and sort_order>from_order;
 update public.shopping set sort_order=target_order where id=shopping_id;
 insert into public.command_receipts(id) values(request_id);
end$$;
revoke all on function public.pantry_move_shopping(uuid,uuid,uuid) from public,anon;
grant execute on function public.pantry_move_shopping(uuid,uuid,uuid) to authenticated;
commit;
