#version 330 compatibility

#define WAVE_AMPLITUDE 0.05 // [0.00 0.01 0.02 0.03 0.05 0.08 0.12 0.15 0.20 0.25 0.30]
#define WAVE_SPEED 1.5 // [0.0 0.5 0.8 1.0 1.2 1.5 1.8 2.0 2.5 3.0 4.0 5.0]
#define WAVE_FREQUENCY 1.0 // [0.2 0.4 0.6 0.8 1.0 1.2 1.5 1.8 2.0 2.5 3.0 4.0]

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glColor;
out vec3 wpos;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glColor  = gl_Color;

    vec4 position = gl_Vertex;

    // Get the world position to wave the water naturally
    vec3 worldPos = (gbufferModelViewInverse * (gl_ModelViewMatrix * position)).xyz + cameraPosition;

    // --- SMOOTH SWELLS (now using #define settings) ---
    if (fract(worldPos.y + 0.001) > 0.02) {
        float time = frameTimeCounter * WAVE_SPEED;
        float freq = WAVE_FREQUENCY;
        position.y += (sin(worldPos.x * freq + time) * cos(worldPos.z * freq + time)) * WAVE_AMPLITUDE;
    }

    vec4 viewPos = gl_ModelViewMatrix * position;
    gl_Position = gl_ProjectionMatrix * viewPos;

    // Send the absolute World Position to the fragment shader
    wpos = (gbufferModelViewInverse * viewPos).xyz + cameraPosition;
}