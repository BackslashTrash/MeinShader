#version 330 compatibility

#define WAVE_AMPLITUDE 0.05 // [0.00 0.01 0.02 0.03 0.05 0.08 0.12 0.15 0.20 0.25 0.30]
#define WAVE_SPEED 1.5      // [0.0 0.5 0.8 1.0 1.2 1.5 1.8 2.0 2.5 3.0 4.0 5.0]
#define WAVE_FREQUENCY 1.0  // [0.2 0.4 0.6 0.8 1.0 1.2 1.5 1.8 2.0 2.5 3.0 4.0]

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glColor;
in vec3 wpos;
in vec3 viewPos; // view-space position from vsh

/* DRAWBUFFERS:013 */
layout(location = 0) out vec4 colorOut;   // colortex0: water base color
layout(location = 1) out vec4 normalOut;  // colortex1: encoded normal
layout(location = 2) out vec4 dataOut;    // colortex3: r=isWater, g=fresnel

uniform sampler2D lightmap;
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform float frameTimeCounter;
uniform int isEyeInWater;
uniform mat4 gbufferModelViewInverse;

#define WATER_ROUGHNESS 0.04
#define WATER_DEEP_COLOR vec3(0.01, 0.08, 0.20)
#define WATER_SHALLOW_COLOR vec3(0.02, 0.18, 0.38)

// -----------------------------------------------
// HASH & NOISE PRIMITIVES
// -----------------------------------------------

vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)),
    dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

// Smooth value noise returning a float in [-1, 1]
float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f); // smoothstep

    float a = dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
    float b = dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
    float c = dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
    float d = dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// -----------------------------------------------
// FRACTAL BROWNIAN MOTION WATER NORMAL
// Each octave adds finer ripple detail.
// WAVE_FREQUENCY controls the base scale.
// WAVE_ROUGHNESS controls how much the normal deflects.
// -----------------------------------------------
vec3 getWaterNormal(vec3 worldPos) {
    float time = frameTimeCounter;
    float freq = WAVE_FREQUENCY;

    // Tiny epsilon for finite-difference normal reconstruction
    const float eps = 0.05;

    // fBm height function — samples multiple octaves of noise
    // at a given XZ position to produce a wave height
    #define FBM_HEIGHT(px, pz) (                                        \
        vnoise(vec2(px, pz) * freq * 1.0  + vec2( 1.0,  0.4) * time * 0.8) * 0.50 + \
        vnoise(vec2(px, pz) * freq * 2.1  + vec2(-0.5,  1.0) * time * 1.1) * 0.25 + \
        vnoise(vec2(px, pz) * freq * 4.3  + vec2( 0.3, -0.8) * time * 1.6) * 0.125 + \
        vnoise(vec2(px, pz) * freq * 8.7  + vec2(-0.7,  0.5) * time * 2.2) * 0.0625 \
    )

    // Sample height at three nearby points and reconstruct the surface normal
    // using finite differences — standard technique for bump mapping
    float hC  = FBM_HEIGHT(worldPos.x,       worldPos.z      );
    float hX  = FBM_HEIGHT(worldPos.x + eps, worldPos.z      );
    float hZ  = FBM_HEIGHT(worldPos.x,       worldPos.z + eps);

    #undef FBM_HEIGHT

    // dX and dZ are the slope of the surface in each axis
    float dX = (hX - hC) / eps;
    float dZ = (hZ - hC) / eps;

    // Scale by roughness — higher = more choppy normal deflection
    dX *= WATER_ROUGHNESS * 8.0;
    dZ *= WATER_ROUGHNESS * 8.0;

    return normalize(vec3(-dX, 1.0, -dZ));
}

void main() {
    vec3 viewDir = normalize(wpos - cameraPosition);
    vec3 normal  = getWaterNormal(wpos);
    if (isEyeInWater == 1) normal = -normal;

    float NdotV  = max(dot(normal, -viewDir), 0.0);
    float fresnel = 0.02 + 0.98 * pow(1.0 - NdotV, 5.0);
    fresnel = max(fresnel, 0.5);

    vec3 lm = texture2D(lightmap, lmcoord).rgb;
    vec3 waterBodyColor = mix(WATER_DEEP_COLOR, WATER_SHALLOW_COLOR, pow(1.0 - NdotV, 2.0));
    waterBodyColor *= max(lm, vec3(0.02));

    // Write base color, encoded normal, and water flag
    colorOut  = vec4(waterBodyColor, 1.0);
    normalOut = vec4(normal * 0.5 + 0.5, 1.0);
    dataOut   = vec4(1.0, fresnel, 0.0, 1.0); // r=1.0 = is water
}