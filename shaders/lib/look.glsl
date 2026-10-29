#ifndef LOOK_GLSL
#define LOOK_GLSL
// Look parameters: the numbers that define how the sky, the sun and the moon look over a day.
//
// These are appearance data (light levels, colours, fog densities...), kept apart from the code so the look can be
// retuned without touching any algorithm.
//
// The day phase d: 0 = noon, 0.25 = sunset, 0.5 = midnight, 0.75 = sunrise. Colours are 0..255 sRGB triplets.
#include "/lib/common.glsl"

// ------------------------------------------------------------------ the day (overworld)
// Every curve holds DAY_SAMPLES values over the day phase d, one every 1/DAY_STEPS of a day (15 game minutes), the
// last equal to the first; lib/daylight.glsl reads them with linear interpolation (DAYCURVE).
// Illuminances, sky colours (sRGB 0..255), Rayleigh strength, sun halo strength and lobe
// width (the lobe uses cos^(1 / width)), and the elevations where the horizon colour and the halo have faded.
const int DAY_STEPS = 96;
#define DAY_SAMPLES 97
const float SUN_LUX[DAY_SAMPLES] = float[DAY_SAMPLES](100.0, 100.0, 100.0, 100.0, 100.0, 99.1, 94.7, 90.2, 85.8, 81.3, 76.9, 72.4,
    68.0, 63.6, 59.1, 54.7, 50.2, 45.8, 41.3, 36.9, 32.4, 28.0, 23.5, 19.1,
    14.7, 10.2, 5.77, 1.32, 0.0067, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.975, 5.36, 9.82,
    14.3, 18.7, 23.2, 27.7, 32.1, 36.6, 41.1, 45.5, 50.0, 54.5, 58.9, 63.4,
    67.9, 72.3, 76.8, 81.3, 85.7, 90.2, 94.6, 99.1, 100.0, 100.0, 100.0, 100.0,
    100.0);
const vec3 SUN_TINT[DAY_SAMPLES] = vec3[DAY_SAMPLES](vec3(255.0, 227.0, 215.0), vec3(255.0, 223.0, 205.0), vec3(255.0, 219.0, 195.0), vec3(255.0, 215.0, 185.0), vec3(255.0, 211.0, 175.0), vec3(255.0, 207.0, 165.0),
    vec3(255.0, 203.0, 156.0), vec3(255.0, 199.0, 146.0), vec3(255.0, 195.0, 136.0), vec3(255.0, 191.0, 126.0), vec3(255.0, 187.0, 116.0), vec3(255.0, 183.0, 106.0),
    vec3(255.0, 179.0, 96.0), vec3(255.0, 175.0, 86.0), vec3(255.0, 172.0, 81.0), vec3(255.0, 169.0, 81.0), vec3(255.0, 167.0, 81.0), vec3(255.0, 164.0, 81.0),
    vec3(255.0, 162.0, 82.0), vec3(255.0, 159.0, 82.0), vec3(255.0, 157.0, 82.0), vec3(255.0, 153.0, 76.0), vec3(255.0, 142.0, 43.0), vec3(255.0, 131.0, 11.0),
    vec3(255.0, 127.0, 0.0), vec3(255.0, 127.0, 0.0), vec3(255.0, 128.0, 5.0), vec3(255.0, 134.0, 40.0), vec3(255.0, 140.0, 76.0), vec3(255.0, 147.0, 111.0),
    vec3(255.0, 153.0, 147.0), vec3(255.0, 152.0, 147.0), vec3(255.0, 149.0, 139.0), vec3(255.0, 147.0, 131.0), vec3(255.0, 144.0, 122.0), vec3(255.0, 141.0, 114.0),
    vec3(255.0, 139.0, 106.0), vec3(255.0, 136.0, 97.0), vec3(255.0, 133.0, 89.0), vec3(255.0, 131.0, 81.0), vec3(255.0, 128.0, 72.0), vec3(255.0, 125.0, 64.0),
    vec3(255.0, 123.0, 56.0), vec3(255.0, 120.0, 47.0), vec3(255.0, 117.0, 39.0), vec3(255.0, 115.0, 31.0), vec3(255.0, 112.0, 22.0), vec3(255.0, 109.0, 14.0),
    vec3(255.0, 107.0, 6.0), vec3(255.0, 105.0, 2.0), vec3(255.0, 107.0, 9.0), vec3(255.0, 108.0, 15.0), vec3(255.0, 110.0, 22.0), vec3(255.0, 111.0, 28.0),
    vec3(255.0, 112.0, 35.0), vec3(255.0, 114.0, 42.0), vec3(255.0, 115.0, 48.0), vec3(255.0, 117.0, 55.0), vec3(255.0, 118.0, 61.0), vec3(255.0, 119.0, 68.0),
    vec3(255.0, 121.0, 74.0), vec3(255.0, 122.0, 81.0), vec3(255.0, 123.0, 88.0), vec3(255.0, 125.0, 94.0), vec3(255.0, 126.0, 101.0), vec3(255.0, 128.0, 107.0),
    vec3(255.0, 129.0, 114.0), vec3(255.0, 130.0, 120.0), vec3(255.0, 132.0, 127.0), vec3(255.0, 133.0, 132.0), vec3(255.0, 138.0, 126.0), vec3(255.0, 143.0, 119.0),
    vec3(255.0, 148.0, 113.0), vec3(255.0, 153.0, 106.0), vec3(255.0, 158.0, 100.0), vec3(255.0, 163.0, 93.0), vec3(255.0, 168.0, 87.0), vec3(255.0, 173.0, 82.0),
    vec3(255.0, 176.0, 89.0), vec3(255.0, 179.0, 96.0), vec3(255.0, 182.0, 103.0), vec3(255.0, 185.0, 110.0), vec3(255.0, 187.0, 117.0), vec3(255.0, 190.0, 124.0),
    vec3(255.0, 193.0, 131.0), vec3(255.0, 196.0, 138.0), vec3(255.0, 199.0, 145.0), vec3(255.0, 202.0, 152.0), vec3(255.0, 204.0, 159.0), vec3(255.0, 207.0, 166.0),
    vec3(255.0, 210.0, 173.0), vec3(255.0, 213.0, 180.0), vec3(255.0, 216.0, 187.0), vec3(255.0, 219.0, 194.0), vec3(255.0, 221.0, 201.0), vec3(255.0, 224.0, 208.0),
    vec3(255.0, 227.0, 215.0));
