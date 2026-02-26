#version 330 compatibility

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

    // --- SMOOTH SWELLS ---
    if (fract(worldPos.y + 0.001) > 0.02) {
        float time = frameTimeCounter * 1.5;
        position.y += (sin(worldPos.x * 1.0 + time) * cos(worldPos.z * 1.0 + time)) * 0.05;
    }

    vec4 viewPos = gl_ModelViewMatrix * position;
    gl_Position = gl_ProjectionMatrix * viewPos;

    // Send the absolute World Position to the fragment shader
    wpos = (gbufferModelViewInverse * viewPos).xyz + cameraPosition;
}