# FS25-Silverrun-Fix

<img src="docs/icon.png" alt="Sawmill icon: a log travels from the pond over the ramp into the hall" width="256" align="right">

Addon mod for **Farming Simulator 25** and the **Silverrun Forest** map. It brings the FS22 log lift back to the old sawmill and fixes its woodchip heap. No map files are changed.

As in FS22, the sawmill takes the logs out of the pond one by one. Each log travels over the chain and up the ramp into the hall until the pond is empty.

## What the mod does

- **Log lift restored.** The map ships five log models and the FS22 motion clip, but FS25 no longer plays the selling station's `<animation>` block and silently ignores it. The mod plays the clip's 105 keyframes itself. They are taken 1:1 from the map's `sawmillOldAnimation.i3d.anim`.
- **Automatic collection at the pond.** You no longer need to activate the exclamation mark. Logs are sold through the same function as the manual trigger, so prices and storage limits work as usual. If the storage is full, the log stays in the pond.
- **Woodchip heap fixed.** In the map, the heap spawner creates woodchips for free while the sawmill's woodchip storage is never emptied. The sawmill stops once that storage reaches 50,000 l (see this [Steam discussion](https://steamcommunity.com/app/2300320/discussions/0/604152469261425532/)). The mod switches off the free spawning and instead empties the storage onto the same area in a steady flow of 2000 l per in-game hour. If the heap is full, the storage fills up and only then does the sawmill stop. The particles, sound and animation at the pipe above the heap only run while chips are actually flowing.
- **The yellow wood chipper makes woodchips.** In the map, the chipper next to the pond only adds the logs to the storage as wood (button "Sell Wood"). With the mod, logs thrown in are chipped automatically, as in FS22. The chips go into the sawmill storage and flow from there onto the heap. The amount matches a base game wood chipper. In `xml/custom_sawmill_extension.xml` this can be switched off (`mode`) or scaled (`chipsScale`).
- **Rollers and conveyor belts** only run while a production is active.

## Installation

1. Download the ZIP from the [Releases](../../releases), or zip the `FS25_Silverrun_Forest_Improved` folder yourself. The `modDesc.xml` has to be at the top level of the ZIP.
2. Copy the ZIP into your mods folder, usually `Documents\My Games\FarmingSimulator2025\mods`. The file is called `FS25_Silverrun_Forest_Improved.zip`.
3. Activate the mod in your Silverrun Forest savegame. The map `FS25_silverrunForest` is listed as a dependency.

The unpacked folder also works in singleplayer. FS25 requires a ZIP for multiplayer.

After loading, `log.txt` should contain a line like this:

```
[SilverrunForestImproved] Injected into 'sawmillOld': 5 roller shapes, 18 belt shapes, auto collect true, log lift slots 5, chip heap drained to heap at 2000 l/h, chipper chips, automatic.
```

## Settings

All values are in `xml/custom_sawmill_extension.xml`:

| Value | Default | Meaning |
|---|---|---|
| `logLift#transSpeed` | `0.5` | Playback speed of the lift (map value, about 33 s per log) |
| `logLift#waitThresholdAnimTime` | `3400` | Clip time in ms after which the next log starts |
| `logLift#enabled` | `true` | Log lift on/off |
| `woodTrigger#autoCollect` | `true` | Automatic collection at the pond |
| `chipHeap#drainToHeap` | `true` | Storage empties onto the heap instead of free spawning |
| `chipHeap#litersPerHour` | `2000` | Flow onto the heap per in-game hour (map value) |
| `chipHeap#maxHeapHeight` | `8` | Maximum heap height above the area in m |
| `chipHeap#tickMs` | `250` | Real time in ms between two flow updates |
| `chipper#mode` | `chips` | `chips` = woodchips, anything else = map default (wood) |
| `chipper#autoChip` | `true` | Chip logs automatically |
| `chipper#chipsScale` | `1.0` | Factor on the base game chipper yield |
| `rotationNode#rotSpeed` | `15` | Rotation speed of the rollers (map: 8) |
| `scrollNode#speedScale` | `1.0` | Factor for the conveyor belt speed |
| `syncWithProduction#value` | `true` | Rollers/belts only while a production is running |

## Limitations

- Only singleplayer players and the host see the lift animation. Other players in multiplayer only see the logs disappear.
- The same map log model always travels up the ramp, no matter how big the real log was. FS22 did the same.
- If the sawmill is not bought, the revenue goes to your farm in singleplayer. In multiplayer, automatic collection pauses until someone buys the sawmill.
- In multiplayer, other players only know the storage level sent by the host. Their pipe effects run while there are chips in the storage.
- If the mod hits a runtime error, it switches itself off for the session and writes a line to `log.txt`. It never blocks loading the savegame.

## Technical notes

`scripts/SawmillAnimationInjector.lua` registers via `addModEventListener` and, after loading, looks for the placeable with `uniqueId="sawmillOld"`. Then it:

- finds the log models `logAnimNode1–5` and plays the keyframes with `setTranslation`/`setRotation`,
- sells exactly one log at a time from the pond trigger through `WoodUnloadTrigger:processWood`,
- sets the shader parameters `rotation` (rollers) and `offsetUV` (belts) depending on the production state,
- replaces `processWood` on the chipper trigger instance and adds woodchips to the production storage,
- skips `PlaceableHeapSpawner.onUpdateTick` for this sawmill only and tips the storage onto the heap with `DensityMapHeightUtil.tipToGroundAroundLine`.

The icon (`docs/icon.svg`) is an original drawing.
