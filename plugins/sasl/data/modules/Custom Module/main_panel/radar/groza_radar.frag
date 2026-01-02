#version 330 core
// Radar returns shader, converts raw return values to green intensity 0..1
in vec2 v_uv;
out vec4 fragColor;

uniform sampler2D u_returns; // WX radar return strengths (R)
//uniform float u_gain = 0.19; // Increased for better signal visibility
//uniform float u_bias = 0.06; // Lower threshold for weak returns
//uniform float u_gamma = 0.25; // Higher gamma for better mid-tone contrast
//uniform float u_brightness = 0.02; // Slight brightness boost for weak signals
//uniform float u_contrast = 3.8; // Higher contrast for better differentiation

uniform float u_gain = 0.09; // Increased for better signal visibility
uniform float u_bias = 0.06; // Lower threshold for weak returns
uniform float u_gamma = 0.25; // Higher gamma for better mid-tone contrast
uniform float u_brightness = 0.02; // Slight brightness boost for weak signals
uniform float u_contrast = 1.8; // Higher contrast for better differentiation
//
uniform vec3 u_phosphorColor = vec3(0.10, 0.95, 0.12);

// Sweep reveal controls
uniform float u_sweepAngleDeg = 0.0; // current sweep angle in degrees (-100..100), 0 = up
uniform float u_beamWidthDeg = 4.0; // total beam width in degrees
uniform float u_uvYOffset = 0.4; // vertical UV offset applied to returns sampling
uniform float u_sweepDirection = 1.0; // 1.0 = clockwise, -1.0 = counter-clockwise
uniform float u_antennaSpeedDPS = 0.0; // antenna speed in degrees per second

// Contour mode (shows black voids in areas with most intensity)
uniform bool u_contourMode = true; // contour mode switch
uniform float u_contourThreshold = 0.8; // cloud core threshold [0..1]

uniform vec2 kViewportSize = vec2(2048.0, 1504.0);
// Display geometry assumptions in UV of the returns texture:
// - Center of the scope is at bottom middle of the returns UV (0.5, 0.0)
// - We only display the upper semicircle (p.y >= 0)
// - Radius is within [0..1] in returns UV space
const vec2 kCenterUV = vec2(0.5, 0.0);
const float kRadiusUV = 0.51;
//const vec2 kViewportSize = vec2(2048.0, 1504.0);
float kAspectRatio = kViewportSize.x / kViewportSize.y; // ~1.36

// Convert raw return value at UV to post-processed intensity 0..1
float sampleIntensity(vec2 uv) {
    float r = texture(u_returns, uv).r; // RED channel per X-Plane WX radar docs

    // Contour mode. Zero out cloud 'core' when enabled and above threshold.
    float contourMask = 1.0 - (u_contourMode ? step(u_contourThreshold, r) : 0.0);
    r *= contourMask;
    // Apply bias and gain for initial signal processing
    float i = (r - u_bias) * u_gain;

    // Soft clamp to preserve dynamic range while preventing harsh cutoffs
    i = smoothstep(0.0, 1.0, i);

    // Apply gamma correction for better perceptual response
    i = pow(max(i, 1e-4), u_gamma);

    // Apply contrast and brightness adjustments
    i = (i - 0.5) * u_contrast + 0.5 + u_brightness;

    // Final clamp to valid range with headroom for bright returns
    return clamp(i, 0.0, 1.5);
}

// Improved angle difference function that handles wraparound correctly
float angleDiffSigned(float a, float b) {
    float d = a - b;
    // Wrap to [-pi, pi]
    d = atan(sin(d), cos(d));
    return d;
}

float angleDiffAbs(float a, float b) {
    return abs(angleDiffSigned(a, b));
}

// Work in sweep coordinate system to avoid conversion issues
float pixelSweepAngle(vec2 p, float aspectRatio) {
    // Apply aspect ratio correction first to get proper circular geometry
    vec2 pCorrected = vec2(p.x * aspectRatio, p.y);

    // Convert pixel position to sweep angle coordinates
    // where 0° = up, positive = clockwise, range [-180, 180]
    // Standard atan(y,x): 0° = right, 90° = up
    // We want: 0° = up, 90° = right (clockwise)
    // So we rotate by -90° and flip for clockwise: -90° - atan(y,x)
    float angleRad = -atan(pCorrected.y, pCorrected.x) + 1.57079632679; // +π/2 to make 0° = up
    // Wrap to [-π, π] range
    angleRad = atan(sin(angleRad), cos(angleRad));
    float angleDeg = degrees(angleRad);
    return angleDeg;
}

