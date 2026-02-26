#version 330 compatibility

uniform sampler2D colortex0;  // rendered scene
uniform sampler2D colortex1;  // water normals (encoded)
uniform sampler2D colortex3;  // water data (r=isWater, g=fresnel)
uniform sampler2D depthtex0;  // depth
uniform sampler2D depthtex1;  // depth (solid only, no water)

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform float near;
uniform float far;
uniform int isEyeInWater;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

// SSR step settings (tuned for performance on integrated graphics)
const int   SSR_STEPS     = 16;
const float SSR_STEP_SIZE = 1.2;
const float SSR_STEP_INC  = 2.0;
const int   SSR_REFINE    = 3;
const float SSR_REFINE_MULT = 0.1;

// Reconstruct view-space position from depth
vec3 getViewPos(vec2 uv, float depth) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 vp  = gbufferProjectionInverse * ndc;
    return vp.xyz / vp.w;
}

// Project view-space position back to screen UV + depth
vec3 toClipSpace(vec3 vp) {
    vec4 cp = gbufferProjection * vec4(vp, 1.0);
    return cp.xyz / cp.w * 0.5 + 0.5;
}

float cdist(vec2 coord) {
    return max(abs(coord.x - 0.5), abs(coord.y - 0.5)) * 2.0;
}

// Fallback sky color when ray misses
vec3 getSkyColor(vec3 reflViewDir) {
    // Convert reflected view direction to world direction for sky gradient
    vec3 reflWorldDir = mat3(gbufferModelViewInverse) * reflViewDir;

    vec3 horizonCol = vec3(0.60, 0.82, 0.98);
    vec3 zenithCol  = vec3(0.05, 0.22, 0.65);
    vec3 sunsetCol  = vec3(0.85, 0.50, 0.15);

    float upFactor     = clamp(reflWorldDir.y, 0.0, 1.0);
    float sunsetFactor = pow(clamp(1.0 - abs(reflWorldDir.y), 0.0, 1.0), 4.0);
    vec3 sky = mix(mix(horizonCol, zenithCol, upFactor), sunsetCol, sunsetFactor * 0.4);

    // Sun glint
    vec3 worldSunDir = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float sunDot  = max(dot(reflWorldDir, worldSunDir), 0.0);
    sky += vec3(1.0, 0.95, 0.80) * pow(sunDot, 800.0) * 12.0;

    return sky;
}

// Core SSR — marches in view space, same approach as Oceano
vec4 raytrace(vec3 fragpos, vec3 rvector) {
    vec4 result   = vec4(0.0);
    vec3 pos      = vec3(0.0);
    vec3 start    = fragpos;
    vec3 tvector  = SSR_STEP_SIZE * rvector;
    vec3 vector   = tvector;
    int  sr       = 0;

    fragpos += vector;

    for (int i = 0; i < SSR_STEPS; i++) {
        pos = toClipSpace(fragpos);

        // Left screen — stop
        if (pos.x < 0.0 || pos.x > 1.0 || pos.y < 0.0 || pos.y > 1.0 || pos.z < 0.0 || pos.z > 1.0) break;

        // Sample depth at this screen position
        float sceneDepth = texture2D(depthtex1, pos.xy).r;
        vec3  sceneVPos  = getViewPos(pos.xy, sceneDepth);

        float err         = distance(fragpos, sceneVPos);
        float vectorLen   = length(vector);

        if (err < pow(vectorLen * pow(vectorLen, 0.11), 1.1) * 1.1) {
            sr++;
            if (sr >= SSR_REFINE) {
                result.a = 1.0;
                break;
            }
            tvector -= vector;
            vector  *= SSR_REFINE_MULT;
        }

        vector  *= SSR_STEP_INC;
        tvector += vector;
        fragpos  = start + tvector;
    }

    // Edge fade — reflections fade out near screen borders
    float border = clamp(1.0 - pow(cdist(pos.xy), 6.0), 0.0, 1.0);
    result.rgb   = texture2D(colortex0, pos.xy).rgb;
    result.a    *= border;

    return result;
}

void main() {
    vec4  data    = texture2D(colortex3, texcoord);
    bool  isWater = data.r > 0.5;
    vec3  scene   = texture2D(colortex0, texcoord).rgb;

    if (!isWater) {
        // ---- NON-WATER: existing post-processing ----
        if (isEyeInWater == 1) {
            scene = mix(scene, vec3(0.0, 0.25, 0.55), 0.6);
        }
        float luminance = dot(scene, vec3(0.299, 0.587, 0.114));
        scene = mix(vec3(luminance), scene, 1.30);
        scene = smoothstep(0.0, 1.0, scene);
        color = vec4(scene, 1.0);
        return;
    }

    // ---- WATER PIXEL ----
    float fresnel   = data.g;
    vec3  waterBase = scene;

    // Decode normal (world space) and convert to view space for raytrace
    vec3 worldNormal = texture2D(colortex1, texcoord).rgb * 2.0 - 1.0;
    vec3 viewNormal  = normalize(mat3(gbufferProjection) * mat3(gbufferModelViewInverse) * worldNormal);
    // Simpler: use gbufferModelView to bring world normal into view space
    // gbufferModelViewInverse inverse = gbufferModelView
    mat3 modelView   = mat3(
    gbufferProjectionInverse[0].xyz, // this is wrong, need actual MV
    gbufferProjectionInverse[1].xyz,
    gbufferProjectionInverse[2].xyz
    );

    // Correct approach: reconstruct view normal from gbufferProjectionInverse
    // Normal transform: transpose of inverse of upper-left 3x3 of MV
    // Since we stored world normal, bring it to view space via MV
    // We don't have gbufferModelView in composite, but we can use MVInverse transposed
    mat3 mv = transpose(mat3(gbufferModelViewInverse));
    viewNormal = normalize(mv * worldNormal);

    // Get view-space position of this pixel
    float depth    = texture2D(depthtex0, texcoord).r;
    vec3  fragpos  = getViewPos(texcoord, depth);

    // Reflected view direction in view space
    vec3 uPos     = normalize(fragpos);
    vec3 reflView = reflect(uPos, viewNormal);

    // Sky fallback using world-space reflection
    vec3 skyColor = getSkyColor(reflView);

    // Raytrace in view space
    vec4 reflection = raytrace(fragpos, reflView);
    // Mix: where ray hit something use SSR, where it missed use sky
    vec3 reflColor  = mix(skyColor, reflection.rgb, reflection.a);

    // Final blend: fresnel controls how much reflection vs water body color
    vec3 finalColor = mix(waterBase, reflColor, fresnel);

    color = vec4(finalColor, 1.0);
}