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

vec3 underwaterFog(vec3 sceneColor, float depth) {
    vec3 fogNear = vec3(0.02, 0.18, 0.28);
    vec3 fogFar  = vec3(0.00, 0.08, 0.18);

    float linearD    = linearizeDepth(depth) * far;
    float fogDensity = 0.06;
    float fogAmt     = 1.0 - exp(-linearD * fogDensity);
    fogAmt = clamp(fogAmt, 0.0, 1.0);
    fogAmt *= smoothstep(1.0, 4.0, linearD);

    vec3 fogColor = mix(fogNear, fogFar, clamp(linearD / 20.0, 0.0, 1.0));

    vec3 worldPos = mat3(gbufferModelViewInverse) * getViewPos(texcoord, depth) + cameraPosition;
    float caustic  = sin(worldPos.x * 2.1 + frameTimeCounter * 1.2) *
    sin(worldPos.z * 1.8 + frameTimeCounter * 0.9) * 0.5 + 0.5;
    caustic = pow(caustic, 4.0) * 0.08 * (1.0 - fogAmt);
    sceneColor += vec3(0.0, caustic * 0.2, caustic * 0.35);

    return mix(sceneColor, fogColor, fogAmt);
}

// Looking up at the surface from below —
// show sky light coming through, not a floor reflection
vec3 underwaterSurface(vec3 worldNormal, vec3 viewDir) {
    // Light filtering down from above — teal/cyan toned
    vec3 skyLight = vec3(0.06, 0.28, 0.45);

    // Sun visible as a soft bright patch directly above
    vec3 worldSunDir = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float sunAngle   = max(dot(-worldNormal, worldSunDir), 0.0);
    float sunBeam    = pow(sunAngle, 80.0) * 1.2 + pow(sunAngle, 10.0) * 0.2;
    skyLight        += vec3(0.15, 0.28, 0.38) * sunBeam;

    // Bright teal ring at grazing angles (snell's window edge)
    float NdotV  = abs(dot(worldNormal, viewDir));
    float snell  = pow(1.0 - NdotV, 4.0);
    skyLight     = mix(skyLight, vec3(0.08, 0.42, 0.62), snell * 0.6);

    return skyLight;
}

void main() {
    vec4  data    = texture2D(colortex3, texcoord);
    bool  isWater = data.r > 0.5;
    vec3  scene   = texture2D(colortex0, texcoord).rgb;
    float depth   = texture2D(depthtex0, texcoord).r;

    // -----------------------------------------------
    // UNDERWATER
    // -----------------------------------------------
    if (isEyeInWater == 1) {
        scene *= vec3(0.55, 0.80, 0.95);
        scene  = underwaterFog(scene, depth);

        if (isWater) {
            vec3 worldNormal = texture2D(colortex1, texcoord).rgb * 2.0 - 1.0;

            // View direction in world space
            vec3 fragpos     = getViewPos(texcoord, depth);
            vec3 viewDirView = normalize(fragpos);
            vec3 viewDirWorld = normalize(mat3(gbufferModelViewInverse) * viewDirView);

            // Make sure normal points toward camera (upward from below)
            if (dot(worldNormal, vec3(0.0, 1.0, 0.0)) < 0.0) worldNormal = -worldNormal;

            float NdotV = abs(dot(worldNormal, -viewDirWorld));

            // Snell's window — the cone of ~97 degrees through which you can see the sky
            // Outside this cone is total internal reflection showing the floor
            float snellWindow = smoothstep(0.10, 0.30, NdotV);

            // Sky light coming through — bright teal/cyan at center, darker at edges
            vec3 worldSunDir = normalize(mat3(gbufferModelViewInverse) * sunPosition);
            float sunAngle   = max(dot(worldNormal, worldSunDir), 0.0);
            float sunBeam    = pow(sunAngle, 60.0) * 1.5 + pow(sunAngle, 8.0) * 0.3;

            vec3 skyLight = vec3(0.10, 0.42, 0.65);            // base sky color through water
            skyLight     += vec3(0.20, 0.35, 0.45) * sunBeam;  // sun patch
            skyLight      = clamp(skyLight, 0.0, 1.0);

            // TIR — just darken the scene tint, no SSR (avoids the streak artifacts)
            vec3 tirColor = scene * vec3(0.3, 0.5, 0.7);

            scene = mix(tirColor, skyLight, snellWindow);
        }

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