// Shiroi Visuals - user settings. The lists in [..] are the choices Iris offers in the menu; the defaults give the
// intended look.

// ---------------------------------------------------------------- shadows
#define SHADOW_QUALITY 3            // [0 1 2 3] cascade setup: low, medium, high, ultra (lib/look.glsl)
#define CLOUD_SHADOWS               // shadows of the vanilla clouds (aligned with them through Iris cloudTime / cloudHeight)
#define SHADOW_SUN_STEP 40         // the shadow light turns in steps of this many ticks of sun travel, so shadows never slide back (0 = every frame) [0 20 40 80]
#define TEXEL_SHADOWS               // "pixel" shadows: receivers snapped to the 1/16 block texel grid, one shadow-map texel each, no filter
#define SHADOW_NORMAL_OFFSET 0.065  // receiver offset along the normal, in blocks [0.0 0.02 0.04 0.065 0.1 0.15 0.2]
#define SHADOW_BIAS_SCALE 1.0       // depth bias multiplier [0.5 0.75 1.0 1.5 2.0 3.0]
#define SSS_FALLOFF 1.0             // how fast light fades through subsurface materials [0.25 0.5 1.0 2.0 4.0]
#define SSS_CONTRIBUTION 1.0        // strength of the subsurface terms [0.0 0.25 0.5 0.75 1.0]
#define DIFFUSE_WRAP 0.5            // wrap lighting of subsurface materials [0.0 0.1 0.25 0.5 0.75 1.0]

// ---------------------------------------------------------------- volumetrics (light shafts)
#define VOLUMETRIC_FOG              // froxel fog with shadowed in-scattering
#define VOLUME_QUALITY 2            // [0 1 2 3] froxel grid: low, medium, high, ultra (lib/look.glsl)
#define VOLUME_TEMPORAL             // reproject and accumulate the froxel shadows over frames
#define VOLUME_FAST_SHADOWS         // 1-2 texel PCF per froxel instead of the full cascade filter (froxels are blurred and accumulated anyway)
#define FOG_DENSITY_MUL 1.0         // multiplier on the fog density [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0]

// ---------------------------------------------------------------- materials / micro detail
//#define MICRO_DETAIL              // relief normals from the block textures where the resource pack gives no normal map (off by default: the user prefers flat texels)
#define MICRO_DETAIL_STRENGTH 1.0   // height scale of that relief [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#define PBR_TABLE                 // per-block roughness / metal guesses for blocks without a texture set; metal / gem blocks, obsidian and ores texel by texel like the texture sets (lib/surface.glsl). Lights and foliage keep emissive / subsurface anyway
#define EMISSIVE_STRENGTH 1.0       // emissive brightness multiplier [0.5 1.0 2.0 4.0 8.0]
#define EMISSIVE_BLOOM 6.0          // extra bloom input on emissive pixels (mob eyes, light blocks, lit particles) [0.0 2.0 4.0 6.0 8.0 12.0 16.0]

// ---------------------------------------------------------------- lighting
#define COLORED_LIGHT               // block light takes the colour of the lights around (soul, copper, redstone torches, soul fire...), lib/lightcolor.glsl
#define COLORED_LIGHT_SATURATION 1.5 // how strongly the light colours show
#define HAND_LIGHT                  // a torch, a lantern or another light in the player's hands lights the surroundings, in its colour
#define BLOCK_LIGHT_INTENSITY 1.0   // block light (torches, lamps) multiplier [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#define SKY_LIGHT_CURVE 0.5         // response to the sky lightmap: 0 = s^5 (darker shade), 1 = s^3 [0.0 0.25 0.5 0.75 1.0]
#define SKY_INTENSITY 1.0           // sky light multiplier [0.5 0.75 1.0 1.25 1.5 2.0]
#define SKY_AMBIENT_MUL 0.5         // share of the sky irradiance used as ambient light. 1.0 flattens the image (sky 1.5:1 to the sun instead of ~6:1) [0.25 0.5 0.75 1.0 1.25 1.5 2.0]

// ---------------------------------------------------------------- reflections
#define SSR                         // screen-space reflections
#define SSR_STEPS 96                // linear search steps of the reflection ray [32 64 96 128 256 400 800]
#define IBL                         // reflections of the pre-filtered sky probe

// ---------------------------------------------------------------- clouds / sky
#define CLOUD_LIGHTING              // lit clouds (sun scattering through the cloud cells)
#define CLOUD_DENSITY 0.35          // extinction inside a cloud cell [0.1 0.2 0.35 0.5 0.75 1.0]
#define CLOUD_PHASE_G 0.6           // forward scattering of the clouds (Henyey-Greenstein g) [0.0 0.3 0.6 0.75 0.85]
#define CLOUD_OPACITY 1.0           // extinction of the light crossing the cloud slab (0 = only the vanilla face alpha 0.8) [0.0 0.5 1.0 1.5 2.0 3.0]
#define SUN_DISC_INTENSITY 10.0     // brightness of the sun and moon discs relative to their light [1.0 5.0 10.0 20.0 50.0 100.0]
#define STAR_INTENSITY 1.0          // [0.0 0.5 1.0 2.0 4.0]

