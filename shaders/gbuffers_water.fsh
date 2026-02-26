#version 330 compatibility

#define WAVE_AMPLITUDE 0.05 // [0.00 0.01 0.02 0.03 0.05 0.08 0.12 0.15 0.20 0.25 0.30]
#define WAVE_SPEED 1.5      // [0.0 0.5 0.8 1.0 1.2 1.5 1.8 2.0 2.5 3.0 4.0 5.0]
#define WAVE_FREQUENCY 1.0  // [0.2 0.4 0.6 0.8 1.0 1.2 1.5 1.8 2.0 2.5 3.0 4.0]

// ---- INPUTS from vertex shader ----
in vec2 texcoord;
in vec2 lmcoord;
in vec4 glColor;
in vec3 wpos;

// ---- OUTPUT ----
/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 colorOut;

// ---- UNIFORMS ----
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
#define WATER_ROUGHNESS 0.08
#define REFLECTION_STRENGTH 0.85
#define WATER_DEEP_COLOR vec3(0.0, 0.25, 0.55)
#define WATER_SHALLOW_COLOR vec3(0.0, 0.55, 0.75)

// -----------------------------------------------
// NORMAL HELPERS
// -----------------------------------------------
vec2 waveNormalLayer(vec3 worldPos, float time, float scale, float speed, vec2 dir) {
    vec2 uv = worldPos.xz * scale + dir * time * speed;
    float dx = cos(uv.x + sin(uv.y * 0.7));
    float dz = sin(uv.y + cos(uv.x * 0.7));
    return vec2(dx, dz);
}

vec3 getWaterNormal(vec3 worldPos) {
    float time = frameTimeCounter;
    float freq = WAVE_FREQUENCY;

    vec2 n1 = waveNormalLayer(worldPos, time, freq * 1.0, 1.2, vec2(1.0,  0.4));
    vec2 n2 = waveNormalLayer(worldPos, time, freq * 1.7, 0.9, vec2(-0.5, 1.0));
    vec2 n3 = waveNormalLayer(worldPos, time, freq * 0.4, 0.5, vec2(0.3, -0.8));

    float strength = WATER_ROUGHNESS * 0.15;
    vec2 combined = (n1 * 0.5 + n2 * 0.3 + n3 * 0.2) * strength;

    return normalize(vec3(-combined.x, 1.0, -combined.y));
}

// -----------------------------------------------
// MAIN
// -----------------------------------------------
void main() {
    vec4 albedo = texture2D(texture, texcoord) * glColor;

    vec3 viewDir = normalize(wpos - cameraPosition);
    vec3 normal  = getWaterNormal(wpos);
    if (isEyeInWater == 1) normal = -normal;

    // FRESNEL
    float NdotV  = max(dot(normal, -viewDir), 0.0);
    float fresnel = 0.02 + (REFLECTION_STRENGTH - 0.02) * pow(1.0 - NdotV, 5.0);

    // SUN DIRECTION
    // sunPosition is in view space in Iris, convert to world space
    vec3 worldSunDir = normalize(mat3(gbufferModelViewInverse) * sunPosition);

    // REFLECTION DIRECTION with roughness jitter
    vec3 reflDir = reflect(viewDir, normal);
    vec3 up      = abs(reflDir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, reflDir));
    vec3 bitang  = cross(reflDir, tangent);
    float spread      = WATER_ROUGHNESS * 0.5;
    vec3 roughReflDir = normalize(reflDir + tangent * normal.x * spread + bitang * normal.z * spread);

    // SKY GRADIENT
    vec3 horizonCol = vec3(0.55, 0.78, 0.95);
    vec3 zenithCol  = vec3(0.08, 0.30, 0.72);
    vec3 sunsetCol  = vec3(0.80, 0.55, 0.25);
    float upFactor     = clamp(roughReflDir.y, 0.0, 1.0);
    float sunsetFactor = pow(clamp(1.0 - abs(roughReflDir.y), 0.0, 1.0), 4.0);
    vec3 skyRefl = mix(mix(horizonCol, zenithCol, upFactor), sunsetCol, sunsetFactor * 0.35);

    // SUN GLINT
    float sunDot         = max(dot(roughReflDir, worldSunDir), 0.0);
    float glintSharpness = mix(2000.0, 80.0, WATER_ROUGHNESS * 3.0);
    float sunGlint       = pow(sunDot, glintSharpness) * mix(8.0, 1.5, WATER_ROUGHNESS * 2.0);
    skyRefl += vec3(1.0, 0.92, 0.75) * sunGlint;

    // WATER BODY COLOR
    vec3 waterBodyColor = mix(WATER_DEEP_COLOR, WATER_SHALLOW_COLOR, pow(1.0 - NdotV, 3.0));
    waterBodyColor = mix(waterBodyColor, albedo.rgb, 0.25);

    // COMBINE
    vec3 finalColor = mix(waterBodyColor, skyRefl, fresnel);
    vec3 lm = texture2D(lightmap, lmcoord).rgb;
    finalColor *= max(lm, vec3(0.04));
    finalColor  = mix(waterBodyColor, finalColor, 0.85);
    finalColor += waterBodyColor * 0.15;

    float alpha = mix(0.82, 0.97, fresnel);
    if (isEyeInWater == 1) {
        alpha       = 1.0;
        finalColor  = mix(finalColor, WATER_DEEP_COLOR * lm, 0.5);
    }

    colorOut = vec4(finalColor, alpha);
}