const float MOON_LUX[DAY_SAMPLES] = float[DAY_SAMPLES](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1333, 0.3, 0.4, 0.4,
    0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4,
    0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4,
    0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4,
    0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.2778,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0);
const vec3 SKY_TOP[DAY_SAMPLES] = vec3[DAY_SAMPLES](vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0),
    vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0),
    vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0),
    vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(99.0, 125.0, 163.0), vec3(95.0, 119.0, 154.0), vec3(91.0, 113.0, 145.0), vec3(87.0, 107.0, 136.0),
    vec3(82.0, 100.0, 127.0), vec3(78.0, 94.0, 118.0), vec3(74.0, 88.0, 109.0), vec3(69.0, 82.0, 101.0), vec3(65.0, 76.0, 92.0), vec3(61.0, 70.0, 83.0),
    vec3(57.0, 64.0, 74.0), vec3(52.0, 57.0, 65.0), vec3(48.0, 51.0, 56.0), vec3(44.0, 45.0, 47.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0),
    vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0),
    vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0),
    vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0),
    vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0),
    vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 41.0, 41.0), vec3(45.0, 47.0, 50.0), vec3(49.0, 53.0, 58.0), vec3(53.0, 59.0, 67.0),
    vec3(57.0, 65.0, 76.0), vec3(61.0, 71.0, 84.0), vec3(66.0, 77.0, 93.0), vec3(70.0, 83.0, 102.0), vec3(74.0, 89.0, 110.0), vec3(78.0, 95.0, 119.0),
    vec3(83.0, 101.0, 128.0), vec3(87.0, 107.0, 137.0), vec3(91.0, 113.0, 145.0), vec3(95.0, 119.0, 154.0), vec3(99.0, 125.0, 163.0), vec3(103.0, 130.0, 170.0),
    vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0),
    vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0),
    vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0), vec3(103.0, 130.0, 170.0),
    vec3(103.0, 130.0, 170.0));
