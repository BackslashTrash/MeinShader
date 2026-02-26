#version 330 compatibility

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform float near;
uniform float far;
uniform float frameTimeCounter;
uniform int isEyeInWater;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

const int   SSR_STEPS       = 16;
const float SSR_STEP_SIZE   = 1.2;
const float SSR_STEP_INC    = 2.0;
const int   SSR_REFINE      = 3;
const float SSR_REFINE_MULT = 0.1;

vec3 getViewPos(vec2 uv, float depth) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 vp  = gbufferProjectionInverse * ndc;
    return vp.xyz / vp.w;
}

vec3 toClipSpace(vec3 vp) {
    vec4 cp = gbufferProjection * vec4(vp, 1.0);
    return cp.xyz / cp.w * 0.5 + 0.5;
}

float cdist(vec2 coord) {
    return max(abs(coord.x - 0.5), abs(coord.y - 0.5)) * 2.0;
}

float linearizeDepth(float depth) {
    return (2.0 * near) / (far + near - depth * (far - near));
}

vec3 getSkyColor(vec3 reflViewDir) {
    vec3 reflWorldDir = mat3(gbufferModelViewInverse) * reflViewDir;
    vec3 horizonCol   = vec3(0.60, 0.82, 0.98);
    vec3 zenithCol    = vec3(0.05, 0.22, 0.65);
    vec3 sunsetCol    = vec3(0.85, 0.50, 0.15);
    float upFactor     = clamp(reflWorldDir.y, 0.0, 1.0);
    float sunsetFactor = pow(clamp(1.0 - abs(reflWorldDir.y), 0.0, 1.0), 4.0);
    vec3 sky = mix(mix(horizonCol, zenithCol, upFactor), sunsetCol, sunsetFactor * 0.4);
    vec3 worldSunDir = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float sunDot = max(dot(reflWorldDir, worldSunDir), 0.0);
    sky += vec3(1.0, 0.95, 0.80) * pow(sunDot, 800.0) * 12.0;
    return sky;
}

vec4 raytrace(vec3 fragpos, vec3 rvector) {
    vec4 result  = vec4(0.0);
    vec3 pos     = vec3(0.0);
    vec3 start   = fragpos;
    vec3 tvector = SSR_STEP_SIZE * rvector;
    vec3 vector  = tvector;
    int  sr      = 0;
    fragpos += vector;

    for (int i = 0; i < SSR_STEPS; i++) {
        pos = toClipSpace(fragpos);
        if (pos.x < 0.0 || pos.x > 1.0 ||
        pos.y < 0.0 || pos.y > 1.0 ||
        pos.z < 0.0 || pos.z > 1.0) break;
        float sceneDepth = texture2D(depthtex1, pos.xy).r;
        vec3  sceneVPos  = getViewPos(pos.xy, sceneDepth);
        float err        = distance(fragpos, sceneVPos);
        float vectorLen  = length(vector);
        if (err < pow(vectorLen * pow(vectorLen, 0.11), 1.1) * 1.1) {
            sr++;
            if (sr >= SSR_REFINE) { result.a = 1.0; break; }
            tvector -= vector;
            vector  *= SSR_REFINE_MULT;
        }
        vector  *= SSR_STEP_INC;
        tvector += vector;
        fragpos  = start + tvector;
    }

    float border = clamp(1.0 - pow(cdist(pos.xy), 6.0), 0.0, 1.0);
    result.rgb   = texture2D(colortex0, pos.xy).rgb;
    result.a    *= border;
    return result;
}

void main() {
    vec4  data    = texture2D(colortex3, texcoord);
    bool  isWater = data.r > 0.5;
    vec3  scene   = texture2D(colortex0, texcoord).rgb;
    float depth   = texture2D(depthtex0, texcoord).r;

    // -----------------------------------------------
    // UNDERWATER — simple depth fog like Oceano
    // Terrain renders normally, we just add blue tint
    // and increase fog the deeper you go
    // -----------------------------------------------
    if (isEyeInWater == 1) {
        float linearD    = linearizeDepth(depth) * far;
        float fogDensity = 0.04;
        float fogAmt     = 1.0 - exp(-linearD * fogDensity);
        fogAmt           = clamp(fogAmt, 0.0, 0.92);

        // Bright teal near surface, deep blue far away
        vec3 fogNear  = vec3(0.05, 0.30, 0.50);
        vec3 fogFar   = vec3(0.00, 0.08, 0.20);
        vec3 fogColor = mix(fogNear, fogFar, clamp(linearD / 20.0, 0.0, 1.0));

        // Global blue tint simulating water light absorption
        scene *= vec3(0.75, 0.88, 1.0);

        // Depth fog
        scene = mix(scene, fogColor, fogAmt);

        // Subtle caustic shimmer on nearby surfaces
        vec3 worldPos = mat3(gbufferModelViewInverse) * getViewPos(texcoord, depth) + cameraPosition;
        float caustic  = sin(worldPos.x * 2.1 + frameTimeCounter * 1.2) *
        sin(worldPos.z * 1.8 + frameTimeCounter * 0.9) * 0.5 + 0.5;
        caustic = pow(caustic, 4.0) * 0.06 * (1.0 - fogAmt);
        scene  += vec3(0.0, caustic * 0.15, caustic * 0.28);

        color = vec4(scene, 1.0);
        return;
    }

    // -----------------------------------------------
    // ABOVE WATER — NON-WATER PIXEL
    // -----------------------------------------------
    if (!isWater) {
        float luminance = dot(scene, vec3(0.299, 0.587, 0.114));
        scene = mix(vec3(luminance), scene, 1.30);
        scene = smoothstep(0.0, 1.0, scene);
        color = vec4(scene, 1.0);
        return;
    }

    // -----------------------------------------------
    // ABOVE WATER — WATER SURFACE PIXEL
    // -----------------------------------------------
    float fresnel    = data.g;
    vec3  waterBase  = scene;

    vec3 worldNormal = texture2D(colortex1, texcoord).rgb * 2.0 - 1.0;
    mat3 mv          = transpose(mat3(gbufferModelViewInverse));
    vec3 viewNormal  = normalize(mv * worldNormal);

    vec3 fragpos  = getViewPos(texcoord, depth);
    vec3 uPos     = normalize(fragpos);
    vec3 reflView = reflect(uPos, viewNormal);

    vec3 skyColor   = getSkyColor(reflView);
    vec4 reflection = raytrace(fragpos, reflView);
    vec3 reflColor  = mix(skyColor, reflection.rgb, reflection.a);

    vec3 finalColor = mix(waterBase, reflColor, fresnel);
    color = vec4(finalColor, 1.0);
}