#version 330 compatibility

#define WAVE_AMPLITUDE 0.05 // [0.00 0.01 0.02 0.03 0.05 0.08 0.12 0.15 0.20 0.25 0.30]
#define WAVE_SPEED 1.5      // [0.0 0.5 0.8 1.0 1.2 1.5 1.8 2.0 2.5 3.0 4.0 5.0]
#define WAVE_FREQUENCY 1.0  // [0.2 0.4 0.6 0.8 1.0 1.2 1.5 1.8 2.0 2.5 3.0 4.0]

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glColor;
in vec3 wpos;
in vec3 viewPos;

/* DRAWBUFFERS:013 */
layout(location = 0) out vec4 colorOut;
layout(location = 1) out vec4 normalOut;
layout(location = 2) out vec4 dataOut;

uniform sampler2D lightmap;
uniform sampler2D depthtex0; // DO NOT sample this in this pass
uniform sampler2D depthtex1; // Opaque depth before water
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform float frameTimeCounter;
uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform int isEyeInWater;

#define WATER_ROUGHNESS 0.022
#define WATER_DEEP_COLOR    vec3(0.00, 0.32, 0.52)
#define WATER_SHALLOW_COLOR vec3(0.04, 0.52, 0.72)

// -----------------------------------------------
// NOISE
// -----------------------------------------------
vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)),
    dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    // Quintic interpolation
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    float a = dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
    float b = dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
    float c = dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
    float d = dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// -----------------------------------------------
// FBM WATER NORMAL
// -----------------------------------------------
vec3 getWaterNormal(vec3 worldPos) {
    float time = frameTimeCounter;
    float freq = WAVE_FREQUENCY;
    const float eps = 0.10;

    #define SWELL(px, pz) (                                                                  \
        vnoise(vec2(px, pz) * freq * 0.30 + vec2( 0.50,  0.20) * time * 0.30) * 0.500 +   \
        vnoise(vec2(px, pz) * freq * 0.51 + vec2(-0.30,  0.60) * time * 0.40) * 0.350 +   \
        vnoise(vec2(px, pz) * freq * 0.78 + vec2( 0.70, -0.40) * time * 0.35) * 0.250 +   \
        vnoise(vec2(px, pz) * freq * 1.13 + vec2(-0.60, -0.50) * time * 0.45) * 0.150 +   \
        vnoise(vec2(px, pz) * freq * 1.67 + vec2( 0.40,  0.80) * time * 0.55) * 0.075     \
    )

    #define CHOP(px, pz) (                                                                   \
        vnoise(vec2(px, pz) * freq * 3.50 + vec2( 0.80,  0.30) * time * 1.20) * 0.040 +   \
        vnoise(vec2(px, pz) * freq * 5.70 + vec2(-0.50,  0.90) * time * 1.60) * 0.025 +   \
        vnoise(vec2(px, pz) * freq * 8.90 + vec2( 0.30, -0.70) * time * 2.10) * 0.015 +   \
        vnoise(vec2(px, pz) * freq * 14.3 + vec2(-0.80,  0.40) * time * 2.80) * 0.008     \
    )

    #define HEIGHT(px, pz) (SWELL(px, pz) + CHOP(px, pz))

    float hC = HEIGHT(worldPos.x,       worldPos.z      );
    float hX = HEIGHT(worldPos.x + eps, worldPos.z      );
    float hZ = HEIGHT(worldPos.x,       worldPos.z + eps);

    #undef SWELL
    #undef CHOP
    #undef HEIGHT

    float dX = (hX - hC) / eps * WATER_ROUGHNESS * 5.0;
    float dZ = (hZ - hC) / eps * WATER_ROUGHNESS * 5.0;

    return normalize(vec3(-dX, 1.0, -dZ));
}

// -----------------------------------------------
// HELPERS
// -----------------------------------------------
float linearizeDepth(float depth) {
    return (2.0 * near) / (far + near - depth * (far - near));
}

void main() {
    vec3 viewDir = normalize(wpos - cameraPosition);
    vec3 normal  = getWaterNormal(wpos);
    if (isEyeInWater == 1) normal = -normal;

    float NdotV  = max(dot(normal, -viewDir), 0.0);
    float fresnel = 0.02 + 0.92 * pow(1.0 - NdotV, 5.0);

    // -----------------------------------------------
    // SUN SPECULAR GLINT
    // -----------------------------------------------
    vec3 worldSunDir = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    vec3 halfVec     = normalize(-viewDir + worldSunDir);
    float NdotH      = max(dot(normal, halfVec), 0.0);

    float specSoft   = pow(NdotH, 80.0)  * 0.6;
    float specSharp  = pow(NdotH, 600.0) * 3.0;
    vec3  sunGlint   = vec3(1.0, 0.97, 0.90) * (specSoft + specSharp);

    // -----------------------------------------------
    // DEPTH-BASED TRANSPARENCY (FIXED)
    // -----------------------------------------------
    vec2  screenUV      = gl_FragCoord.xy / vec2(viewWidth, viewHeight);

    // FIX: Use gl_FragCoord.z to get the current fragment's depth safely
    float currentDepth  = linearizeDepth(gl_FragCoord.z);

    // depthtex1 safely contains the opaque geometry behind the water
    float depthSeafloor = linearizeDepth(texture2D(depthtex1, screenUV).r);

    float waterDepth    = (depthSeafloor - currentDepth) * far;
    float depthFade     = smoothstep(0.0, 1.0, clamp(waterDepth / 8.0, 0.0, 1.0));

    vec3 lm = texture2D(lightmap, lmcoord).rgb;

    vec3 waterTint = mix(WATER_SHALLOW_COLOR, WATER_DEEP_COLOR, depthFade);
    waterTint *= max(lm, vec3(0.02));
    waterTint += sunGlint * max(lm.g, 0.0);

    float shallowAlpha = mix(0.20, 0.92, pow(fresnel, 0.6));
    float alpha        = mix(shallowAlpha, 0.97, depthFade);

    // -----------------------------------------------
    // UNDERWATER VIEWING (FIXED)
    // -----------------------------------------------
    if (isEyeInWater == 1) {
        // We set the alpha to be transparent so we can see through the underside
        alpha = 0.4;

        // Add a slight sky-blue tint so looking up feels natural
        waterTint = mix(waterTint, vec3(0.5, 0.8, 1.0), 0.35);
    }

    colorOut  = vec4(waterTint, alpha);
    normalOut = vec4(normal * 0.5 + 0.5, 1.0);
    dataOut   = vec4(1.0, fresnel, 0.0, 1.0);
}