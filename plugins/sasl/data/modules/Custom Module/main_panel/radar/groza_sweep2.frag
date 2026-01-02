#version 330 core
in vec2 v_uv;
out vec4 fragColor;
uniform float time;
uniform float arcs[5] = float[](0, 0, 0, 0, 0);
uniform float noise_scale = 0.02;
uniform float noise_strength = 0.165;
uniform vec3 base_color = vec3(1.0, 1.0, 0.0);
uniform float sym_brt = 1;

// Radar scope geometry in UV space (panel 2048x2048, scope bottom at y=350)
const vec2 kCenterUV = vec2(1024.0 / 2048.0, 230.0 / 1504.0);
const float kMaxRadiusUV = (1504.0 - 230.0) / 2048.0;
const vec2 kViewportSize = vec2(2048.0, 1504.0);
const float kAspectRatio = kViewportSize.x / kViewportSize.y; // ~1.36

// Utilities (fast hash-based noise)
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float ringContribution(float rNorm, float target, float width) {
    float d = abs(rNorm - (target + 0.1));
    // Narrow soft band; 1 at center, 0 outside width
    return (1.0 - smoothstep(0.0, width, d));
}

void main() {
    float i = 0.0;
    float n = hash12(v_uv * noise_scale + vec2(time * 0.173, time * 0.297));
    n = (n - 0.5) * 12.0; // [-1..1]

    vec2 dp = v_uv - kCenterUV;
    dp.x *= kAspectRatio;
    float rNorm = length(dp) / kMaxRadiusUV; // 0 at center, 1 at outer edge
    // Slight flicker for realism
    float flick = 0.15 + 0.15 * sin(time * 12.0);

    for (int i = 0; i < 5; i++) {
        ring += ringContribution(rNorm, arcs[i], 0.0015) * step(0.0, arcs[i]) * sym_brt;
    }
    ring = clamp(ring, 0.0, 4.0) * sym_brt;

    i = clamp(i + n * noise_strength, 0.7, 12);

    float result = i * 1.0 * flick;

    vec4 color = base_color * result * 1;

    fragColor = vec4(color, 1.0);
}
