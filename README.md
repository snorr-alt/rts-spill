# Riket

Sanntidsstrategi i Age of Empires-stil for Android, laget i Godot 4.3 (2D, ovenfra). Arbeidstittel.

## Installere på telefonen
1. Åpne **Releases** i dette repoet på telefonen og last ned nyeste `riket-….apk`.
2. Åpne fila og tillat installering fra denne kilden hvis Android spør.

Hver gang det pushes til `main`, bygger GitHub Actions en ny APK automatisk. Byggingen stopper hvis testen i `tests/smoke.gd` feiler.

## Versjon 0.1 – hva som finnes
- Tilfeldig kart (64 × 48 ruter) med skog, stein og et rådhus i midten. Det er alltid skog like ved rådhuset.
- 3 arbeidere og 100 tre ved start.
- Arbeiderne hogger tre (10 per tur), bærer veden til rådhuset og går tilbake. Når et tre er tomt, finner de selv det nærmeste.
- Rådhuset trener nye arbeidere (50 tre, 10 s, opptil 5 i kø). Nye arbeidere går selv og hogger.
- Folketall maks 10 (hus kommer senere).

## Styring
| Handling | Berøring | PC |
|---|---|---|
| Velg arbeider / rådhus | Trykk | Venstreklikk |
| Gå / hogg / lever ved | Trykk på bakken, et tre eller rådhuset når arbeidere er valgt | Venstre- eller høyreklikk |
| Velg flere | Hold fingeren stille et øyeblikk, så dra en boks | Hold inne, så dra |
| Velg alle på skjermen | Dobbelttrykk på en arbeider | Dobbeltklikk |
| Flytte kartet | Dra | Dra |
| Zoom | Knip | Musehjul |
| Ledige arbeidere | «Ledige»-knappen øverst | Samme |

## Planen videre
1. Flere ressurser: mat (bær, sauer), gull og stein
2. Bygge hus (folketall) og brakker
3. Trene soldater, kamp og liv
4. Fiende-AI som samler, bygger og angriper
5. Tidsaldre og oppgraderinger, «fog of war», minikart

## Filer
- `scripts/map.gd` – rutenettet, stifinning (AStarGrid2D) og tegning av terreng og trær
- `scripts/worker.gd` – arbeideren: gå, hogge, bære og levere
- `scripts/town_center.gd` – rådhuset og treningskøen
- `scripts/main.gd` – kamera, berøring, valg og ordre, økonomi
- `scripts/hud.gd` – ressurslinje og panelet for det som er valgt
- `tests/smoke.gd` – testen som kjøres ved hver bygging

Skriften er Saira Condensed (SIL Open Font License, se `fonts/OFL.txt`).