const vec3 SKY_RIM[DAY_SAMPLES] = vec3[DAY_SAMPLES](vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0),
    vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0),
    vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(195.0, 188.0, 188.0),
    vec3(208.0, 187.0, 178.0), vec3(220.0, 186.0, 168.0), vec3(232.0, 185.0, 158.0), vec3(244.0, 184.0, 150.0), vec3(250.0, 186.0, 157.0), vec3(254.0, 186.0, 163.0),
    vec3(221.0, 164.0, 147.0), vec3(187.0, 142.0, 132.0), vec3(154.0, 120.0, 116.0), vec3(138.0, 111.0, 115.0), vec3(142.0, 119.0, 131.0), vec3(146.0, 126.0, 147.0),
    vec3(150.0, 133.0, 163.0), vec3(154.0, 141.0, 179.0), vec3(157.0, 148.0, 195.0), vec3(161.0, 156.0, 211.0), vec3(165.0, 163.0, 227.0), vec3(161.0, 164.0, 232.0),
    vec3(139.0, 151.0, 211.0), vec3(118.0, 138.0, 190.0), vec3(96.0, 125.0, 169.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0),
    vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0),
    vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0),
    vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0),
    vec3(96.0, 123.0, 174.0), vec3(113.0, 130.0, 197.0), vec3(130.0, 138.0, 219.0), vec3(147.0, 145.0, 238.0), vec3(162.0, 154.0, 238.0), vec3(178.0, 163.0, 238.0),
    vec3(194.0, 171.0, 237.0), vec3(210.0, 180.0, 237.0), vec3(224.0, 188.0, 235.0), vec3(232.0, 194.0, 221.0), vec3(240.0, 200.0, 206.0), vec3(248.0, 206.0, 192.0),
    vec3(254.0, 211.0, 179.0), vec3(246.0, 212.0, 183.0), vec3(238.0, 212.0, 186.0), vec3(230.0, 213.0, 189.0), vec3(221.0, 210.0, 192.0), vec3(211.0, 204.0, 194.0),
    vec3(200.0, 199.0, 195.0), vec3(190.0, 193.0, 197.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0),
    vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0),
    vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0), vec3(183.0, 189.0, 198.0),
    vec3(183.0, 189.0, 198.0));
const float RAYLEIGH[DAY_SAMPLES] = float[DAY_SAMPLES](10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0,
    10.0, 10.0, 9.681, 9.213, 8.745, 8.277, 7.809, 7.341, 6.873, 6.404, 5.936, 5.468,
    5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0,
    5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0,
    5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0,
    5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.032, 5.277, 5.523,
    5.769, 6.015, 6.261, 6.506, 6.752, 6.998, 7.244, 7.49, 7.735, 7.981, 8.227, 8.473,
    8.718, 8.964, 9.21, 9.456, 9.702, 9.947, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0,
    10.0);
const float HALO_STRENGTH[DAY_SAMPLES] = float[DAY_SAMPLES](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.125, 0.281, 0.437, 0.594,
    0.75, 0.698, 0.646, 0.594, 0.542, 0.49, 0.438, 0.385, 0.333, 0.281, 0.229, 0.177,
    0.125, 0.073, 0.021, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.021, 0.073,
    0.125, 0.177, 0.229, 0.281, 0.333, 0.385, 0.438, 0.49, 0.542, 0.594, 0.646, 0.698,
    0.75, 0.594, 0.437, 0.281, 0.125, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0);
const float HALO_WIDTH[DAY_SAMPLES] = float[DAY_SAMPLES](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0123, 0.0277, 0.043, 0.0584,
    0.0738, 0.0686, 0.0635, 0.0584, 0.0533, 0.0482, 0.043, 0.0379, 0.0328, 0.0277, 0.0225, 0.0174,
    0.0123, 0.0072, 0.002, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0014, 0.0049,
    0.0083, 0.0118, 0.0153, 0.0188, 0.0222, 0.0257, 0.0292, 0.0326, 0.0361, 0.0396, 0.0431, 0.0465,
    0.05, 0.0396, 0.0292, 0.0188, 0.0083, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0);
const float RIM_HEIGHT[DAY_SAMPLES] = float[DAY_SAMPLES](0.8, 0.788, 0.775, 0.763, 0.75, 0.738, 0.725, 0.713, 0.7, 0.688, 0.675, 0.663,
    0.65, 0.638, 0.625, 0.613, 0.6, 0.588, 0.575, 0.563, 0.55, 0.538, 0.525, 0.513,
    0.5, 0.449, 0.398, 0.347, 0.295, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25,
    0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25,
    0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25,
    0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25,
    0.25, 0.284, 0.318, 0.351, 0.385, 0.419, 0.453, 0.487, 0.511, 0.529, 0.547, 0.565,
    0.583, 0.601, 0.619, 0.637, 0.655, 0.674, 0.692, 0.71, 0.728, 0.746, 0.764, 0.782,
    0.8);
