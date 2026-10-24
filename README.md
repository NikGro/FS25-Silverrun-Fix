# FS25-Silverrun-Fix

<img src="docs/icon.png" alt="Sägewerk-Icon: Stamm fährt vom Teich über die Rampe in die Halle" width="256" align="right">

Addon-Mod für **Farming Simulator 25** und die Map **Silverrun Forest**. Er bringt am alten Sägewerk den Stamm-Lift aus LS22 zurück. Die Map-Dateien bleiben dabei unverändert.

Wie in LS22 nimmt das Sägewerk die Stämme einzeln aus dem Teich. Jeder Stamm fährt über die Kette und die Rampe hoch in die Halle, so lange, bis der Teich leer ist.

## Was der Mod macht

- **Stamm-Lift wiederhergestellt.** Die Map bringt fünf Stamm-Modelle und den Bewegungs-Clip aus LS22 mit. FS25 spielt den `<animation>`-Block der Verkaufsstation aber nicht mehr ab, er wird kommentarlos ignoriert. Der Mod spielt die 105 Keyframes dieses Clips selbst ab. Sie stammen 1:1 aus `sawmillOldAnimation.i3d.anim` der Map.
- **Automatisches Einsammeln am Teich.** Eine Aktivierung am Ausrufezeichen ist nicht mehr nötig. Verkauft wird über dieselbe Funktion wie beim manuellen Auslösen, Preise und Lagerlimits gelten also wie gewohnt. Ist das Lager voll, bleibt der Stamm im Teich.
- **Rollen und Förderbänder** laufen nur noch, solange eine Produktion aktiv ist.

## Installation

1. Lade die ZIP aus den [Releases](../../releases) herunter, oder packe den Ordner `FS25_Silverrun_Forest_Improved` selbst als ZIP. Dabei muss die `modDesc.xml` direkt im ZIP liegen.
2. Kopiere die ZIP in deinen Mods-Ordner, normalerweise `Dokumente\My Games\FarmingSimulator2025\mods`. Die Datei heißt `FS25_Silverrun_Forest_Improved.zip`.
3. Aktiviere den Mod im Spielstand mit Silverrun Forest. Die Map `FS25_silverrunForest` ist als Abhängigkeit eingetragen.

Im Einzelspieler funktioniert auch der entpackte Ordner. Für Multiplayer verlangt FS25 eine ZIP.

Nach dem Laden sollte in `log.txt` diese Zeile stehen:

```
[SilverrunForestImproved] Injected into 'sawmillOld': 5 roller shapes, 18 belt shapes, auto collect true, log lift slots 5.
```

## Einstellungen

Alle Werte stehen in `xml/custom_sawmill_extension.xml`:

| Wert | Standard | Bedeutung |
|---|---|---|
| `logLift#transSpeed` | `0.5` | Abspieltempo des Lifts (Wert der Map, etwa 33 s pro Stamm) |
| `logLift#waitThresholdAnimTime` | `3400` | Clip-Zeit in ms, nach der der nächste Stamm startet |
| `logLift#enabled` | `true` | Stamm-Lift an/aus |
| `woodTrigger#autoCollect` | `true` | Automatisches Einsammeln am Teich |
| `rotationNode#rotSpeed` | `15` | Drehtempo der Rollen (Map: 8) |
| `scrollNode#speedScale` | `1.0` | Faktor für das Tempo der Förderbänder |
| `syncWithProduction#value` | `true` | Rollen/Bänder nur bei laufender Produktion |

## Einschränkungen

- Die Lift-Animation sehen nur Einzelspieler und der Host. Andere Spieler im Multiplayer sehen nur, dass die Stämme verschwinden.
- Es fährt immer dasselbe Stamm-Modell der Map hoch, egal wie groß der echte Stamm war. So war es auch in LS22.
- Ist das Sägewerk nicht gekauft, geht der Erlös im Einzelspieler an deinen Hof. Im Multiplayer pausiert das automatische Einsammeln, bis jemand das Sägewerk kauft.
- Tritt im Mod ein Laufzeitfehler auf, schaltet er sich für die Sitzung ab und schreibt eine Zeile ins `log.txt`. Das Laden des Spielstands blockiert er dabei nicht.

## Technik

`scripts/SawmillAnimationInjector.lua` meldet sich per `addModEventListener` an und sucht nach dem Laden das Placeable mit `uniqueId="sawmillOld"`. Danach:

- findet es die Stamm-Modelle `logAnimNode1–5` und spielt die Keyframes per `setTranslation`/`setRotation` ab,
- verkauft über `WoodUnloadTrigger:processWood` jeweils genau einen Stamm aus dem Teich-Trigger,
- setzt die Shader-Parameter `rotation` (Rollen) und `offsetUV` (Bänder) je nach Produktionsstatus.

Das Icon (`docs/icon.svg`) ist eine eigene Zeichnung.
