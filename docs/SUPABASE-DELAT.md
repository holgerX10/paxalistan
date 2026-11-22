# Delat Supabase-projekt: Bento och PaxaListan

> Kopia i repot för leverantörer. Originalet ligger i Claude-projektet "List APPAR" (`claude/SUPABASE-DELAT.md`) och uppdateras där först. Kopierad 2026-11-22.

Version 6 · 2026-11-22

Projekt: **bentoevent** (eu-north-1). Gratisnivån tillåter två aktiva projekt (MinLista och bentoevent), därför delar apparna det här. Utveckling och test ska göras mot en **lokal Supabase** byggd från `supabase/migrations/`, aldrig mot det delade produktionsprojektet.

## Projektet kan pausas
- Projektet var pausat den 22 november och startades igen samma dag. Under pausen var både Bento och PaxaListan utan databas.
- Bento har en schemalagd Netlify-funktion (`keepalive`, dagligen 05:17 UTC) som håller projektet vaket.
- Svarar inte databasen: kontrollera projektets status först.

## Bento äger
- Tabeller: `lists`, `list_members`, `events`
- Funktioner: `is_member`, `create_list`, `join_list`, `rotate_invite`, `touch_updated_at`, `delete_account`
- Katalog och cache för AI-förslag: `bento_catalog`, `bento_suggest_cache`, `bento_secret` och funktionerna `bento_norm`, `bento_ok`, `bento_catalog_find`, `bento_catalog_put`, `bento_cache_get`, `bento_cache_put` (kräver serverhemlighet).
- Publika delningssidor: `bento_public_events`, `bento_publish`, `bento_public_get`, `bento_public_saved`.
- Extension: `pg_trgm` i schemat `extensions`.
- Storage-bucket: `posters`
- Realtime: `postgres_changes` på `public.events`, kanaler `events-<list-id>`
- Auth: Supabase Auth med e-post. Bara Bento skickar mejl.

## PaxaListan äger
- Tabeller: `paxa_lists`, `paxa_items` (med `used` för "Gärna begagnat"), `paxa_pax`, `paxa_events`, `paxa_ai_use` (AI-kvot per lista och IP-hash och dygn), `paxa_fams` (familjelänkar)
- Interna funktioner: `paxa_role`, `paxa_event`, `paxa_gh`
- Öppna för anon: `paxa_create_list`, `paxa_get_list(p_token, p_guest)`, `paxa_update_list`, `paxa_delete_list`, `paxa_add_item`, `paxa_update_item`, `paxa_move_item`, `paxa_delete_item`, `paxa_set_pax`, `paxa_set_pax_status`, `paxa_ai_allow`, `paxa_create_fam`, `paxa_get_fam`
- Ingen inloggning. All åtkomst via `security definer`-RPC som kontrollerar en länktoken. Tabellerna har RLS på och inga policies.
- Gästens id är en hemlig nyckel i webbläsaren. Databasen sparar bara sha256-hashen. Paxning är atomär. Mottagaren får inga paxningar eller paxhändelser.
- Realtime: endast broadcast på kanalen `paxa-<24 hex>`, en hash av listans gästlänk, så mottagaren kan inte lyssna.
- Storage: ingen ännu. Miniatyrer sparas som data-URL i `paxa_items.thumb`.

## Regler
- Allt nytt för PaxaListan får prefixet `paxa_`, allt nytt för Bento prefixet `bento_`.
- Ingen av apparna rör den andras tabeller, funktioner, buckets eller kanaler.
- Inga `reset`, `drop schema` eller migreringar som ändrar hela `public`.
- Ändringar i delade inställningar (extensions, auth, region, plan) beslutas av beställaren först.
- **Service role-nyckeln används inte av PaxaListan.** Den ger åtkomst till hela projektet, även Bentos data. Serverfunktioner som behöver mer än anon ska anropa egna `paxa_`-RPC:er som kräver en egen serverhemlighet.
- Om PaxaListan inför inloggning: Bentos `delete_account` raderar i `auth.users` och måste då samordnas.
