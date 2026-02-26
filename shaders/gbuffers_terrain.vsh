#version 330 compatibility

// 1. We import the block IDs defined in block.properties
in int mc_Entity;

// 2. We import time and the camera's position from the game
uniform float frameTimeCounter;
uniform vec3 cameraPosition;

out vec2 lmcoord;
out vec2 texcoord;
out vec4 glcolor;

void main() {
    // Get the base position of the block's vertex
    vec4 position = gl_Vertex;

    // --- WAVING FOLIAGE LOGIC ---
    // ID 10000 = Grass/Ferns
    // ID 10001 = Leaves
    if (mc_Entity == 10000 || mc_Entity == 10001) {
        // Calculate the absolute world position so the wave is seamless across different blocks
        vec3 worldPos = position.xyz + cameraPosition;

        // How fast and how far the blocks sway
        float waveSpeed = 2.0;
        // Grass waves a bit more than heavy leaves
        float waveMagnitude = (mc_Entity == 10000) ? 0.08 : 0.04;

        // Create a sine wave based on time and the X/Z world coordinates
        float wave = sin(frameTimeCounter * waveSpeed + worldPos.x + worldPos.z) * waveMagnitude;

        // Apply the wave to the X axis to create the sway
        position.x += wave;
    }

    // Multiply by the ModelViewProjection matrix to put the vertex on the screen
    // (This replaces the old ftransform() function)
    gl_Position = gl_ModelViewProjectionMatrix * position;

    // Pass texture, lightmap, and color data to the fragment shader
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor = gl_Color;
}