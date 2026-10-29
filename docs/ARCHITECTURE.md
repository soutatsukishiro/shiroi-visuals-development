# How a frame is drawn

This is a map of the passes, in the order Iris runs them. Each entry names the file that holds the code; the comment
at the top of that file goes into detail. The render targets and the G-buffer layout are listed in
`shaders/lib/gbuffer.glsl`, and the custom images and buffers in `shaders/shaders.properties`.

The top-level files (`composite3.fsh`, `prepare2.csh`, ...) are tiny: they set a define or two and include a file
from `program/`. So one program file usually holds several passes, chosen by those defines.

## 1. Shadows

- **shadow** (`program/shadow.glsl`, `lib/shadowmap.glsl`): the shadow map is a 2x2 atlas, one cascade per tile.
  A geometry shader draws each triangle into every cascade it touches. The sun moves in steps
  (`SHADOW_SUN_STEP`), so shadows don't crawl; with **Pixel shadows** each 1/16 block texel takes one shadow value.
  The Vitrail edition has no geometry shader, so it draws a single cascade.

## 2. Prepare (before the world)

- **prepare, prepare1** (`program/prepare.glsl`, `lib/skyprobe.glsl`): the sky rendered into a small environment
  map, then blurred into levels for glossy reflections.
- **prepare2-4** (`program/lightcolor_spread.glsl`, `lib/lightcolor.glsl`): coloured torch light. The positions of
  coloured lights are written into a 3D grid and blurred along each axis.

## 3. Geometry

- **gbuffers_terrain, entities, hand, block** (`program/gbuffers_solid.glsl`): opaque geometry writes the G-buffer:
  albedo, normal, material, light levels. Materials come from `block.properties` / `item.properties` and
  `lib/surface.glsl`, or from a PBR resource pack if there is one.
- **gbuffers_skybasic / skytextured** (`program/gbuffers_sky.glsl`): sun, moon and stars. The sky colour itself is
  computed per pixel later (`lib/skymodel.glsl`).
- **gbuffers_clouds** (`program/gbuffers_clouds.glsl`, `lib/clouds.glsl`): the game's clouds, lit as a soft slab.

## 4. Deferred lighting

- **deferred** (`program/deferred.glsl`, `lib/shading.glsl`): lights everything opaque: the sun or moon with its
  shadows and cloud shadows, sky light, block light (coloured where needed), reflections from the sky probe. It
  also fills in the sky.

## 5. Translucent and forward geometry

- **gbuffers_water** (`program/gbuffers_translucent.glsl`): translucent blocks. Water writes only its surface (it's
  shaded later in composite5); glass, ice and the rest are lit right here with the same lighting code.
- **gbuffers_particles, textured, weather, line...** (`program/gbuffers_forward.glsl`): particles, rain and snow,
  the block outline and other things drawn after deferred, lit in place.

## 6. Fog volume

- **composite.csh, composite1.csh, composite2.csh** (`program/volume.glsl`, `lib/froxel.glsl`): fog and light shafts
  in a 3D grid that follows the screen. Shadowing, then filling, then scattering along each view ray. Reused over
  frames to stay smooth.

## 7. Scene composites

- **composite3** (`program/composite_scene.glsl`, `CS_VOLUME`): applies the fog to the scene.
- **composite4** (`CS_SSR`, `lib/ssr.glsl`): screen-space reflections.
- **composite5** (`CS_WATER`): the water surface: reflection, refraction, colour by depth, caustics.

## 8. Exposure

- **composite6-9.csh** (`program/exposure.glsl`, `lib/exposure.glsl`): a brightness histogram of the frame drives
  automatic exposure.

## 9. Resolve

- **composite10** (`program/post.glsl`, `LE_DOWN`): a blurred, small copy of the brightness for local exposure.
- **composite11** (`LE_APPLY`, `lib/taa.glsl`): TAA (and the upscale from 85% resolution), then local exposure.
- **composite12.csh** (`program/celestial_history.glsl`): a mask of the sun and moon discs kept over frames.

## 10. Glow

- **composite12-23** (`post.glsl`, `BLOOM_*`): bloom, a chain of downsample and upsample passes.
- **composite24-30** (`post.glsl`, `CELESTIAL_*`, `lib/celestial_bloom.glsl`): the soft glow around the sun and moon.

## 11. End of frame

- **composite31.csh** (`program/cloudtrack.glsl`): works out where the clouds are (for cloud shadows) and saves
  the state the next frame needs: the shadow grid shift and the cloud scroll of the last sun step.
- **composite32.csh** (`program/entitytrack_clear.glsl`): clears the table used for entity motion
  (`lib/entitymotion.glsl`).
- **final** (`program/final.glsl`): white balance, colour grading, exposure, tone mapping (Lottes by default; ACES,
  Hable and Reinhard are options), and a little dither against banding.

## Nether and End

`world-1/` (Nether) and `world1/` (End) hold the same list of passes, with defines for that dimension. Iris uses
the whole folder for that dimension, so every pass has to be there.
