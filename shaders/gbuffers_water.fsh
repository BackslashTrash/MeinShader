#version 330 compatibility

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 colorOut;

// Note: In GLSL 330, "texture" is a built-in function, so to sample the Minecraft
// uniform block texture without crashing, we must use texture2D() instead.
uniform sampler2D texture;
uniform sampler2D lightmap;

uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform float frameTimeCounter;
uniform int isEyeInWater;
uniform mat4 gbufferModelViewInverse;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glColor;
in vec3 wpos;

// Very subtle, smooth ripples
vec3 getWaterNormal(vec3 worldPos) {
    float time = frameTimeCounter * 1.2;
    float dx = cos(worldPos.x * 1.2 + time) * 0.015;
    float dz = sin(worldPos.z * 1.2 + time) * 0.015;
    return normalize(vec3(-dx, 1.0, -dz));
}

void main() {
    // --- DA OLD COLOR ---
    // This samples the actual Minecraft texture and biome tint!
    // This brings back your original colors exactly as they were.
    vec4 albedo = texture2D(texture, texcoord) * glColor;

    // --- 1. FOOLPROOF WORLD SPACE MATH ---
    // Direction from your eyes to the water
    vec3 playerPos = wpos - cameraPosition;
    vec3 worldViewDir = normalize(playerPos);

    vec3 worldNormal = getWaterNormal(wpos);
    if (isEyeInWater == 1) worldNormal = -worldNormal;

    // Bounce the view direction off the water to get the reflection angle
    vec3 worldRefDir = reflect(worldViewDir, worldNormal);
    vec3 worldSunDir = normalize(mat3(gbufferModelViewInverse) * sunPosition);

    // --- 2. FRESNEL (Mirror Effect) ---
    float NdotV = max(dot(worldNormal, -worldViewDir), 0.0);
    float fresnel = 0.02 + 0.98 * pow(1.0 - NdotV, 5.0);

    // --- 3. GOOD LOOKING SKY ---
    vec3 horizonCol = vec3(0.5, 0.75, 0.95);
    vec3 zenithCol  = vec3(0.1, 0.35, 0.8);
    float skyMix = clamp(worldRefDir.y, 0.0, 1.0);
    vec3 reflection = mix(horizonCol, zenithCol, skyMix);

    // --- 4. CONTAINED SUN ---
    float sunDot = max(dot(worldRefDir, worldSunDir), 0.0);
    float sunCore = pow(sunDot, 600.0) * 4.0;
    reflection += vec3(1.0, 0.9, 0.7) * sunCore;

    // --- 5. COMBINE IT ALL ---
    // Mix "Da Old Color" with the new Sky/Sun Mirror based on viewing angle
    vec3 finalColor = mix(albedo.rgb, reflection, fresnel);

    // Make sure caves/underground areas stay dark
    vec3 lm = texture2D(lightmap, lmcoord).rgb;
    finalColor *= max(lm, vec3(0.05));

    // Increase opacity near the horizon to complete the mirror look
    float alpha = mix(albedo.a, 1.0, fresnel);
    if (isEyeInWater == 1) alpha = albedo.a;

    colorOut = vec4(finalColor, alpha);
}