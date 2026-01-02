#version 330 core

in vec2 v_uv;
out vec4 fragColor;

uniform sampler2D render_target; // WX radar return strengths (R)
uniform sampler2D u_prev; // previous frame (for afterglow)
uniform sampler2D reticle; // reticle texture

uniform vec2 u_texel; //vec2(1.0 / textureSize(render_target, 0));
uniform float u_time = 0.0; // seconds

uniform float u_floorSubtract = 0.0011; // subtract ~1 LSB in 8-bit (~1/255=0.0039)
uniform float u_floorThreshold = 0.0001; // hard kill below this

// Calculate texel size if not provided via uniform
vec2 getTexelSize() {
    if (u_texel.x > 0.0 && u_texel.y > 0.0) {
        return u_texel;
    }
    // Fallback: calculate from texture size
    //return 1.0 / vec2(textureSize(render_target, 0));
    // TODO: replace hardcoded values with uniform
    return 1.0 / vec2(2048, 1504);
}

uniform float u_persistence = 0.9; // 0..1
uniform float u_decay = 0.92; // 0..1

uniform vec2 blur_dir = vec2(1.0, 0.0);

uniform vec3 u_phosphorColor = vec3(0.60, 1.00, 0.42); // e.g., vec3(0.10, 0.95, 0.12)

// Utilities (fast hash-based noise)
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec3 hsv2rgb(vec3 c) {
    vec3 rgb = clamp(abs(mod(c.x * 6.0 + vec3(0, 4, 2), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    return c.z * mix(vec3(1.0), rgb, c.y);
}

void main() {
    // 1. Get intensity of the new radar returns for this pixel.
    float new_intensity = texture(render_target, v_uv).g;

    // 2. Get the intensity of this pixel from the previous frame and apply decay.
    float previous_intensity = texture(u_prev, v_uv).g;
    float decayed_intensity = previous_intensity * u_decay;

    // 3. The new intensity is the MAXIMUM of the new return and the decayed afterglow.
    //    This ensures new returns are always bright and old ones fade.
    float i = max(new_intensity, decayed_intensity);

    // Black-level clamp to prevent "forever" residue (this part is good and unchanged)
    i = max(0.0, i - u_floorSubtract);
    if (i < u_floorThreshold) {
        i = 0.0;
    }

    // Set final color
    fragColor = vec4(clamp(u_phosphorColor, 0.3, 1.0), i * 2.0);
}
