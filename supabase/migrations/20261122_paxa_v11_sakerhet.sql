-- PaxaListan v1.1: säkerhetsrättningar (2026-11-22)
-- 1. Gästens id är nu en hemlig nyckel i klienten. Databasen sparar bara sha256-hashen,
--    och svaren visar bara de första 12 tecknen av hashen plus mine=true/false.
-- 2. Atomär paxning (ingen dubbelpaxning).
-- 3. Mottagaren får inga paxrelaterade händelser alls och inga gäst-id.
-- 4. Händelser sparar item_id i stället för en kopia av bilden.
-- 5. paxa_move_item flyttar bara paxningar i rätt lista.
-- 6. Kvot för AI-anrop per lista och per IP (paxa_ai_allow).

create or replace function public.paxa_gh(p text) returns text
language sql immutable set search_path to 'public' as $$
  select case when p is null or p = '' then null else encode(sha256(convert_to(p,'UTF8')),'hex') end $$;
revoke all on function public.paxa_gh(text) from public, anon, authenticated;

-- befintliga råa gäst-id blir hashar (körs en gång; hashar är 64 hex-tecken)
update public.paxa_items set created_by = public.paxa_gh(created_by) where created_by is not null and created_by !~ '^[0-9a-f]{64}$';
update public.paxa_pax set guest_id = public.paxa_gh(guest_id) where guest_id !~ '^[0-9a-f]{64}$';
update public.paxa_events set guest_id = public.paxa_gh(guest_id) where guest_id is not null and guest_id !~ '^[0-9a-f]{64}$';

alter table public.paxa_events add column if not exists item_id uuid;
update public.paxa_events set thumb = null where thumb is not null;

create table if not exists public.paxa_ai_use (k text not null, d date not null default current_date, n int not null default 0, primary key (k,d));
alter table public.paxa_ai_use enable row level security;

create or replace function public.paxa_event(p_list uuid, p_t text, p_guest_hash text, p_name text, p_item text, p_item_id uuid, p_extra text default null)
returns void language sql security definer set search_path to 'public' as $$
  insert into public.paxa_events(list_id,t,guest_id,guest_name,item_name,item_id,extra) values (p_list,p_t,p_guest_hash,p_name,p_item,p_item_id,p_extra);
  delete from public.paxa_events where list_id = p_list and id not in (select id from public.paxa_events where list_id = p_list order by id desc limit 60);
$$;
revoke all on function public.paxa_event(uuid,text,text,text,text,uuid,text) from public, anon, authenticated;
drop function if exists public.paxa_event(uuid,text,text,text,text,text,text);

drop function if exists public.paxa_get_list(text);
create or replace function public.paxa_get_list(p_token text, p_guest text default null)
returns json language plpgsql security definer set search_path to 'public' as $function$
declare v_list uuid; v_role text; l public.paxa_lists; res json; g text := public.paxa_gh(p_guest); rec boolean;
begin
  select * into v_list, v_role from public.paxa_role(p_token);
  if v_list is null then return null; end if;
  rec := v_role = 'recipient';
  select * into l from public.paxa_lists where id = v_list;
  select json_build_object(
    'role', v_role,
    'list', json_build_object('id',l.id,'name',l.name,'recipient',l.recipient,'occasion',l.occasion,'date',l.date,'kid',l.kid,'created_at',l.created_at),
    'tokens', case when v_role='owner' then json_build_object('owner',l.owner_token,'guest',l.guest_token,'view',l.view_token) else null end,
    'items', coalesce((select json_agg(json_build_object('id',i.id,'name',i.name,'price',i.price,'was',i.was,'shop',i.shop,'url',i.url,'note',i.note,'cat',i.cat,'prio',i.prio,'thumb',i.thumb,'img',i.img,
               'by', case when rec then null else left(i.created_by,12) end,'mine', i.created_by = g,'by_name',i.created_by_name,'at',extract(epoch from i.created_at)*1000) order by i.created_at desc, i.id)
             from public.paxa_items i where i.list_id = v_list), '[]'::json),
    'pax', case when rec then '[]'::json else coalesce((select json_agg(json_build_object('item_id',p.item_id,'by',left(p.guest_id,12),'mine',p.guest_id = g,'by_name',p.guest_name,'st',p.st,'at',extract(epoch from p.created_at)*1000))
             from public.paxa_pax p where p.list_id = v_list), '[]'::json) end,
    'events', coalesce((select json_agg(json_build_object('id',e.id,'t',e.t,'by', case when rec then null else left(e.guest_id,12) end,'mine',e.guest_id = g,'by_name',e.guest_name,'name',e.item_name,'item',e.item_id,'extra',e.extra,'at',extract(epoch from e.created_at)*1000) order by e.id desc)
             from (select * from public.paxa_events where list_id = v_list and not (rec and t in ('pax','unpax','st')) order by id desc limit 40) e), '[]'::json)
  ) into res;
  return res;