const float HALO_HEIGHT[DAY_SAMPLES] = float[DAY_SAMPLES](0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.521, 0.573,
    0.625, 0.677, 0.729, 0.781, 0.833, 0.885, 0.938, 0.99, 1.0, 1.0, 1.0, 1.0,
    1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
    1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
    1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
    1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
    1.0, 1.0, 1.0, 1.0, 1.0, 0.99, 0.938, 0.885, 0.833, 0.781, 0.729, 0.677,
    0.625, 0.573, 0.521, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5,
    0.5);
const float PALE_SUN_LUX[DAY_SAMPLES] = float[DAY_SAMPLES](5.0, 5.0, 5.0, 5.0, 5.0, 4.96, 4.74, 4.53, 4.31, 4.09, 3.88, 3.66,
    3.45, 3.23, 3.02, 2.8, 2.59, 2.37, 2.16, 1.94, 1.72, 1.51, 1.29, 1.08,
    0.8621, 0.6466, 0.431, 0.2155, 0.0067, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.195, 0.4113, 0.6277,
    0.8442, 1.06, 1.28, 1.49, 1.71, 1.93, 2.14, 2.36, 2.58, 2.79, 3.01, 3.23,
    3.44, 3.66, 3.87, 4.09, 4.31, 4.52, 4.74, 4.96, 5.0, 5.0, 5.0, 5.0,
    5.0);
const vec3 PALE_SKY_TOP[DAY_SAMPLES] = vec3[DAY_SAMPLES](vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0),
    vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0),
    vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0),
    vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(117.0, 122.0, 130.0), vec3(112.0, 116.0, 123.0), vec3(106.0, 110.0, 117.0), vec3(101.0, 104.0, 110.0),
    vec3(95.0, 98.0, 104.0), vec3(89.0, 92.0, 97.0), vec3(84.0, 87.0, 91.0), vec3(78.0, 81.0, 84.0), vec3(73.0, 75.0, 78.0), vec3(67.0, 69.0, 71.0),
    vec3(61.0, 63.0, 65.0), vec3(56.0, 57.0, 58.0), vec3(50.0, 51.0, 52.0), vec3(45.0, 45.0, 45.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0),
    vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0),
    vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0),
    vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0),
    vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0),
    vec3(40.0, 40.0, 40.0), vec3(40.0, 40.0, 40.0), vec3(41.0, 41.0, 41.0), vec3(46.0, 46.0, 47.0), vec3(51.0, 52.0, 53.0), vec3(57.0, 58.0, 60.0),
    vec3(62.0, 64.0, 66.0), vec3(68.0, 70.0, 72.0), vec3(73.0, 76.0, 79.0), vec3(79.0, 81.0, 85.0), vec3(84.0, 87.0, 92.0), vec3(90.0, 93.0, 98.0),
    vec3(95.0, 99.0, 104.0), vec3(101.0, 105.0, 111.0), vec3(106.0, 110.0, 117.0), vec3(112.0, 116.0, 123.0), vec3(117.0, 122.0, 130.0), vec3(122.0, 127.0, 135.0),
    vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0),
    vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0),
    vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0), vec3(122.0, 127.0, 135.0),
    vec3(122.0, 127.0, 135.0));
