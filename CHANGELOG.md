# Changelog

## 26.3.11

### Looks

- Sunsets darken gradually. The picture used to keep its daylight brightness until well after the sun had gone,
  then drop to night in a few seconds; now the sky and the ground dim steadily from the moment the sun touches the
  horizon until night falls. The same happens in reverse at sunrise. Day and night look the same as before.

### Fixes

- Torches and lanterns really glow in your hand now. Held flat items go through a different shader than blocks,
  and the glow added in R29 never reached them.
- The moon no longer has a lit square around it, and its dark side stays dark, so the phases read clearly. The
  phase itself comes from the game: `/time set` can put the world back on day 0, which is a full moon, so use
  `/time add 24000` to step through the nights.

## Stable R29

### Looks

- Torches and lanterns now glow when you hold them, the same way they do when placed. Only the flame lights up, not
  the handle or the frame. Dropped ones and ones in item frames glow too.

### Fixes

- TAA is much sharper while you move. Turning the camera used to smear the picture; now it stays close to the
  still image, and after you stop it settles in a few frames instead of a second or two.
- Less ghosting behind things that move.
- Cloud shadows no longer creep sideways a pixel at a time, and no longer jump back and forth. They now move in one
  step at a time, together with the other shadows.

### Performance

- The sharper TAA costs about 0.07 ms per frame at 1080p (less than 1 fps at 120 fps). The other changes cost
  nothing measurable.

## Stable R26

This release collects everything since the last snapshot.

### Looks

- Snow: during snowfall the sky keeps a soft blue top and a pink horizon, with light fog. Thunderstorms in snowy
  biomes look the same instead of turning dark and foggy.
- Biomes: each biome family gets its own colour temperature and air. Snowy places are cooler, jungles and deserts
  warmer, swamps and the Pale Garden foggier. The Nether biomes have their own sky colours, and the End sky is no
  longer too bright after the dragon fight.
- Coloured torch light: soul torches and soul fire light the area teal, copper torches green and redstone torches
  red, and they glow in their own colour. Normal torches and lamps are unchanged.
- Materials: wet farmland is shiny, dry farmland matte. Fallen leaves and pink petals let light through. Melons
  and pumpkins have their own finish. Iron, gold, diamond, netherite, copper and chainmail armour now look
  metallic (leather is unchanged).
- Shadows: cloud shadows have the same hard pixel edges as the other shadows.
- The sun's glow is softer, and the rings that showed in the glow around it are gone.

### Fixes

- The lit redstone torch no longer has a glowing pink box around its head.
- No more dark lines on frozen rivers and lakes, or along the edges of lakes.
- Shadows no longer creep back and forth as the sun moves.
- Much less shimmer with TAA and 85% resolution: on the sun's edge, on leaves, on the player and along water.
- Edges between still surfaces no longer blink every few frames (TAA anti-flicker setting).
- Players and mobs stay sharp while moving with TAA.
- The pack compiles again with the mod compatibility setting turned off.

### Performance

- Frozen rivers and lakes ran about four times slower than they should. They are back to normal.
- Shadows are a bit cheaper (about 5 to 15% of the shadow pass).
- Solid terrain no longer runs the transparency test, so hidden surfaces cost less.

### Settings

- All option names and descriptions are in English.
- New: TAA anti-flicker, Sun halo strength, Biome colour grading.
- Celestial Bloom Strength now defaults to 0.6 (was 1.0).
