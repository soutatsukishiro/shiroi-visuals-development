# Changelog

## Stable 26.3.10

### Looks

- Sunsets are smooth. The clouds, the haze and the ground used to switch from the warm sunset light to the cold
  night light in a single frame as the sun reached the horizon; now the sun's light fades over its last few degrees
  and the moon's comes in as it rises. The picture also dims steadily through the dusk instead of holding its
  daylight brightness and then dropping to night. The same happens in reverse at sunrise. Day and night look the
  same as before.
- A torch, lantern or other light in your hands lights up the area around you again, in its own colour (teal
  for soul torches, red for redstone, green for copper). It can be turned off in Lighting, Held light.
- Enchanted items shine as in vanilla by day and by night (the shine used to be lost in daylight), and the moving
  shine glows. Materials, Enchantment Shine and Enchantment Glow set how much.
- Nether portals light the blocks around them in purple, like the coloured light of soul and copper torches.
- More blocks glow in their coloured parts: trial spawners and vaults, sculk sensors and shriekers, lit
  redstone parts (comparators, repeaters, observers, crafters, powered rails), the eye of an End portal frame and
  the dragon egg, and the two magenta eyes of a monster spawner (the cage stays metal). The End portal frame
  itself no longer glows, only the raised eye (its green, not the dark pupil), and the creaking heart glows again
  (its old rule used a block state that no longer exists).
- Light blocks glow only where they should. A sculk catalyst glows in its cyan spots, not all over; a jack
  o'lantern in its face; copper bulbs (green ones too) in their lamp; end rods in the rod; crying obsidian in its
  tears; a respawn anchor in its charge. A sculk shrieker's swirl glows. Amethyst clusters and conduits no longer
  glow.
- Froglights, shroomlight, magma blocks, glow lichen and crying obsidian glow softly from their surface (about a
  third of glowstone); they still light the area as before. Materials, Block Glow sets how much glowing blocks
  glow around them.
- Clouds follow the target look's cloud model (Sky: Cloud Model): the light takes the real paths through the cloud
  cells (joined cells are one body), the faces keep their shade, and clouds are see-through with one opacity, so a
  cloud behind another shows through it. The bright edges come from those paths, as in the target look: near the
  sun the whole cloud is lit, away from it the thin edges and sunward sides keep the light.
  Their strength, opacity and night light are matched to the target look's clouds at 23500, 1000, 6000, 13000 and
  18000: whiter by day, lilac at dawn, a warm glow beside the sun, and lighter than the sky at night.
- The volumetric fog's sky light and sun shafts follow how much sky each point of it sees, as the target look's
  fog volume does: light shafts at a cave mouth seen from inside, less sky light in the fog under trees and by walls
  (Volume: Sky Visibility in Fog).
- Torches, lamps and other lights light the volumetric fog around them, in their colour, as the target look's fog
  volume does (Volume: Block Light in Fog).
- Clouds are reflected soft, as in the target look: they are drawn into the sky probe (as its sky probe pass does),
  and the screen-space reflections no longer pick them from the screen, sharp (Sky: Clouds in Reflections).
- Water fades into the distance fog like the land: what is seen through it fades with the surface, as in the target
  look's water pass. It used to stay brighter than the fogged land, a checkerboard of water chunks at the edge of
  the render distance.
- The sky's glow at sunrise and sunset is the target look's wide warm band over the whole sun side of the horizon,
  at its full strength, instead of a small halo around the sun (Sky: Sunrise / Sunset Glow).
- Sky: Day Follows the Clock (off by default: the day's colours follow the sun's position). The ground keeps more of
  the sky's light at dawn, dusk and night, as in the target look; by night clouds are one even dark grey instead of
  black with bright lilac edges, and the moonlit sky is a little brighter. Under water the evening keeps more light
  than midnight, as in the target look.
- Volumetric fog only in the biomes that have it in the target look: taigas, windswept forest, beach, sparse jungle,
  the warm oceans, jungles, mangroves, lush caves, the dark forest, the swamp, the mushroom fields and ice spikes (plus
  the pale garden, sulfur caves and the End, as before). Plains, the common forests, birch, cherry, savannas, hills
  and peaks, the cold oceans and rivers and the caves have clear air with the distance fog only: no more orange haze
  around a low sun or lilac sky in the morning and afternoon.
- Clouds by day are white and bright from below as in the target look, instead of a dim blue grey (matched to it in
  the morning). Sunrise, sunset, night and the grey clouds of rain keep their colours.
- Under water, matched to the target look in open ocean by day, at nightfall and at midnight: the sea floor deeper than
  15 blocks is lit by the sun through the water again (the game's sky light is 0 there, and it was taken for a sealed
  cave: no sun, no sky, only a harsh net of caustics on black), the open water stays blue at any depth instead of
  turning black, and the water darkens with the night, navy blue at midnight with the floor still visible (it used to
  stay a bright cyan wall all night). Each biome
  has its own water colour and distance: oceans deep blue, rivers bright blue, swamps murky and closer, frozen oceans
  dark blue.
- Per-block PBR table: leaves, wood and mud now follow the target look texel by texel. Each texture's bright texels
  are smoother and its dark ones rougher, across one range per family (planks and logs, poplar and other smooth
  woods, tinted leaves, coloured leaves such as poplar and cherry, mud, packed mud, mud bricks, muddy mangrove roots).
  Wet mud is clearly smoother than packed mud. Blackstone too: raw blackstone rough, polished blackstone and its
  bricks, cracked and chiseled smoother, and gilded blackstone's gold flecks metallic and shinier than its stone. Costs about 0.4 ms in a dense forest (the texture's brightness range
  is read once per sprite and kept in a small table).
- PBR Format (Materials): LabPBR 1.3, the layout of most PBR resource packs, besides this pack's own. Read the old
  way a LabPBR pack lost its glowing parts and made its metals glow.
- End portals and gateways show a dark field of small teal, green and blue stars in depth that shifts as you move,
  instead of the almost black block Iris draws in their place. The stars are their own light: nearby lava or torches
  don't tint or brighten them, and a portal just lit by its last eye no longer shows as a pale blue sheet.
- Works with Enchantment Glows and other resource packs that mark glowing texels in their item textures: those
  parts now glow (with their animation) instead of showing as plain texture.

### Fixes

- The block selection outline shows again. Minecraft 26 sends line segments with no width and expects the shader
  to open them; the pack never did, so the outline never appeared.
- Torches and lanterns really glow in your hand now, and so do glowstone and the other light blocks. The game
  reports these items by their block, not as items, so the glow added in R29 never switched on.
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