end $function$;

create or replace function public.paxa_add_item(p_token text, p_guest text, p_guest_name text, p_name text, p_price numeric, p_shop text, p_url text, p_note text, p_cat text, p_prio boolean, p_thumb text, p_img text)
returns json language plpgsql security definer set search_path to 'public' as $function$
declare v_list uuid; v_role text; r public.paxa_items; n int; g text := public.paxa_gh(p_guest);
begin
  select * into v_list, v_role from public.paxa_role(p_token);
  if v_list is null then raise exception 'not_allowed'; end if;
  if g is null then raise exception 'guest_required'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'name_required'; end if;
  select count(*) into n from public.paxa_items where list_id = v_list;
  if n >= 300 then raise exception 'list_full'; end if;
  if length(coalesce(p_thumb,'')) > 120000 then raise exception 'thumb_too_big'; end if;
  insert into public.paxa_items(list_id,name,price,shop,url,note,cat,prio,thumb,img,created_by,created_by_name)
  values (v_list, left(trim(p_name),80), p_price, nullif(left(trim(p_shop),60),''), nullif(left(p_url,500),''), nullif(left(trim(p_note),200),''), nullif(left(p_cat,30),''), coalesce(p_prio,false), p_thumb, nullif(left(p_img,500),''), g, left(p_guest_name,40))
  returning * into r;
  perform public.paxa_event(v_list,'add',g,left(p_guest_name,40),r.name,r.id);
  return json_build_object('id',r.id,'at',extract(epoch from r.created_at)*1000);
end $function$;

create or replace function public.paxa_update_item(p_token text, p_guest text, p_item uuid, p_name text, p_price numeric, p_shop text, p_url text, p_note text, p_cat text, p_prio boolean)
returns boolean language plpgsql security definer set search_path to 'public' as $function$
declare v_list uuid; v_role text; i public.paxa_items; g text := public.paxa_gh(p_guest);
begin
  select * into v_list, v_role from public.paxa_role(p_token);
  select * into i from public.paxa_items where id = p_item and list_id = v_list;
  if i.id is null then raise exception 'not_found'; end if;
  if v_role is distinct from 'owner' and i.created_by is distinct from g then raise exception 'not_allowed'; end if;
  update public.paxa_items set name = coalesce(nullif(left(trim(p_name),80),''), name),
    was = case when p_price is distinct from price and price is not null and p_price is not null and p_price < price then price else was end,
    price = p_price, shop = nullif(left(trim(p_shop),60),''), url = nullif(left(p_url,500),''), note = nullif(left(trim(p_note),200),''),
    cat = nullif(left(p_cat,30),''), prio = coalesce(p_prio,false) where id = p_item;
  return true;
end $function$;

create or replace function public.paxa_delete_item(p_token text, p_guest text, p_guest_name text, p_item uuid)
returns boolean language plpgsql security definer set search_path to 'public' as $function$
declare v_list uuid; v_role text; i public.paxa_items; g text := public.paxa_gh(p_guest);
begin
  select * into v_list, v_role from public.paxa_role(p_token);
  select * into i from public.paxa_items where id = p_item and list_id = v_list;
  if i.id is null then return false; end if;
  if v_role is distinct from 'owner' and i.created_by is distinct from g then raise exception 'not_allowed'; end if;
  delete from public.paxa_pax where item_id = p_item and list_id = v_list;
  delete from public.paxa_items where id = p_item;
  perform public.paxa_event(v_list,'del',g,left(p_guest_name,40),i.name,null);
  return true;
end $function$;