const vec3 PALE_SKY_RIM[DAY_SAMPLES] = vec3[DAY_SAMPLES](vec3(198.0, 195.0, 183.0), vec3(197.0, 195.0, 184.0), vec3(196.0, 194.0, 185.0), vec3(195.0, 194.0, 186.0), vec3(194.0, 194.0, 187.0), vec3(193.0, 193.0, 188.0),
    vec3(192.0, 193.0, 189.0), vec3(191.0, 192.0, 190.0), vec3(191.0, 192.0, 190.0), vec3(190.0, 192.0, 191.0), vec3(189.0, 191.0, 192.0), vec3(188.0, 191.0, 193.0),
    vec3(187.0, 191.0, 194.0), vec3(186.0, 190.0, 195.0), vec3(185.0, 190.0, 196.0), vec3(184.0, 189.0, 197.0), vec3(183.0, 189.0, 198.0), vec3(195.0, 188.0, 188.0),
    vec3(208.0, 187.0, 178.0), vec3(220.0, 186.0, 168.0), vec3(232.0, 185.0, 158.0), vec3(244.0, 184.0, 150.0), vec3(250.0, 186.0, 157.0), vec3(254.0, 186.0, 163.0),
    vec3(221.0, 164.0, 147.0), vec3(187.0, 142.0, 132.0), vec3(154.0, 120.0, 116.0), vec3(138.0, 111.0, 115.0), vec3(142.0, 119.0, 131.0), vec3(146.0, 126.0, 147.0),
    vec3(150.0, 133.0, 163.0), vec3(154.0, 141.0, 179.0), vec3(157.0, 148.0, 195.0), vec3(161.0, 156.0, 211.0), vec3(165.0, 163.0, 227.0), vec3(161.0, 164.0, 232.0),
    vec3(139.0, 151.0, 211.0), vec3(118.0, 138.0, 190.0), vec3(96.0, 125.0, 169.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0),
    vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0),
    vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0),
    vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0), vec3(83.0, 117.0, 157.0),
    vec3(96.0, 123.0, 174.0), vec3(113.0, 130.0, 197.0), vec3(130.0, 138.0, 219.0), vec3(147.0, 145.0, 238.0), vec3(162.0, 154.0, 238.0), vec3(178.0, 163.0, 238.0),
    vec3(194.0, 171.0, 237.0), vec3(210.0, 180.0, 237.0), vec3(224.0, 188.0, 235.0), vec3(232.0, 194.0, 221.0), vec3(240.0, 200.0, 206.0), vec3(248.0, 206.0, 192.0),
    vec3(254.0, 211.0, 179.0), vec3(246.0, 212.0, 183.0), vec3(238.0, 212.0, 186.0), vec3(230.0, 213.0, 189.0), vec3(223.0, 211.0, 190.0), vec3(216.0, 207.0, 188.0),
    vec3(209.0, 202.0, 186.0), vec3(203.0, 198.0, 184.0), vec3(198.0, 195.0, 183.0), vec3(198.0, 195.0, 183.0), vec3(198.0, 195.0, 183.0), vec3(198.0, 195.0, 183.0),
    vec3(198.0, 195.0, 183.0), vec3(198.0, 195.0, 183.0), vec3(198.0, 195.0, 183.0), vec3(198.0, 195.0, 183.0), vec3(198.0, 195.0, 183.0), vec3(198.0, 195.0, 183.0),
    vec3(198.0, 195.0, 183.0), vec3(198.0, 195.0, 183.0), vec3(198.0, 195.0, 183.0), vec3(198.0, 195.0, 183.0), vec3(198.0, 195.0, 183.0), vec3(198.0, 195.0, 183.0),
    vec3(198.0, 195.0, 183.0));
const vec3  MOON_TINT = vec3(163.0, 182.0, 255.0);
const float RIM_BELOW = 0.25;           // the horizon colour reaches this far below the horizon
// pale garden variant: sun and moon tint
const vec3  PALE_SUN_TINT  = vec3(195.0, 216.0, 255.0);
const vec3  PALE_MOON_TINT = vec3(217.0, 225.0, 255.0);

// ------------------------------------------------------------------ weather, fog, ambient
const float RAIN_SKY_GREY = 103.0;      // sky colour under rain
const float STORM_SKY_GREY = 51.0;      // sky colour under thunder, reached at 75 % of the thunder strength
const float STORM_SKY_WEIGHT = 0.75;
// falling snow, (a light snowfall in a snowy biome): the sky does not turn grey, its zenith
// stays a soft blue-lavender and the horizon, with the fog that takes its colour, turns pink; a light fog. Thunder
// over snow keeps the same look (no darker, foggier blizzard). Sky colours before the cold grading of snowy biomes,
// fitted so that after it the zenith, the middle of the sky and the horizon come out near the #7890D8,
// #C0A8CC and #E4C0CC (the rim is above 255: the horizon is brighter than the zenith)
const float SNOW_SKY_GREY = 190.0;   // the grey the weather blend passes through at a snow biome border
const vec3  SNOW_SKY_TOP = vec3(70.0, 84.0, 112.0);
const vec3  SNOW_SKY_RIM = vec3(325.0, 230.0, 205.0);
const float SNOW_FOG_DENSITY = 0.0003;   // extra exponential fog of the falling snow (m^-1)
const float AMBIENT_FLOOR = 0.02;       // minimum ambient light
const vec2  FOG_RANGE = vec2(0.92, 1.0);
const vec2  WEATHER_FOG_RANGE = vec2(0.23, 0.7);   // the weather fog (fog_default "weather"): 23 % to 70 % of the render distance// distance fog from 92 % to 100 % of the render distance

