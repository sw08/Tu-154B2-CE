#version 330 core
in vec2 v_uv;
out vec4 fragColor;
uniform sampler2D u_source;

void main() {
    vec3 color = texture(u_source, v_uv).rgb;

    // Compute a brightness/alpha metric (you can use luminance or max channel)
    float alpha = max(max(color.r, color.g), color.b);

    // Hard threshold to remove very small residues (tweak thresholds)
    float hardCut = 0.03; // below this -> fully transparent
    float softStart = 0.03;
    float softEnd = 0.12; // soft ramp range

    if (alpha <= hardCut) {
        discard; // avoid writing tiny alpha and color
    }

    // Softstep for smoother edges (optional)
    float a = smoothstep(softStart, softEnd, alpha);

    // Use premultiplied alpha to avoid dark fringes when compositing
    vec3 premult = color * a;

    fragColor = vec4(premult, a);
}
