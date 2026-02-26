#version 330 compatibility

// Fallback defaults — Iris will override these with slider values from shaders.properties

#define WAVE_AMPLITUDE 0.05 // [0.00 0.01 0.02 0.03 0.05 0.08 0.12 0.15 0.20 0.25 0.30]
#define WAVE_SPEED 1.5 // [0.0 0.5 0.8 1.0 1.2 1.5 1.8 2.0 2.5 3.0 4.0 5.0]
#define WAVE_FREQUENCY 1.0 // [0.2 0.4 0.6 0.8 1.0 1.2 1.5 1.8 2.0 2.5 3.0 4.0]


out vec2 texcoord;
out vec2 lmcoord;
out vec4 glColor;
out vec3 wpos;

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 colorOut;

uniform sampler2D texture;
uniform sampler2D lightmap;

uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform float frameTimeCounter;
uniform int isEyeInWater;
uniform mat4 gbufferModelViewInverse;


// -----------------------------------------------
// WATER APPEARANCE SETTINGS
// -----------------------------------------------
// How blurry/rough the reflections are. 0.0 = mirror, 1.0 = very rough.
// Real lakes sit around 0.08–0.15. Choppy sea ~0.25.
#define WATER_ROUGHNESS 0.12

// Overall reflection brightness. 1.0 = physically based, lower = more transparent look.
#define REFLECTION_STRENGTH 0.65

// Deep water base tint (what you see looking straight down)
#define WATER_DEEP_COLOR vec3(0.04, 0.18, 0.32)

// Shallow water tint (at grazing angles near shore)
#define WATER_SHALLOW_COLOR vec3(0.15, 0.42, 0.55)

// -----------------------------------------------
// NORMAL HELPERS
// -----------------------------------------------

// Returns a single layer of normal perturbation using a scrolling sine field.
vec2 waveNormalLayer(vec3 worldPos, float time, float scale, float speed, vec2 dir) {
    vec2 uv = worldPos.xz * scale + dir * time * speed;
    float dx = cos(uv.x + sin(uv.y * 0.7));
    float dz = sin(uv.y + cos(uv.x * 0.7));
    return vec2(dx, dz);
}

// Multi-layer normal to break up the mirror look.
vec3 getWaterNormal(vec3 worldPos) {
    float time = frameTimeCounter;
    float freq = WAVE_FREQUENCY;

    // Three overlapping wave layers at different scales/directions
    vec2 n1 = waveNormalLayer(worldPos, time, freq * 1.0,  1.2, vec2(1.0,  0.4));
    vec2 n2 = waveNormalLayer(worldPos, time, freq * 1.7,  0.9, vec2(-0.5, 1.0));
    vec2 n3 = waveNormalLayer(worldPos, time, freq * 0.4,  0.5, vec2(0.3, -0.8));

    // Blend and scale by roughness — rougher water = stronger normal deflection
    float strength = WATER_ROUGHNESS * 0.15;
    vec2 combined = (n1 * 0.5 + n2 * 0.3 + n3 * 0.2) * strength;

    return normalize(vec3(-combined.x, 1.0, -combined.y));
}

// -----------------------------------------------
// MAIN
// -----------------------------------------------
void main() {
    // Original Minecraft texture & biome tint
    vec4 albedo = texture2D(texture, texcoord) * glColor;

    // View direction (from camera toward the surface)
    vec3 viewDir = normalize(wpos - cameraPosition);

    vec3 normal = getWaterNormal(wpos);
    if (isEyeInWater == 1) normal = -normal;

    // -----------------------------------------------
    // FRESNEL — controls how reflective the surface is
    // at different viewing angles.
    // -----------------------------------------------
    float NdotV = max(dot(normal, -viewDir), 0.0);

    // Standard Schlick approximation.
    // F0 = 0.02 is physically correct for water.
    // We cap the max at REFLECTION_STRENGTH so it never goes full mirror.
    float fresnel = 0.02 + (REFLECTION_STRENGTH - 0.02) * pow(1.0 - NdotV, 5.0);

    // -----------------------------------------------
    // ROUGH SKY REFLECTION
    // We jitter the reflection direction using the normal's XZ
    // to simulate surface roughness.
    // -----------------------------------------------
    vec3 worldSunDir = normalize(mat3(gbufferModelViewInverse) * sunPosition);

    // Primary reflection direction
    vec3 reflDir = reflect(viewDir, normal);

    // Build a simple tangent frame to jitter the reflection
    vec3 up      = abs(reflDir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, reflDir));
    vec3 bitang  = cross(reflDir, tangent);

    // Roughness-driven jitter — bigger WATER_ROUGHNESS = more spread
    float spread = WATER_ROUGHNESS * 0.5;
    vec3 jitter  = tangent * normal.x * spread + bitang * normal.z * spread;
    vec3 roughReflDir = normalize(reflDir + jitter);

    // Sky gradient sampled along the rough reflection direction
    vec3 horizonCol = vec3(0.55, 0.78, 0.95);
    vec3 zenithCol  = vec3(0.08, 0.30, 0.72);
    vec3 sunsetCol  = vec3(0.80, 0.55, 0.25);

    float upFactor     = clamp(roughReflDir.y, 0.0, 1.0);
    float sunsetFactor = pow(clamp(1.0 - abs(roughReflDir.y), 0.0, 1.0), 4.0);
    vec3 skyRefl = mix(horizonCol, zenithCol, upFactor);
    skyRefl = mix(skyRefl, sunsetCol, sunsetFactor * 0.35);

    // -----------------------------------------------
    // SPECULAR HIGHLIGHT (sun glint)
    // -----------------------------------------------
    float sunDot  = max(dot(roughReflDir, worldSunDir), 0.0);
    float glintSharpness = mix(2000.0, 80.0, WATER_ROUGHNESS * 3.0);
    float sunGlint = pow(sunDot, glintSharpness) * mix(8.0, 1.5, WATER_ROUGHNESS * 2.0);
    skyRefl += vec3(1.0, 0.92, 0.75) * sunGlint;

    // -----------------------------------------------
    // WATER BODY COLOR
    // -----------------------------------------------
    vec3 waterBodyColor = mix(WATER_DEEP_COLOR, WATER_SHALLOW_COLOR, pow(1.0 - NdotV, 3.0));

    // Blend the Minecraft albedo into the body color so biome tints still show
    waterBodyColor = mix(waterBodyColor, albedo.rgb, 0.25);

    // -----------------------------------------------
    // COMBINE
    // -----------------------------------------------
    vec3 finalColor = mix(waterBodyColor, skyRefl, fresnel);

    // Apply lightmap so underwater caves stay dark
    vec3 lm = texture2D(lightmap, lmcoord).rgb;
    finalColor *= max(lm, vec3(0.04));

    // Alpha: more opaque at grazing angles, more transparent looking straight down
    float alpha = mix(albedo.a * 0.75, 0.92, fresnel);
    if (isEyeInWater == 1) {
        alpha = albedo.a;
        finalColor = mix(finalColor, albedo.rgb * lm, 0.4);
    }

    colorOut = vec4(finalColor, alpha);
}