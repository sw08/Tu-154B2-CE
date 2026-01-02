#version 330 core
in vec2 v_uv;
out vec4 fragColor;
uniform float time;
uniform float arcs[5] = float[](0, 0, 0, 0, 0);
uniform float noise_scale = 812;
uniform float noise_strength = 0.265;
uniform float beam_angle = 0.0; // radians, from Lua
uniform float beam_width = 20; // radians, e.g., radians(1.0)
uniform float beam_vel = 0.0; // degrees per second
uniform vec3 base_color = vec3(0.0, 1.0, 0.3);
uniform float u_antennaSpeedDPS = 0.0; // antenna speed in degrees per second

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
    float d = abs(rNorm - target);
    // Narrow soft band; 1 at center, 0 outside width
    return (1.0 - smoothstep(0.0, width, d)) * sym_brt;
}

void main() {
    float i = 0.0;
    float n = hash12(v_uv * noise_scale + vec2(time * 0.173, time * 0.297));
    n = (n - 0.5) * 2.0; // [-1..1]

    vec2 dp = v_uv - kCenterUV;
    dp.x *= kAspectRatio;
    float rNorm = length(dp) / kMaxRadiusUV; // 0 at center, 1 at outer edge
    float ring = 0.0;

    // --- HARD CLIP beyond ±100° ---
    float angle = atan(dp.x, dp.y);
    float angleDeg = degrees(angle);
    if (abs(angle) > radians(101.0)) {
        discard; // nothing drawn outside range
    }

    for (int i = 0; i < 5; i++) {
        ring += ringContribution(rNorm, arcs[i], 0.0015) * step(0.0, arcs[i]) * sym_brt;
    }

    float speedFactor = clamp(abs(u_antennaSpeedDPS) / 15.0, 0.0, 1.0);
    float maxSectorHalfWidth = mix(1.0, 101.0, speedFactor);
    float fadeWidth = 1.0;
    float sectorMask = 1.0 - smoothstep(
                maxSectorHalfWidth - fadeWidth,
                maxSectorHalfWidth + fadeWidth,
                abs(angleDeg)
            );
    //ring = clamp(ring, 0.0, 4.0);

    // Slight flicker for realism
    //float flick = 0.25 + 0.15 * sin(time * 12.0);
    //
    //float mask = smoothstep(100, 100 - beam_width, abs(beam_angle));

    i = clamp(i + n * noise_strength, 0.01, 0.16) * sectorMask;

    float result = i + ring * 2.0; // * flick;

    vec3 color = base_color * result;

    fragColor = vec4(color, result);
}
