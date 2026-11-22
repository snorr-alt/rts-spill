# Riket

Sanntidsstrategi i Age of Empires-stil for Android, laget i Godot 4.3 (2D, ovenfra). Arbeidstittel.

## Installere på telefonen
1. Åpne **Releases** i dette repoet på telefonen og last ned nyeste `riket-….apk`.
2. Åpne fila og tillat installering fra denne kilden hvis Android spør.

Hver gang det pushes til `main`, bygger GitHub Actions en ny APK automatisk. Byggingen stopper hvis testen i `tests/smoke.gd` feiler.

## Spillet (versjon 0.3)
Du (blå) mot datamaskinen (rød) på et kart på 96 × 64 ruter. Kartet er speilet gjennom midten, så begge får like gode startplasser. Du vinner når fienden har mistet rådhuset og alle enhetene sine.

**Start:** rådhus, 3 arbeidere, 200 tre, 200 mat, 100 gull, 200 stein. Folketall 5.

**Ressurser:** tre (skog), mat (bærbusker), gull og stein (gruver). Ved hver base er det skog, bær, gull og stein, og mer lenger ute. Arbeiderne bærer 10 om gangen til rådhuset. Bytter de type, mister de lasten.

**Bygninger** (arbeiderne bygger, flere arbeidere bygger raskere):
| Bygning | Pris | Liv | Byggetid | Gir |
|---|---|---|---|---|
| Rådhus | – | 2400 | – | +5 folk, trener arbeidere |
| Hus | 25 tre | 550 | 15 s | +5 folk |
| Brakker | 175 tre | 1200 | 35 s | trener soldater |

**Enheter:**
| Enhet | Pris | Liv | Angrep | Rekkevidde | Merknad |
|---|---|---|---|---|---|
| Arbeider | 50 mat | 25 | 3 | nærkamp | samler, bygger |
| Sverdmann | 60 mat, 20 gull | 45 | 6 (rustning 1) | nærkamp | dobbel skade mot bygninger |
| Bueskytter | 25 tre, 45 gull | 30 | 4 | 4,5 ruter | svak mot bygninger |

Soldater som står i ro, angriper fiender de ser og slår tilbake når de blir angrepet. Lar de seg lokke langt hjemmefra, går de tilbake. Alle tall står i `scripts/defs.gd`.

**Fienden** samler, bygger hus og brakker, trener sverdmenn og bueskyttere og angriper i bølger som blir større hver gang. Den forsvarer basen sin, og arbeiderne slår tilbake mot små angrep hvis den ikke har soldater hjemme.
| Vanskelighetsgrad | Samlefart | Første angrep | Første bølge |
|---|---|---|---|
| Lett | 80 % | ca. 9:00 | 3 soldater |
| Normal | 100 % | ca. 6:30 | 5 soldater |
| Vanskelig | 120 % | ca. 4:30 | 7 soldater, 2 brakker |

## Styring
| Handling | Berøring | PC |
|---|---|---|
| Velg | Trykk | Venstreklikk |
| Gi ordre (gå, samle, bygge, levere, angripe) | Trykk på bakken, en ressurs, en byggeplass, rådhuset eller en fiende når noe er valgt | Venstre- eller høyreklikk |
| Velg flere | Hold fingeren stille et øyeblikk, så dra en boks (er det soldater i boksen, velges bare de) | Hold inne, så dra |
| Velg alle av samme type på skjermen | Dobbelttrykk | Dobbeltklikk |
| Flytte kartet | Dra, eller trykk/dra på minikartet | Samme |
| Zoom | Knip | Musehjul |
| Bygge | Velg arbeidere → **Bygg** → velg bygning. Byggeplassen følger midten av skjermen (dra kartet) eller stedet du trykker, og hopper til nærmeste ledige plass. Trykk **Plasser**. | Samme |
| Trene | Trykk på rådhuset eller brakkene, så på enheten. **Avbryt** gir pengene tilbake. | Samme |
| Ledige arbeidere / hele hæren | **Ledige** og **Hær** øverst | Samme |
| Pause | **II** øverst eller tilbakeknappen | Esc |

## Planen videre
1. ~~Flere ressurser~~ (0.2)
2. ~~Hus og brakker~~ (0.3)
3. ~~Soldater og kamp~~ (0.3)
4. ~~Fiende-AI~~ (0.3)
5. Tidsaldre og oppgraderinger, «fog of war», flere bygninger (skytebane, stall, tårn, mur), leveringsplasser (sagbruk, mølle, gruveleir)

## Filer
- `scripts/defs.gd` – alle tall: priser, liv, angrep, byggetid, vanskelighetsgrader
- `scripts/map.gd` – rutenett, kartgenerering, ressurser, stifinning (AStarGrid2D) og tegning i biter
- `scripts/unit.gd` – felles for alle enheter: bevegelse, angrep, liv, død
- `scripts/worker.gd` – arbeideren: samle, levere, bygge
- `scripts/building.gd` – bygninger: byggeplass, trening, liv
- `scripts/player.gd` – et lag: ressurser, enheter, bygninger, folketall
- `scripts/ai.gd` – fiende-AI-en
- `scripts/main.gd` – kamera, berøring, valg, ordre, bygging, seier/tap
- `scripts/hud.gd` – ressurslinje, minikart, panelet nederst, menyer
- `tests/smoke.gd` – testen som kjøres ved hver bygging (del A: alle funksjoner, del B: AI mot AI)
- `tools/bench.gd` – ytelsesmåling med 170 enheter i kamp

## Ytelse
Målt med `tools/bench.gd` (170 enheter, kamp og samling, PC): ca. 1,8 ms per fysikksteg (var 3,6 ms før optimaliseringen). Det som ble gjort:
- enheter skyves fra hverandre med et fint rutenett (16 px), 20 ganger i sekundet
- enheter og bygninger tegnes bare på nytt når de er på skjermen
- panelet nederst og minikartet oppdateres 10 og 5 ganger i sekundet
- søk etter nærmeste ressurs leser tabellen direkte
- bakken er ett bilde, trærne er ferdigtegnede bilder, og kartet tegnes i biter på 16 × 16 ruter

Skriften er Saira Condensed (SIL Open Font License, se `fonts/OFL.txt`).