// ------------------------------------------------------------------ water caustics
const float CAUSTIC_FRAME_TIME = 0.09;  // seconds per frame of the caustic animation
const float CAUSTIC_SCALE = 0.5;        // pattern tiles per block
const float CAUSTIC_POWER = 1.0;        // contrast exponent (energy kept by the (p + 1) factor)
const float CAUSTIC_FRAMES = 64.0;      // frames stacked vertically in textures/caustics.png

// ------------------------------------------------------------------ shadow cascades (per SHADOW_QUALITY)
// extent: share of SHADOW_RANGE covered by each cascade; filter: PCF width in texels of a cascade of filterRes;
// bias / slope: depth bias as a fraction of the cascade size (constant / per tan of the light angle)
// (a single-pass shadow map, see lib/common.glsl SHADOW_SINGLE_PASS, always uses the one-cascade setup)
#if SHADOW_QUALITY == 0 || defined SHADOW_SINGLE_PASS
    const int CASCADES = 1;
    const float CASCADE_EXTENT[4] = float[4](1.0, 1.0, 1.0, 1.0);
    const float CASCADE_FILTER[4] = float[4](2.0, 2.0, 2.0, 2.0);
    const float CASCADE_BIAS_CONST[4] = float[4](0.000275, 0.000275, 0.000275, 0.000275);
    const float CASCADE_BIAS_SLOPE[4] = float[4](0.00001, 0.00001, 0.00001, 0.00001);
    const float CASCADE_FILTER_RES[4] = float[4](2048.0, 2048.0, 2048.0, 2048.0);
#elif SHADOW_QUALITY == 1
    const int CASCADES = 3;
    const float CASCADE_EXTENT[4] = float[4](0.25, 0.5, 1.0, 1.0);
    const float CASCADE_FILTER[4] = float[4](8.0, 4.0, 4.0, 4.0);
    const float CASCADE_BIAS_CONST[4] = float[4](0.000275, 0.0015, 0.00275, 0.00275);
    const float CASCADE_BIAS_SLOPE[4] = float[4](0.00003, 0.00004, 0.00004, 0.00004);
    const float CASCADE_FILTER_RES[4] = float[4](2048.0, 1024.0, 1024.0, 1024.0);
#elif SHADOW_QUALITY == 2
    const int CASCADES = 4;
    const float CASCADE_EXTENT[4] = float[4](1.0 / 6.0, 1.0 / 3.0, 0.5, 1.0);
    const float CASCADE_FILTER[4] = float[4](8.0, 8.0, 4.0, 4.0);
    const float CASCADE_BIAS_CONST[4] = float[4](0.000275, 0.0015, 0.00275, 0.003);
    const float CASCADE_BIAS_SLOPE[4] = float[4](0.00001, 0.00004, 0.00004, 0.00006);
    const float CASCADE_FILTER_RES[4] = float[4](2048.0, 2048.0, 1024.0, 1024.0);
#else
    const int CASCADES = 4;
    const float CASCADE_EXTENT[4] = float[4](1.0 / 6.0, 1.0 / 3.0, 0.5, 1.0);
    const float CASCADE_FILTER[4] = float[4](16.0, 8.0, 4.0, 4.0);
    const float CASCADE_BIAS_CONST[4] = float[4](0.000275, 0.0015, 0.00275, 0.003);
    const float CASCADE_BIAS_SLOPE[4] = float[4](0.00001, 0.00002, 0.00004, 0.00006);
    const float CASCADE_FILTER_RES[4] = float[4](2048.0, 2048.0, 2048.0, 2048.0);
#endif
// cloud shadow filter width per SHADOW_QUALITY
#if SHADOW_QUALITY == 0
    const float CLOUD_SHADOW_FILTER = 1.0;
#elif SHADOW_QUALITY == 1 || SHADOW_QUALITY == 2
    const float CLOUD_SHADOW_FILTER = 4.0;
#else
    const float CLOUD_SHADOW_FILTER = 16.0;
#endif
const float SHADOW_RANGE = 128.0;            // metres of shadowed terrain around the camera
const float CLOUD_SHADOW_STRENGTH = 0.4;     // darkest a cloud shadow gets: 1 - strength

// ------------------------------------------------------------------ froxel volume (per VOLUME_QUALITY)
// grid size in froxels (x, y follow the screen; z = depth slices) and the shadow filter scale of its samples
#if VOLUME_QUALITY == 3
    const ivec3 FROXEL_GRID = ivec3(240, 136, 96);
    const float FROXEL_SHADOW_FILTER = 1.0;