// ---------------------------------------------------------------- water
//#define WATER_TEXTURE             // the vanilla water texture drawn as a coloured layer on the surface. Off: only its relief is used
#define WATER_TEXTURE_OPACITY 0.6   // multiplier on the texture alpha (vanilla 0.7) [0.2 0.3 0.4 0.5 0.6 0.7 0.8 1.0]
#define WATER_TEXTURE_NORMALS       // wave relief and roughness from the water texture set (normal map + MERS), animated with the texture
#define WATER_CAUSTICS              // caustics under the water surface
//#define WATER_WAVES               // procedural waves (iterated directional sine octaves) mixed into the relief

// ---------------------------------------------------------------- post processing
#define TAA                         // stabilized native-resolution temporal anti-aliasing
#define RENDER_SCALE 100 // internal scene resolution per axis; 85 is experimental [100 85]
#define TAA_SHARPNESS 0.25           // detail recovery, not fed back into history [0.0 0.1 0.2 0.25 0.35 0.5]
#define ENTITY_MOTION                // motion vectors of mobs, players and their limbs for the TAA (vertex tracking, lib/entitymotion.glsl)
#define TAA_ANTI_FLICKER             // edges between two still surfaces no longer blink once every 8 frames (mostly at 85 %): the odd jitter phase holds the history
#define TAA_BLEND 0.93                // history weight [0.8 0.85 0.9 0.93 0.95]
#define BLOOM                        // dual-filter bloom
#define BLOOM_INTENSITY 0.02         // [0.0 0.01 0.02 0.04 0.06 0.1 0.2]
#define BLOOM_THRESHOLD 0.0          // bloom threshold (x average luminance) [0.0 0.5 1.0 2.0 4.0]
#define AUTO_EXPOSURE                // histogram auto exposure
#define EXPOSURE_EV 1.0              // exposure compensation in EV [-2.0 -1.5 -1.0 -0.5 0.0 0.5 1.0 1.5 2.0 2.5 3.0]
#define LOCAL_EXPOSURE               // local exposure (bilateral grid): brightens shade, holds back highlights
#define LOCAL_EXPOSURE_STRENGTH 0.5  // [0.0 0.25 0.5 0.75 1.0]
#define TONEMAP_OPERATOR 5           // 0 Reinhard, 1 extended Reinhard, 2 luminance Reinhard, 3 Hable, 4 ACES fit, 5 Lottes [0 1 2 3 4 5]
#define TONEMAP_CONTRAST 1.25        // Lottes curve: contrast [1.0 1.1 1.2 1.25 1.3 1.4 1.5 1.6]
#define TONEMAP_HDR_MAX 16.0         // Lottes curve: white point [4.0 8.0 16.0 32.0 64.0]
#define TONEMAP_MID_OUT 0.18         // Lottes curve: output of mid grey [0.14 0.16 0.18 0.2 0.22 0.25 0.267]
#define TONEMAP_CROSSTALK 4.0        // Lottes curve: how fast bright colours move towards white [1.0 2.0 4.0 8.0]
#define GRADE_CONTRAST 1.15          // contrast around the average luminance [1.0 1.05 1.1 1.15 1.2 1.25 1.3]
#define GRADE_SATURATION 1.05        // [0.8 0.9 1.0 1.05 1.1 1.2 1.3]
#define GRADE_GAMMA 2.2              // display gamma [1.8 2.0 2.2 2.4]
#define COLOR_TEMPERATURE 6500       // white balance target (K) [4000 4500 4800 5000 5500 6000 6500 7000 7500 8000]
#define COLOR_TEMPERATURE_ON         // white balance
#define BIOME_GRADING 1             // colour temperature per biome family: 0 off, 1 all day, 2 around sunrise and sunset only [0 1 2]
#define END_SKY_GAIN 0.1            // brightness of the End sky as seen (not of its light on the islands) [0.05 0.1 0.15 0.2 0.3 0.5 1.0]

// ---------------------------------------------------------------- debug
#define DEBUG_VIEW 0                 // [0 1 2 3 4 5 6 7 8] 0 off, 1 albedo, 2 normal, 3 roughness, 4 shadow, 5 volume in-scatter, 6 exposure, 7 sky ambient, 8 block outline (magenta line, cyan mark)

// Internal compatibility support is always active; not a user option.
#define MOD_COMPAT (1)

// Optional cloud transmission and solar optics.
#define CLOUD_SOLAR_RIM 1 // [0 1]
#define CLOUD_RIM_STRENGTH 1.0 // [0.5 1.0 1.5 2.0]

// Optional optical spread; existing general bloom stays unchanged.
#define SUN_LIGHT_BLEED 1 // [0 1]
#define SUN_HALO_STRENGTH 0.6 // the sky's glow around the sun near sunrise and sunset (the sun mie); 1 = its full strength [0.0 0.3 0.45 0.6 0.8 1.0]
#define SUN_GLOW_STRENGTH 0.6 // the soft glow of the visible sun and moon discs [0.0 0.3 0.5 0.6 0.8 1.0 1.5 2.0]
#define CLOUD_RIM_STYLE 1 // [0 1]
