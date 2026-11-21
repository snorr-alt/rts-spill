# Riket

Sanntidsstrategi i Age of Empires-stil for Android, laget i Godot 4.3 (2D, ovenfra). Arbeidstittel.

## Installere på telefonen
1. Åpne **Releases** i dette repoet på telefonen og last ned nyeste `riket-….apk`.
2. Åpne fila og tillat installering fra denne kilden hvis Android spør.

Hver gang det pushes til `main`, bygger GitHub Actions en ny APK automatisk. Byggingen stopper hvis testen i `tests/smoke.gd` feiler.

## Hva som finnes (versjon 0.2)
- Tilfeldig kart (64 × 48 ruter) med skog, stein og et rådhus i midten.
- Fire ressurser som i Age of Empires: **tre** (skog), **mat** (bærbusker), **gull** og **stein** (gruver). Ved basen er det alltid skog, en bærbusk-klynge, en gullgruve og en steingruve, og det finnes flere lenger ute.
- Start: 3 arbeidere, 200 tre, 200 mat, 100 gull, 200 stein.
- Arbeiderne samler 10 om gangen, bærer det til rådhuset og går tilbake. Når en ressurs er tom, finner de selv nærmeste av samme type. Bytter en arbeider ressurstype, mister den det den bar.
- Ulik fart: bær går raskest, så tre, gull og stein. Verktøyet viser hva de gjør (øks, hakke, hånd), og lasten på ryggen har ressursens farge.
- Rådhuset trener nye arbeidere (50 mat, 10 s, opptil 5 i kø). Nye arbeidere går selv og samler mat eller tre, det det er minst av.
- Folketall maks 10 (hus kommer senere).
- Trykk på en ressurs (uten arbeidere valgt) for å se hvor mye som er igjen.

## Styring
| Handling | Berøring | PC |
|---|---|---|
| Velg arbeider / rådhus | Trykk | Venstreklikk |
| Gå / samle / lever | Trykk på bakken, en ressurs eller rådhuset når arbeidere er valgt | Venstre- eller høyreklikk |
| Send til nærmeste ressurs | Knappene Tre / Mat / Gull / Stein nederst | Samme |
| Velg flere | Hold fingeren stille et øyeblikk, så dra en boks | Hold inne, så dra |
| Velg alle på skjermen | Dobbelttrykk på en arbeider | Dobbeltklikk |
| Flytte kartet | Dra | Dra |
| Zoom | Knip | Musehjul |
| Ledige arbeidere | «Ledige»-knappen øverst | Samme |

## Planen videre
1. ~~Flere ressurser: mat, gull og stein~~ (0.2)
2. Bygge hus (folketall) og brakker
3. Trene soldater, kamp og liv
4. Fiende-AI som samler, bygger og angriper
5. Tidsaldre og oppgraderinger, «fog of war», minikart

## Filer
- `scripts/map.gd` – rutenettet, ressursene, stifinning (AStarGrid2D) og tegning av terrenget
- `scripts/worker.gd` – arbeideren: gå, samle, bære og levere
- `scripts/town_center.gd` – rådhuset og treningskøen
- `scripts/main.gd` – kamera, berøring, valg og ordre, økonomi
- `scripts/hud.gd` – ressurslinje og panelet for det som er valgt
- `tests/smoke.gd` – testen som kjøres ved hver bygging

Skriften er Saira Condensed (SIL Open Font License, se `fonts/OFL.txt`).