#elif VOLUME_QUALITY == 2
    const ivec3 FROXEL_GRID = ivec3(240, 136, 48);
    const float FROXEL_SHADOW_FILTER = 0.5;
#elif VOLUME_QUALITY == 1
    const ivec3 FROXEL_GRID = ivec3(120, 72, 64);
    const float FROXEL_SHADOW_FILTER = 0.25;
#else
    const ivec3 FROXEL_GRID = ivec3(32, 24, 32);
    const float FROXEL_SHADOW_FILTER = 0.125;
#endif
const vec2 FROXEL_RANGE = vec2(0.025, 250.0);   // view depth covered by the slices (m)

// ------------------------------------------------------------------ participating media
// air: density, scattering and absorption per channel, Henyey-Greenstein anisotropy, height up to which it is dense
const float AIR_DENSITY = 0.05;
const vec3  AIR_SCATTERING = vec3(0.04);
const vec3  AIR_ABSORPTION = vec3(0.0);
const float AIR_G = 0.6;
const float AIR_TOP = 320.0;
// pale garden fog
const float PALE_DENSITY = 0.07;
const vec3  PALE_SCATTERING = vec3(0.5);
const vec3  PALE_ABSORPTION = vec3(0.25, 0.125, 0.125);
const float PALE_G = 0.3;
// end fog
const float END_FOG_DENSITY = 0.25;
const float END_FOG_SCATTERING = 0.02;
const float END_FOG_G = 0.8;
// water: per-channel extinction of clear water (m^-1), its scattering share and anisotropy
const vec3  WATER_EXTINCTION = vec3(0.4655, 0.0584, 0.0113);
const vec3  WATER_SCATTERING = vec3(0.0011, 0.0019, 0.0045);
const float WATER_G = 0.8;
// camera under water: distance fog colour (pale garden variant), the distance where it is complete, and the share of
// that distance it starts from when the camera has just dived in (shaders.properties waterEyeAdapt, 0 -> 1 in ~30 s)
const vec3  UNDERWATER_FOG = vec3(68.0, 175.0, 245.0);
const vec3  PALE_UNDERWATER_FOG = vec3(85.0, 105.0, 128.0);
const float UNDERWATER_FOG_END = 60.0;
const float UNDERWATER_FOG_FIRST = 0.25;
// procedural waves (WATER_WAVES, off by default): octave count, time scale, speed of the first octave, crest
// exponent, domain warp along each wave, and per octave: amplitude x, frequency x, speed x, direction turn (rad)
const int   WAVE_OCTAVES = 28;
const float WAVE_TIME_SCALE = 0.5;
const float WAVE_SPEED = 2.0;
const float WAVE_SHARPNESS = 1.5;
const float WAVE_DRAG = 0.38;
const vec4  WAVE_OCTAVE_STEP = vec4(0.8, 1.2, 1.03, 1.399);
// camera in powder snow: fog colour and the distance (blocks) where it is complete
const vec3  POWDER_SNOW_FOG = vec3(159.0, 187.0, 200.0);
const float POWDER_SNOW_FOG_END = 2.0;
// exposure change (EV) with the camera in water / in powder snow (asked for, not in the base data)
const float UNDERWATER_EV = -0.75;
const float POWDER_SNOW_EV = 1.0;
// biome grading (deserts 4400 K, badlands 4800 K, shaders.properties) applies while the sun is within this height
// (sin of the elevation) of the horizon, fading out above it: the warm sunrises and sunsets of those biomes
const float BIOME_GRADE_SUN_HEIGHT = 0.35;
// camera in lava
const vec3  LAVA_FOG = vec3(153.0, 26.0, 0.0);
const float LAVA_FOG_GAIN = 4.0;
const float LAVA_FOG_END = 0.64;

// ------------------------------------------------------------------ reflections
const float PROBE_REFLECTION_GAIN = 0.5;   // strength of the sky probe in reflections
const float BLOCK_LIGHT_REFLECTION = 0.05; // block light reflected by metals when the sky probe is darker
const vec2  PROBE_SKY_FADE = vec2(12.0, 15.0);   // sky light levels over which the probe fades in (cubic)

// screen-space reflections: depth thickness of a hit (fraction of the depth), share of the ray length after which
// the reflection fades out, roughness above which there is none and where its fade starts
const float SSR_THICKNESS = 0.025;
const float SSR_FADE_LENGTH = 0.75;
const float SSR_ROUGH_CUTOFF = 0.4;
const float SSR_ROUGH_FADE_START = 0.3;

