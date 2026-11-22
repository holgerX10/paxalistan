# PaxaListan – hela projektet

Läget den 22 november 2026. Den här filen sammanfattar vad appen är, hur den är byggd, vad som är gjort och vad som återstår.

## Vad appen är
En önskelista för familjer. Ägaren lägger in saker genom att fota dem, klistra in en butikslänk eller skriva själv. Släkten paxar (reserverar) presenter via en delad länk. Mottagaren ser listan men inte vad som paxats eller av vem. Appen har inga konton, ingen reklam, inga affiliatelänkar och ingen spårning.

- Live: https://paxalistan.netlify.app
- Kod: GitHub holgerX10/paxalistan, grenen main
- Testtelefon: Pixel 9 Pro, Chrome. Appen kan installeras på hemskärmen (PWA).

## Roller och länkar
| Roll | Länk | Kan |
|---|---|---|
| Ägare | `#list-<ägartoken>` (visas aldrig i adressfältet, sparas i telefonen) | allt, inklusive ändra, radera och dela |
| Släkt (gäst) | `#list-<gästtoken>` | se, paxa, lägga till |
| Mottagare | `#list-<visningstoken>` | se och önska, ser inga paxningar |
| Familjelänk | `#fam-<token>` | som gäst, men flera listor som flikar |

## Arkitektur
- **Gränssnitt:** `public/index.html`, en fil med HTML, CSS och JS, utan byggsteg. Typsnitten Anton, Archivo och Space Mono ligger i `public/fonts`. Färger: papper #F6EFE4, bläck #1E1613, tomat #E8502F, petrol #1F6E6B, ockra #F0B340.
- **Data:** Supabase-projektet `bentoevent`, som delas med appen Bento. Allt som hör till PaxaListan har prefixet `paxa_`. RLS är på och det finns inga policies, så all åtkomst går via `security definer`-funktioner som kontrollerar länktoken. Se `claude/SUPABASE-DELAT.md` i projektet List APPAR.
- **Tabeller:** `paxa_lists`, `paxa_items`, `paxa_pax`, `paxa_events`, `paxa_ai_use`, `paxa_fams`.
- **Serverfunktioner (Netlify):**
  - `/api/see`: bildigenkänning med Claude (`claude-haiku-5-5`, utan tänkande, avbryts efter 9 s). Kräver giltig listlänk. Högst 60 anrop per lista och 40 per IP och dygn.
  - `/api/peek`: läser namn, bild och pris från en butikslänk. Har SSRF-skydd, alltså DNS-kontroll vid varje omdirigering, och blockerar interna adresser. Priser i utländsk valuta blir tomma.
- **Synk:** Realtime broadcast på en kanal vars namn är en hash av gästlänken, så mottagaren kan inte lyssna. Appen frågar också servern var 20:e–45:e sekund och när den kommer tillbaka i förgrunden.
- **Miljövariabler i Netlify:** `ANTHROPIC_API_KEY` (egen arbetsyta i Claude Console med utgiftstak), valfritt `PAXA_MODEL`.
- **Databasmigreringar i repot:** `supabase/migrations/20261122_paxa_v11_sakerhet.sql` och `20261122_paxa_v12_familj_begagnat.sql`.

## Funktioner i dag
- Kamera med levande bild i appens egen vy, bildbibliotek, länk eller skriv själv.
- Bildigenkänning: föreslår namn, kategori och pris och beskär bilden.
- Paxa i tre steg: Paxad, Köpt, Inslagen. Gästen bekräftar tre löften första gången.
- Vyerna Listan, Bläddra (kortlek), Aktivitet och Mer.
- Flytta en sak mellan egna listor, ta bort med ångra i 5 s, mörkt läge och stor text.
- Bakåt-gesten stänger kameran eller arket.
- Spara-ägarlänken-steg när en lista skapas.
- Butiksbilder som inte laddar ersätts med en lugn bildsymbol.
- **Nytt i v1.2 (byggt, inte publicerat än):** familjelänk med flikar, "Gärna begagnat" med sökknappar till Tradera, Blocket och Vinted, och Realtime-kanalen som mottagaren inte kan lyssna på.

## Historik
| Version | Innehåll |
|---|---|
| v1.0 | Grundappen på Netlify och Supabase |
| e77793b | Levande kamera, bakåt-gest, igenkänning utan tänkande och inom tidsgränsen |
| v1.1 (2e49c68, publicerad) | Atomär paxning, hemlig gästnyckel, inget läckage till mottagaren, AI-kvot, SSRF-skydd, dold ägarlänk, bildfallback, egna typsnitt, ny ikon, säkerhetsheaders |
| v1.2 (7ba4baa, väntar) | Familjelänk, Gärna begagnat, Realtime-kanal som hash |

## Testat
- **I databasen, som anonym besökare:**
  - Den andra som paxar samma sak får "taken".
  - En gäst kan inte avpaxa någon annan.
  - Mottagaren får inga paxningar.
  - AI-kvoten nekar felaktiga länkar.
  - Familjelänken returnerar bara gästlänkar.
- **I webbläsaren här, med påhittade svar:** kameran, bakåt-gesten, att ägarlänken döljs, bildfallback, typsnitt, familjeflikar och begagnatlänkar.
- **Inte testat:** allt på riktig telefon. Där behöver bildigenkänning, bildbibliotek, butikslänkar, delning från annan app och iPhone kontrolleras.

## Kvar till 2.0
- Bilder i Supabase Storage (WebP) i stället för base64 i databasen.
- Ny frontendstruktur (Vite och TypeScript) med tester.
- "Mina pax": alla mina paxningar i alla listor, med budget.
- Samköp ("Gå ihop") och "Jag köper något eget".
- Upplevelsekort, katalogkort med bilden skild från texten, Archivo för produktnamn.
- Content-Security-Policy, väljare för vilken lista en delad länk ska till, offline-stöd.
- Röstlapp, önskeburk, etiketter, View Transitions.
- Briefen "PaxaListan 2.0 Master Brief" finns men behöver uppdateras. Det som redan är gjort i v1.1 och v1.2 ska strykas, och två påståenden om AI-modellen var fel: `claude-haiku-5-5` är rätt modell och `thinking: disabled` ska vara kvar.
