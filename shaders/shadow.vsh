#version 330 compatibility

out vec2 texcoord;
out vec4 glcolor;

void main() {
    // Renders the blocks from the sun's perspective
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;
}