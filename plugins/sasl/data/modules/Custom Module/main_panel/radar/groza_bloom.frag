#version 330 core

in vec2 v_uv;
out vec4 fragColor;
uniform sampler2D render_target;
uniform float dirx = 1.0;
uniform float diry = 0.0;
uniform float intensity = 1.1;

// Calculate texel size if not provided via uniform
vec2 getTexelSize() {
    return 1.0 / vec2(2048, 1504);
}

// This function now returns a vec4 to include the alpha channel
vec4 bloom(vec2 uv) {
    vec2 texelSize = getTexelSize();
    // gaussian kernel, 1-dimensional, since the shader is applied in two passes
    float weight[11] = float[](0.1324, 0.1253, 0.1063, 0.0807, 0.0549, 0.0334, 0.0183, 0.0089, 0.0039, 0.0015, 0.0005);

    // Sample the full RGBA vector from the input texture
    vec4 result = texture(render_target, uv) * weight[0];

    for (int i = 1; i < 11; i++) {
        // Blur the full RGBA vector for all samples
        result += texture(render_target, uv + vec2(i * texelSize.x * dirx, i * texelSize.y * diry)) * weight[i] * intensity;
        result += texture(render_target, uv - vec2(i * texelSize.x * dirx, i * texelSize.y * diry)) * weight[i] * intensity;
    }

    return result;
}

void main()
{
    // The bloom function now returns the full blurred RGBA color
    vec4 bloomed_color = bloom(v_uv);

    // Apply brightness multiplication to the color channels only
    vec3 color = bloomed_color.rgb * 3.0;
    // Use the blurred alpha directly
    float alpha = bloomed_color.a;

    fragColor = vec4(1, 1, 1, alpha);
}
