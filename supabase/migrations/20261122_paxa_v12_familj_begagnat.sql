-- PaxaListan v1.2 (2026-11-22): "Gärna begagnat" och samlingslänken ("Familjens jul").

alter table public.paxa_items add column if not exists used boolean not null default false;

-- Samlingslänk: en token som visar flera listor som flikar. Innehåller bara gästlänkar, aldrig mottagar- eller ägarlänkar.
create table if not exists public.paxa_fams (
  id uuid primary key default gen_random_uuid(),
  token text not null unique default replace(gen_random_uuid()::text,'-',''),
  name text not null,
  list_ids uuid[] not null,
  created_at timestamptz not null default now()
);
alter table public.paxa_fams enable row level security;

create or replace function public.paxa_create_fam(p_name text, p_owner_tokens text[])
returns json language plpgsql security definer set search_path to 'public' as $function$
declare ids uuid[] := '{}'; t text; v_list uuid; v_role text; r public.paxa_fams;
begin
  if coalesce(array_length(p_owner_tokens,1),0) < 1 or array_length(p_owner_tokens,1) > 12 then raise exception 'bad_count'; end if;
  foreach t in array p_owner_tokens loop
    select * into v_list, v_role from public.paxa_role(t);
    if v_role is distinct from 'owner' then raise exception 'not_allowed'; end if;
    if not v_list = any(ids) then ids := ids || v_list; end if;
  end loop;
  insert into public.paxa_fams(name,list_ids) values (coalesce(nullif(left(trim(p_name),60),''),'Familjens lista'), ids) returning * into r;
  return json_build_object('token',r.token);
end $function$;

create or replace function public.paxa_get_fam(p_token text)
returns json language sql stable security definer set search_path to 'public' as $function$
  select json_build_object('name',f.name,'lists',coalesce((
    select json_agg(json_build_object('name',l.name,'recipient',l.recipient,'occasion',l.occasion,'date',l.date,'guest',l.guest_token) order by array_position(f.list_ids,l.id))
    from public.paxa_lists l where l.id = any(f.list_ids)),'[]'::json))
  from public.paxa_fams f where f.token = p_token and length(p_token) >= 16;
$function$;

-- Realtime: kanalnamnet byggs av en hash av gästlänken i klienten, så mottagaren (som inte har gästlänken) kan inte lyssna.
-- Ingen databasändring krävs för det.

-- add_item och update_item får parametern p_used (frivillig, så äldre klienter fungerar).
drop function if exists public.paxa_add_item(text,text,text,text,numeric,text,text,text,text,boolean,text,text);
create or replace function public.paxa_add_item(p_token text, p_guest text, p_guest_name text, p_name text, p_price numeric, p_shop text, p_url text, p_note text, p_cat text, p_prio boolean, p_thumb text, p_img text, p_used boolean default false)
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
  insert into public.paxa_items(list_id,name,price,shop,url,note,cat,prio,thumb,img,created_by,created_by_name,used)
  values (v_list, left(trim(p_name),80), p_price, nullif(left(trim(p_shop),60),''), nullif(left(p_url,500),''), nullif(left(trim(p_note),200),''), nullif(left(p_cat,30),''), coalesce(p_prio,false), p_thumb, nullif(left(p_img,500),''), g, left(p_guest_name,40), coalesce(p_used,false))
  returning * into r;
  perform public.paxa_event(v_list,'add',g,left(p_guest_name,40),r.name,r.id);
  return json_build_object('id',r.id,'at',extract(epoch from r.created_at)*1000);
end $function$;

drop function if exists public.paxa_update_item(text,text,uuid,text,numeric,text,text,text,text,boolean);
create or replace function public.paxa_update_item(p_token text, p_guest text, p_item uuid, p_name text, p_price numeric, p_shop text, p_url text, p_note text, p_cat text, p_prio boolean, p_used boolean default null)
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
    cat = nullif(left(p_cat,30),''), prio = coalesce(p_prio,false), used = coalesce(p_used, used) where id = p_item;
  return true;
end $function$;

-- get_list returnerar used
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
    'items', coalesce((select json_agg(json_build_object('id',i.id,'name',i.name,'price',i.price,'was',i.was,'shop',i.shop,'url',i.url,'note',i.note,'cat',i.cat,'prio',i.prio,'used',i.used,'thumb',i.thumb,'img',i.img,
               'by', case when rec then null else left(i.created_by,12) end,'mine', i.created_by = g,'by_name',i.created_by_name,'at',extract(epoch from i.created_at)*1000) order by i.created_at desc, i.id)
             from public.paxa_items i where i.list_id = v_list), '[]'::json),
    'pax', case when rec then '[]'::json else coalesce((select json_agg(json_build_object('item_id',p.item_id,'by',left(p.guest_id,12),'mine',p.guest_id = g,'by_name',p.guest_name,'st',p.st,'at',extract(epoch from p.created_at)*1000))
             from public.paxa_pax p where p.list_id = v_list), '[]'::json) end,
    'events', coalesce((select json_agg(json_build_object('id',e.id,'t',e.t,'by', case when rec then null else left(e.guest_id,12) end,'mine',e.guest_id = g,'by_name',e.guest_name,'name',e.item_name,'item',e.item_id,'extra',e.extra,'at',extract(epoch from e.created_at)*1000) order by e.id desc)
             from (select * from public.paxa_events where list_id = v_list and not (rec and t in ('pax','unpax','st')) order by id desc limit 40) e), '[]'::json)
  ) into res;
  return res;
end $function$;

grant execute on function public.paxa_add_item(text,text,text,text,numeric,text,text,text,text,boolean,text,text,boolean),
  public.paxa_update_item(text,text,uuid,text,numeric,text,text,text,text,boolean,boolean),
  public.paxa_create_fam(text,text[]), public.paxa_get_fam(text) to anon, authenticated;
