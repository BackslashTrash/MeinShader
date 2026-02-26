#version 330 compatibility

uniform sampler2D lightmap;
uniform sampler2D gtexture;

uniform float alphaTestRef = 0.1;

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

// A simple, fast function to make colors pop more
vec3 increaseVibrancy(vec3 color, float amount) {
    // Calculate how bright the color is (luminance)
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 gray = vec3(luminance);
    // Mix the gray version of the color with the actual color to boost saturation
    return mix(gray, color, amount);
}

void main() {
    // 1. Get the texture color and multiply by the biome/block tint (glcolor)
    color = texture(gtexture, texcoord) * glcolor;

    // 2. Apply the vanilla Minecraft lightmap (torches and sun)
    color *= texture(lightmap, lmcoord);

    // 3. Make the game 25% more colorful/saturated! (1.0 is default, 1.25 is boosted)
    color.rgb = increaseVibrancy(color.rgb, 1.25);

    // 4. Discard transparent pixels (like the gaps in leaves or grass)
    if (color.a < alphaTestRef) {
        discard;
    }
}