create or replace function public.paxa_move_item(p_token text, p_item uuid, p_to_token text)
returns boolean language plpgsql security definer set search_path to 'public' as $function$
declare v_list uuid; v_role text; t_list uuid; t_role text; n int;
begin
  select * into v_list, v_role from public.paxa_role(p_token);
  select * into t_list, t_role from public.paxa_role(p_to_token);
  if v_role is distinct from 'owner' or t_role is distinct from 'owner' then raise exception 'not_allowed'; end if;
  update public.paxa_items set list_id = t_list where id = p_item and list_id = v_list;
  get diagnostics n = row_count;
  if n = 0 then return false; end if;
  update public.paxa_pax set list_id = t_list where item_id = p_item and list_id = v_list;
  return true;
end $function$;

create or replace function public.paxa_set_pax(p_token text, p_guest text, p_guest_name text, p_item uuid, p_on boolean)
returns json language plpgsql security definer set search_path to 'public' as $function$
declare v_list uuid; v_role text; i public.paxa_items; g text := public.paxa_gh(p_guest); v_ins uuid; v_who text; n int;
begin
  select * into v_list, v_role from public.paxa_role(p_token);
  if v_list is null or v_role = 'recipient' then raise exception 'not_allowed'; end if;
  if g is null then raise exception 'guest_required'; end if;
  select * into i from public.paxa_items where id = p_item and list_id = v_list;
  if i.id is null then raise exception 'not_found'; end if;
  if p_on then
    insert into public.paxa_pax(item_id,list_id,guest_id,guest_name) values (p_item,v_list,g,left(p_guest_name,40))
    on conflict (item_id) do nothing returning item_id into v_ins;
    if v_ins is null then
      select guest_id into v_who from public.paxa_pax where item_id = p_item;
      if v_who = g then return json_build_object('ok',true); end if;
      return json_build_object('ok',false,'reason','taken');
    end if;
    perform public.paxa_event(v_list,'pax',g,left(p_guest_name,40),i.name,i.id);
  else
    if v_role = 'owner' then delete from public.paxa_pax where item_id = p_item and list_id = v_list;
    else delete from public.paxa_pax where item_id = p_item and list_id = v_list and guest_id = g; end if;
    get diagnostics n = row_count;
    if n = 0 then
      if exists(select 1 from public.paxa_pax where item_id = p_item) then raise exception 'not_allowed'; end if;
      return json_build_object('ok',true);
    end if;
    perform public.paxa_event(v_list,'unpax',g,left(p_guest_name,40),i.name,i.id);
  end if;
  return json_build_object('ok',true);
end $function$;

create or replace function public.paxa_set_pax_status(p_token text, p_guest text, p_guest_name text, p_item uuid, p_st smallint)
returns boolean language plpgsql security definer set search_path to 'public' as $function$
declare v_list uuid; v_role text; i public.paxa_items; g text := public.paxa_gh(p_guest); n int;
begin
  select * into v_list, v_role from public.paxa_role(p_token);
  update public.paxa_pax set st = greatest(0, least(2, p_st)) where item_id = p_item and list_id = v_list and guest_id = g;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not_allowed'; end if;
  if p_st > 0 then
    select * into i from public.paxa_items where id = p_item;
    perform public.paxa_event(v_list,'st',g,left(p_guest_name,40),i.name,i.id, case when p_st=1 then 'köpt' else 'inslagen' end);
  end if;
  return true;
end $function$;

-- AI-kvot: kräver giltig länk. Högst 60 anrop per lista och dygn, 40 per IP och dygn.
create or replace function public.paxa_ai_allow(p_token text, p_ip text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare v_list uuid; v_role text; nl int; ni int;
begin
  select * into v_list, v_role from public.paxa_role(p_token);
  if v_list is null then return 'bad_token'; end if;
  delete from public.paxa_ai_use where d < current_date - 2;
  insert into public.paxa_ai_use(k,d,n) values ('l:'||v_list, current_date, 1) on conflict (k,d) do update set n = paxa_ai_use.n + 1 returning n into nl;
  insert into public.paxa_ai_use(k,d,n) values ('i:'||coalesce(public.paxa_gh(p_ip),'?'), current_date, 1) on conflict (k,d) do update set n = paxa_ai_use.n + 1 returning n into ni;
  if nl > 60 then return 'list_limit'; end if;
  if ni > 40 then return 'ip_limit'; end if;
  return 'ok';
end $function$;

revoke all on function public.paxa_get_list(text,text), public.paxa_ai_allow(text,text) from public;
grant execute on function public.paxa_get_list(text,text), public.paxa_ai_allow(text,text) to anon, authenticated;
