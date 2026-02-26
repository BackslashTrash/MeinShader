#version 330 compatibility

out vec2 texcoord;

void main() {
    // This simply draws a flat rectangle over the whole screen
    // so the fragment shader can apply color effects to it.
    gl_Position = ftransform();

    // Pass the screen coordinates to the fragment shader
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}