// Calculate signed angular difference in sweep coordinates
// Result: negative = behind sweep, positive = ahead of sweep
float sweepAngleDiff(float pixelAngle, float sweepAngle) {
    float diff = pixelAngle - sweepAngle;

    // Handle wraparound at ±180° boundary
    if (diff > 180.0) {
        diff -= 360.0;
    } else if (diff < -180.0) {
        diff += 360.0;
    }

    return diff;
}

void main() {
    // Apply the same UV lift used by the original shader so geometry aligns
    vec2 uvR = vec2(v_uv.x, v_uv.y - u_uvYOffset);

    // Base intensity from returns
    float i = sampleIntensity(uvR);

    // Work entirely in degrees to avoid radian conversion issues
    vec2 p = uvR - kCenterUV;

    // Apply aspect ratio correction for proper circular geometry
    vec2 pCorrected = vec2(p.x * kAspectRatio, p.y);
    float r = length(pCorrected);

    // Adjust radius threshold by aspect ratio
    float inAperture = step(0.0, p.y) * step(r, kRadiusUV * kAspectRatio);

    // Get pixel angle in sweep coordinates (-180° to +180°, 0° = up)
    // Pass aspect ratio for proper angle calculation
    float pixAngle = pixelSweepAngle(p, kAspectRatio);

    // Calculate signed difference (negative = behind, positive = ahead)
    float angleDiff = sweepAngleDiff(pixAngle, u_sweepAngleDeg);

    float beamWidthDeg = max(0.1, u_beamWidthDeg) * 3.5;

    // Calculate both beam styles
    // Clockwise beam: sharp edge ahead, soft behind
    float cwLeadingCutoff = step(angleDiff, 0.0);
    //float cwTrailingFalloff = smoothstep(-beamWidthDeg, 0.0, angleDiff);
    float cwTrailingFalloff = step(-beamWidthDeg, angleDiff);
    float cwBeamMask = cwLeadingCutoff * cwTrailingFalloff;

    // Counter-clockwise beam: soft ahead, sharp behind
    float ccwTrailingCutoff = step(-angleDiff, 0.0);
    //float ccwLeadingFalloff = smoothstep(beamWidthDeg, 0.0, angleDiff);
    float ccwLeadingFalloff = step(angleDiff, beamWidthDeg);
    float ccwBeamMask = ccwTrailingCutoff * ccwLeadingFalloff;

    // Blend between beam styles based on sweep direction
    // u_sweepDirection: 1.0 = fully clockwise, -1.0 = fully counter-clockwise
    // Can also use values between -1 and 1 for smooth transitions
    float directionBlend = (u_sweepDirection + 1.0) * 0.5; // Convert [-1,1] to [0,1]
    float beamMask = mix(ccwBeamMask, cwBeamMask, directionBlend);

    // dynamic speed-based masking to hide the sector while beam is stationary
    float speedFactor = clamp(abs(u_antennaSpeedDPS) / 15.0, 0.0, 1.0);
    float maxSectorHalfWidth = mix(1.0, 100.0, speedFactor); // 10° total at 0°/s, 200° at 15°/s
    float sectorMask = smoothstep(maxSectorHalfWidth + 5.0, maxSectorHalfWidth, abs(angleDiff));

    // Combine aperture and beam
    float reveal = inAperture * beamMask * sectorMask;

    // Apply reveal to intensity
    float outI = i * reveal;

    // Map to phosphor green with proper intensity scaling
    float displayIntensity = 1.0 - exp(-outI * 1.5);

    vec3 color = u_phosphorColor * displayIntensity * 1.1;

    // The calculated displayIntensity is our alpha value.
    float alpha = displayIntensity;

    // For compatibility with the rest of the alpha-based pipeline,
    // we output the clean intensity in the green and alpha channels.
    fragColor = vec4(1, 1, 1, alpha * 0.5); //fragColor = vec4(0, 1, 0, 0.5);

    //float i = sampleIntensity(vec2(v_uv.x, v_uv.y - 0.15));
    //vec3 color = u_phosphorColor * i * 1.5;
    //
    //fragColor = vec4(color, 1.0);
}