// ------------------------------------------------------------------ clouds and sky objects
const float RAIN_CLOUD_GREY = 191.0;    // cloud colour under rain (reached at 95 % of the rain strength)
const float STORM_CLOUD_GREY = 30.0;    // cloud colour under thunder
const float CLOUD_WEATHER_WEIGHT = 0.95;
const float CLOUD_FOG_START = 0.9;      // clouds fade into the sky from 90 % of their draw distance
const float CLOUD_REFLECTION = 0.25;    // strength of the sky reflection on clouds
const float STAR_BRIGHTNESS = 0.05;
const float MOON_MIN_LUX = 0.05;        // the moon disc stays visible while the moon light is off
const float KEY_HORIZON_FADE = 0.105;   // sine of the elevation (6 degrees) over which the sun's and the moon's direct light fade at the horizon

// ------------------------------------------------------------------ automatic exposure
const float HIST_MIN_LOG2 = -3.0;          // log2 luminance of the first histogram bin
const float HIST_LOG2_RANGE = 20.0;        // log2 range covered by the bins
const vec2  HIST_PERCENTILES = vec2(0.80, 1.00);   // the average is taken over this part of the histogram
const float ADAPT_RATE = 1.0;              // per second
const vec2  ADAPT_SPEED = vec2(1.0, 1.0);  // towards brighter, towards darker
const vec2  EXPOSURE_AVG_CLAMP = vec2(0.125, 16.0);   // range of the average used for the exposure
// dusk and dawn (program/final.glsl duskExposureFloor): the exposure stops making up for all of the fading sun, so the
// picture darkens little by little through the sunset instead of holding the daylight brightness and then dropping
// once the average reaches its lower clamp. For a view of the sky at sunset the floor is the lower clamp plus
// DUSK_EXPOSURE_FLOOR.x x (sun illuminance)^.y: fitted so the sky comes down in a straight line over the whole dusk
// (some 900 ticks), from its daylight brightness with the sun at the horizon to the night's when the sun's light ends
// (where the floor meets the clamp, so the night is as before). Any other view gets the same darkening: its floor is
// scaled by its own average against the average such a view of the sky has at that light (DUSK_EXPOSURE_REF.x x
// illuminance^.y, set a little low so that view itself gets all of it), and never above the sky's. Faded in between
// these day phases (distance from noon), outdoors only
const vec2  DUSK_EXPOSURE_FLOOR = vec2(0.137, 0.762);
const vec2  DUSK_EXPOSURE_REF = vec2(0.0196, 1.463);
const vec2  DUSK_EXPOSURE_PHASES = vec2(0.20, 0.235);

// ------------------------------------------------------------------ materials
// surface without a texture set: not metallic, not emissive, fully rough, no subsurface
const vec4 DEFAULT_MATERIAL = vec4(0.0, 0.0, 1.0, 0.0);   // metal, emissive, roughness, subsurface

// ------------------------------------------------------------------ other dimensions
const vec3  NETHER_SKY = vec3(51.0, 8.0, 8.0);
const float NETHER_RAYLEIGH = 0.15;
const vec2  NETHER_FOG_BLOCKS = vec2(10.0, 96.0);
const float NETHER_AMBIENT = 0.5;
const vec3  END_SKY_TOP = vec3(22.0, 17.0, 36.0);
const vec3  END_SKY_RIM = vec3(1.0, 1.0, 5.0);
const float END_RAYLEIGH = 50.0;
const float END_AMBIENT = 0.125;
const vec3  END_FLASH_TINT = vec3(228.0, 93.0, 255.0);   // the End flash: the only direct light there
const float END_FLASH_LUX = 3.0;
// what the End sky texture leaves of the sky gradient on average: end_sky.png (linear mean 0.200) x its vertex colour
// 0x282828. The fog and the sky probe take this share, the sky itself the real texture (deferred); with the bare
// gradient the End fog was a bright lilac haze, ~30 times the sky behind it
const float END_SKY_TEXTURE_MEAN = 0.0314;
// brightness of the End sky as seen (and of the distance fog that takes its colour), not of the light it gives the
// islands: the End is dark (distance fog #0B080C, horizon 1 1 5); at 1 the noise of the sky texture was
// brighter than the end stone once the dragon's darkening of the screen was gone
// (END_SKY_GAIN: lib/settings.glsl)
const float OTHER_DIM_LUX = 100.0;      // the (invisible) sun / moon terms of the Nether and the End sky

#endif
