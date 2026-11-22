# Riket

Sanntidsstrategi i Age of Empires-stil for Android, laget i Godot 4.3 (2D, ovenfra). Arbeidstittel.

## Installere på telefonen
1. Åpne **Releases** i dette repoet på telefonen og last ned nyeste `riket-….apk`.
2. Åpne fila og tillat installering fra denne kilden hvis Android spør.

Hver gang det pushes til `main`, bygger GitHub Actions en ny APK automatisk. Byggingen stopper hvis testen i `tests/smoke.gd` feiler.

## Spillet (versjon 0.4)
Du (blå) mot datamaskinen (rød) på et kart på 96 × 64 ruter. Kartet er speilet gjennom midten, så begge får like gode startplasser. Du vinner når fienden har mistet rådhuset og alle enhetene sine.

**Start:** rådhus, 3 arbeidere, 200 tre, 200 mat, 100 gull, 200 stein. Folketall 5.

**Ressurser:** tre (skog), mat (bærbusker og gårder), gull og stein (gruver). Ved hver base er det skog, bær, gull og stein, og mer lenger ute. Arbeiderne bærer 10 om gangen til nærmeste leveringsplass. Bytter de type, mister de lasten.

**Tidsaldre:** Du starter i **mørketid**. **Føydaltid** forskes i rådhuset (500 mat, 60 s) og krever to ulike av sagbruk, gruveleir, mølle og brakker. Rådhuset kan ikke trene arbeidere mens det forsker. Føydaltid låser opp skytebane, stall, tårn og spydmann.

**Bygninger** (arbeiderne bygger, flere arbeidere bygger raskere). Byggemenyen har to sider: økonomi og militært.
| Bygning | Pris | Liv | Byggetid | Krav | Gir |
|---|---|---|---|---|---|
| Rådhus | – | 2400 | – | – | +5 folk, arbeidere, føydaltid, leveringsplass for alt |
| Hus | 25 tre | 550 | 15 s | – | +5 folk |
| Sagbruk | 100 tre | 600 | 20 s | – | leveringsplass for tre |
| Gruveleir | 100 tre | 600 | 20 s | – | leveringsplass for gull og stein |
| Mølle | 100 tre | 600 | 20 s | – | leveringsplass for mat |
| Gård | 60 tre | 300 | 10 s | mølle | 250 mat, én bonde; kan gås over, forsvinner når den er tom |
| Brakker | 175 tre | 1200 | 35 s | – | sverdmann, spydmann |
| Skytebane | 175 tre | 1200 | 35 s | føydaltid, brakker | bueskytter |
| Stall | 175 tre | 1200 | 35 s | føydaltid, brakker | speider, ridder |
| Tårn | 25 tre, 125 stein | 700 | 40 s | føydaltid | skyter fiender innen 7 ruter |

**Enheter:**
| Enhet | Pris | Liv | Angrep | Rustning (nærkamp/pil) | Fart | Spesielt |
|---|---|---|---|---|---|---|
| Arbeider | 50 mat | 25 | 3 | 0/0 | 80 | samler, bygger |
| Sverdmann | 60 mat, 20 gull | 45 | 6 | 1/1 | 72 | dobbel skade mot bygninger |
| Spydmann (føydal) | 35 mat, 25 tre | 45 | 3 | 0/0 | 74 | +12 mot ryttere |
| Bueskytter (føydal) | 25 tre, 45 gull | 30 | 4, rekkevidde 4,5 | 0/0 | 80 | +2 mot fotfolk |
| Speider (føydal) | 80 mat | 45 | 4 | 0/2 | 125 | ser 10 ruter, +3 mot bueskyttere |
| Ridder (føydal) | 60 mat, 75 gull | 100 | 10 | 2/2 | 105 | +4 mot bueskyttere |

**Styrketrekanten** (som i Age of Empires): bueskytter slår fotfolk, rytter slår bueskytter, spydmann slår rytter. Skade = angrep + bonus – rustning (pilrustning mot piler), minst 1.

Soldater som står i ro, angriper fiender de ser og slår tilbake når de blir angrepet. Lar de seg lokke langt hjemmefra, går de tilbake. Alle tall står i `scripts/defs.gd`.

**Samlingspunkt:** Velg en bygning som trener enheter og trykk på kartet. Nye enheter går dit. Står punktet på en ressurs eller gård, begynner nye arbeidere å jobbe der med en gang. Trykk på bygningen igjen for å fjerne punktet.

**Fienden** samler, bygger hus, leveringsplasser og gårder, går opp i føydaltid, bygger skytebane, stall og tårn, og trener de soldatene som slår det du har. Den angriper i bølger som blir større hver gang, forsvarer basen sin, og arbeiderne slår tilbake mot små angrep hvis den ikke har soldater hjemme.
| Vanskelighetsgrad | Samlefart | Første angrep | Første bølge | Annet |
|---|---|---|---|---|
| Lett | 80 % | ca. 9:00 | 3 soldater | ingen stall eller tårn |
| Normal | 100 % | ca. 7:00 | 5 soldater | 1 tårn |
| Vanskelig | 120 % | ca. 5:00 | 7 soldater | 2 brakker, 2 tårn |

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
| Trene / forske | Trykk på bygningen, så på enheten eller føydaltid. **Avbryt** gir pengene tilbake. | Samme |
| Samlingspunkt | Velg en bygning som trener, trykk på kartet | Samme |
| Dyrke gård | Velg arbeider, trykk på gården | Samme |
| Ledige arbeidere / hele hæren | **Ledige** og **Hær** øverst | Samme |
| Pause | **II** øverst eller tilbakeknappen | Esc |

## Planen videre
1. ~~Flere ressurser~~ (0.2)
2. ~~Hus og brakker~~ (0.3)
3. ~~Soldater og kamp~~ (0.3)
4. ~~Fiende-AI~~ (0.3)
5. ~~Leveringsplasser, gårder, samlingspunkt, føydaltid, skytebane, stall, tårn, spydmann, speider, ridder~~ (0.4)
6. «Fog of war», smie med oppgraderinger, borgtid, mur og port (0.5)

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
- `tests/smoke.gd` – testen som kjøres ved hver bygging (del A: alle funksjoner, del B: AI mot AI på normal)
- `tools/bench.gd` – ytelsesmåling med 170 enheter i kamp

## Ytelse
Målt med `tools/bench.gd` (170 enheter, kamp og samling, PC): ca. 1,9 ms per fysikksteg i 0.4 (var 3,6 ms før optimaliseringen i 0.3). Det som ble gjort:
- enheter skyves fra hverandre med et fint rutenett (16 px), 20 ganger i sekundet
- enheter og bygninger tegnes bare på nytt når de er på skjermen
- panelet nederst og minikartet oppdateres 10 og 5 ganger i sekundet
- søk etter nærmeste ressurs leser tabellen direkte
- bakken er ett bilde, trærne er ferdigtegnede bilder, og kartet tegnes i biter på 16 × 16 ruter

Skriften er Saira Condensed (SIL Open Font License, se `fonts/OFL.txt`).
