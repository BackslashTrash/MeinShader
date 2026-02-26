#version 330 compatibility

uniform sampler2D tex; // The block texture

in vec2 texcoord;
in vec4 glcolor;

layout(location = 0) out vec4 color;

void main() {
    color = texture(tex, texcoord) * glcolor;

    // This makes sure invisible parts of leaves/glass don't cast solid square shadows!
    if (color.a < 0.1) {
        discard;
    }
}