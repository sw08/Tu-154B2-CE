# Groza Weather Radar System — Technical Documentation

This directory implements the Tu-154's Groza weather radar display with realistic CRT phosphor rendering, animated sweep, and multi-pass shader effects.

## Overview

The Groza radar system renders X-Plane's weather radar returns as a classic analog radar display with:

- **Phosphor persistence** — Realistic afterglow decay simulating P7 phosphor CRT
- **Animated sweep beam** — Rotating antenna scan from -100° to +100° with realistic speed curves
- **Multi-pass rendering** — Bloom, persistence, and compositing for authentic analog appearance
- **Sweep reveal masking** — Returns appear only in areas swept by the antenna beam
- **Contour mode** — Optional cloud core visualization (black voids in high-intensity areas)

The system is built using SASL's OpenGL shader pipeline with ping-pong buffers for frame persistence and multi-pass bloom filtering.

## File Structure

```
radar/
├── radar.lua                    # Component entry point, property definitions
├── antenna_logic.lua            # NEW: Antenna physics and control system
├── radar_screen.lua             # Main rendering logic, shader orchestration
├── radar_exp.lua                # (Experimental/unused alternate implementation)
├── groza_radar.vert             # Vertex shader (pass-through UV mapping)
├── groza_radar.frag             # Fragment shader: radar returns + sweep reveal
├── groza_sweep.frag             # Sweep beam rendering (range rings + noise)
├── groza_persistence.frag       # Persistence/afterglow with decay
├── groza_bloom.frag             # Gaussian bloom (horizontal + vertical passes)
├── groza_postprocessing.frag    # (Unused) Post-processing placeholder
├── radar_angle_scale.png        # Bezel overlay (angle markings)
├── radar_line.png               # Visual assets
├── radar_mask.png               # Circular aperture mask
├── radar_mask_drift*.png        # Drift mode masks
└── README.md                    # This file
```

## Architecture

### Component Hierarchy

**radar.lua** (entry point):
- Creates `avionicsDevice` with 2048×2048 render target
- Defines global properties for radar state (antenna position, mode, brightness, etc.)
- Contains single component: `radar_screen {}`

**radar_screen.lua** (rendering engine):
- Implements multi-pass shader rendering pipeline
- Manages ping-pong buffers for persistence
- Animates antenna sweep with realistic acceleration curves
- Orchestrates 6+ render passes per frame

### Rendering Pipeline

The radar display is built through multiple rendering passes:

```
1. RADAR RETURNS PASS
   ├─ Input: X-Plane WX radar texture (AIRCRAFT_WXR_PILOT_TEX)
   ├─ Shader: groza_radar.frag
   ├─ Function: Sample radar returns, apply sweep reveal masking
   └─ Output: radar_composite_tex

2. SWEEP BEAM PASS (geometric)
   ├─ Shader: groza_sweep.frag
   ├─ Function: Draw rotating sweep line with range rings
   └─ Composited onto radar_composite_tex

3. BLOOM PASS 1 (horizontal)
   ├─ Input: radar_composite_tex
   ├─ Shader: groza_bloom.frag (dirx=1.0, diry=0.0)
   └─ Output: radar_bloom_pass1

4. BLOOM PASS 2 (vertical)
   ├─ Input: radar_bloom_pass1
   ├─ Shader: groza_bloom.frag (dirx=0.0, diry=1.0)
   └─ Output: radar_bloom_pass2

5. SWEEP BEAM RENDERING
   ├─ Shader: groza_sweep2.frag
   ├─ Function: Render bright sweep line (separate from returns)
   └─ Output: radar_beam_tex

6. BEAM BLOOM PASSES (2-pass Gaussian)
   ├─ Similar to steps 3-4, but with higher intensity (4.0)
   └─ Output: radar_beam_bloom2

7. PERSISTENCE PASS
   ├─ Input: radar_bloom_pass2 (current frame) + previous_frame (ping-pong buffer)
   ├─ Shader: groza_persistence.frag
   ├─ Function: max(new_intensity, previous_intensity * decay_factor)
   └─ Output: dst_prev (next frame's "previous" buffer)

8. FINAL COMPOSITE
   ├─ Blend: persistence output + bloomed sweep beam
   ├─ Color: Green phosphor tint applied
   └─ Output: Screen display
```

### Ping-Pong Persistence Buffers

Frame persistence uses two render targets that swap each frame:

```lua
previous_frame_a = sasl.gl.createRenderTarget(2048, 1504)
previous_frame_b = sasl.gl.createRenderTarget(2048, 1504)
use_prev_a = true  -- toggles each frame
```

**Algorithm**:
1. Read from `use_prev_a ? previous_frame_a : previous_frame_b`
2. Render persistence to `use_prev_a ? previous_frame_b : previous_frame_a`
3. Swap `use_prev_a` flag
4. Result: Each frame sees the previous frame's output, creating afterglow

## Shaders Explained

### groza_radar.frag (Returns + Sweep Reveal)

**Purpose**: Processes raw X-Plane weather returns and masks them by sweep position.

**Key uniforms**:
- `u_returns` — X-Plane weather radar texture (red channel = return strength)
- `u_sweepAngleDeg` — Current antenna azimuth (-100° to +100°, 0° = up)
- `u_beamWidthDeg` — Angular width of the sweep beam (default: 4°)
- `u_sweepDirection` — 1.0 = clockwise, -1.0 = counter-clockwise
- `u_gain`, `u_bias`, `u_gamma`, `u_contrast`, `u_brightness` — Return intensity processing
- `u_contourMode` — Enable cloud core voiding (black areas in high-intensity regions)
- `u_contourThreshold` — Threshold for contour mode (0..1)

**Process**:
1. Sample radar return intensity from `u_returns` texture
2. Apply contour mode masking if enabled (zero out cores above threshold)
3. Process intensity: bias removal → gain → gamma correction → contrast/brightness
4. Calculate pixel angle relative to sweep center
5. Compute angular difference between pixel and sweep beam
6. Generate beam mask (sharp leading edge, soft trailing edge varies by sweep direction)
7. Apply reveal mask: `output = intensity * beamMask * apertureMask`

**Output**: RGBA with intensity in alpha channel (used by bloom/persistence)

### groza_sweep.frag (Sweep Line + Range Rings)

**Purpose**: Renders the rotating sweep line and concentric range rings.

**Features**:
- Procedural range rings at 30%, 50%, 70%, 90%, 110% of radius
- Hash-based noise for CRT texture
- Hard clip at ±100° sector
- Aspect ratio correction for circular geometry

**Output**: Green-tinted sweep line with noise and rings

### groza_persistence.frag (Afterglow Decay)

**Purpose**: Implements phosphor persistence with exponential decay.

**Algorithm**:
```glsl
new_intensity = texture(render_target, v_uv).g;
previous_intensity = texture(u_prev, v_uv).g;
decayed_intensity = previous_intensity * u_decay;
i = max(new_intensity, decayed_intensity);  // New returns override old
```

**Uniforms**:
- `u_decay` — Decay factor per frame (default: 0.92, range: 0..1)
- `u_floorSubtract` — Black level clamp to prevent infinite residue (0.0011)
- `u_floorThreshold` — Hard cutoff for near-zero values (0.0001)

**Behavior**:
- New radar returns appear at full brightness immediately
- Old returns fade exponentially at ~8% per frame
- Black-level clamping prevents "zombie pixels" that never fully disappear

### groza_bloom.frag (Gaussian Blur)

**Purpose**: Two-pass separable Gaussian bloom for CRT glow effect.

**Implementation**:
- 11-tap Gaussian kernel applied in one dimension per pass
- Pass 1: Horizontal blur (`dirx=1.0, diry=0.0`)
- Pass 2: Vertical blur (`dirx=0.0, diry=1.0`)

**Uniforms**:
- `dirx`, `diry` — Blur direction (1.0 for active axis, 0.0 for inactive)
- `intensity` — Bloom strength multiplier (radar: 1.5, beam: 4.0)

**Output**: Bloomed RGBA with preserved alpha channel

## Antenna Control System

The radar uses a realistic antenna control system matching the actual **Groza-26** weather radar specifications, implemented in `antenna_logic.lua`.

### Architecture

**Component Structure**:
- `antenna_logic.lua` — Physics simulation and control logic matching Groza-26 specs
- `radar_screen.lua` — Reads antenna state and renders display
- X-Plane integration — Drives actual weather returns calculation

### Groza-26 Specifications

**Azimuth Sweep**:
- Fixed sector: **±100°** from aircraft structural axis (200° total)
- Smooth acceleration/deceleration with quadratic slowdown near edges
- Max rotation rate: 90°/s at sector center
- Edge pause: 0.15s pause at scan limits before reversing
- Realistic servo dynamics with acceleration limits (120°/s²)

**Elevation/Tilt Control**:
- Manual tilt range: **10° up, 15° down**
- Slew rate: 5°/second
- Stabilization: Handled by X-Plane's built-in radar stabilization system
- Toggle via cockpit switch: `tu154b2/custom/systems/radar/stabilization_sw` (0=off, 1=on)

**Scan Pattern**:
- Continuous ±100° sector scan
- Automatic edge detection and reversal
- Parks at center when not actively scanning

### Operating Modes

Groza-26 modes (from `radar.lua:Radar.Modes`):

| Mode | Value | Russian Name | Description |
|------|-------|--------------|-------------|
| READY | 0 | Готов | Ready/Standby - powered but not scanning |
| MAP | 1 | Земля | "Earth" - terrain/ground mapping |
| WEATHER | 2 | Гроза | "Storm" - weather/storm detection |
| TURB | 3 | Турбулентность | Turbulence detection |
| DRIFT | 4 | Снос | Drift angle measurement (±20°) |

### Power and Warmup

**Power Requirements** (Groza-26 specifications):
- **27V DC** bus > 24V
- **36V AC** bus > 32V (400 Hz)
- **115V AC** bus > 110V

**Warmup Sequence**:
- **4 minute** warmup period after power-on (spec: 3-5 minutes)
- Antenna remains parked at center during warmup
- Display shows warmup progress
- Mode must be set to operational mode after warmup completes

**Power Consumption** (27V current draw):
- Ready/Standby: 0.5A
- Warmup: 2.5A
- Active scanning: 4.0A
- Transmitting (9kW pulse): +6.0A (total 10.0A)

### Technical Specifications

**Transmitter**:
- Carrier frequency: **9,370 MHz** (X-band)
- Pulse power: **9 kW minimum**

**Detection Ranges**:
- Large cities: 270 km
- Mountain peaks (2,500-6,000m): 250 km
- Active storm zones: 120 km

**Display Range Scales**:
- 30, 50, 125, 250, 375 km selectable
- 375 km scale starts at 200 km range

**Safety**:
- 15 meter minimum distance from antenna during ground testing with active transmission

### DataRefs

**Inputs** (from cockpit controls):
```
tu154b/custom/systems/radar/antenna_power               — Power switch (0/1)
tu154b/custom/systems/radar/mode                        — Operating mode (0=Ready, 1=Map, 2=Weather, 3=Turb, 4=Drift)
tu154b/custom/systems/radar/range                       — Display range (30/50/125/250/375 km)
tu154b/custom/systems/radar/antenna_commanded_elevation — Tilt command (-10 to +15 degrees)
```

**Outputs** (antenna state):
```
tu154b/custom/systems/radar/antenna_azimuth     — Current azimuth angle (-100 to +100 degrees)
tu154b/custom/systems/radar/antenna_elevation   — Current tilt angle (-10 to +15 degrees)
tu154b/custom/systems/radar/antenna_speed_dps   — Rotation velocity (degrees/second)
tu154b/custom/systems/radar/scan_active         — Scanning active flag (0/1)
tu154b/custom/systems/radar/warmup_progress     — Warmup completion (0.0 to 1.0)
tu154b/custom/systems/radar/stabilization_sw    — Stabilization switch state (0=off, 1=on)
```

**X-Plane Integration** (drives weather returns):
```
sim/cockpit2/EFIS/EFIS_weather_pilot_angle                    — Synced to antenna_azimuth
sim/cockpit2/radios/actuators/weather_radar_tilt_angle_pilot  — Synced to antenna_elevation
sim/cockpit2/EFIS/EFIS_weather_sector_width                   — Set to 200° (±100° sector)
sim/cockpit2/EFIS/EFIS_weather_stab                           — Synced to stabilization_sw (X-Plane handles stabilization)
```

### Commands

The antenna system provides the following commands for cockpit integration:

```
tu154b2/radar/stabilization_toggle      — Toggle pitch stabilization on/off
tu154b2/radar/tilt_up                   — Tilt antenna up 1°
tu154b2/radar/tilt_down                 — Tilt antenna down 1°
```

### Stabilization System

**X-Plane Built-in Stabilization**:
- Radar stabilization is handled entirely by X-Plane's simulation
- When enabled, X-Plane compensates for aircraft pitch and roll in the returned weather texture
- The antenna system only passes the switch state to X-Plane via `sim/cockpit2/EFIS/EFIS_weather_stab`

**Cockpit Control**:
- Stabilization switch: `tu154b2/custom/systems/radar/stabilization_sw` (0=off, 1=on)
- Toggle command: `tu154b2/radar/stabilization_toggle`
- When ON: X-Plane applies pitch/roll compensation to radar returns
- When OFF: Raw antenna-relative radar returns (no stabilization)

## Global Properties

Defined in `radar.lua`:

```lua
Radar = {
    antenna_azimuth                -- Current antenna azimuth (read-only)
    tx_power                       -- Transmitter power (0/1)
    antenna_commanded_azimuth      -- Pilot-commanded azimuth
    antenna_commanded_elevation    -- Pilot-commanded tilt
    radar_mode                     -- Operating mode (see Modes enum)
    brightness                     -- Display brightness (0..1)
    sym_brt                        -- Symbol brightness (0..1)
    contrast                       -- Display contrast (0..1)
    frequency                      -- Transmit frequency

    Modes = {
        Ready = 0,
        Map = 1,
        Weather = 2,
        Turb = 3,
        Drift = 4
    }
}
```

**X-Plane Integration**:
- Reads from `AIRCRAFT_WXR_PILOT_TEX` (X-Plane's computed weather returns)
- Sets `sim/cockpit2/EFIS/EFIS_weather_sector_width` to 100° on initialization

## Coordinate Systems

### UV Space (Texture Coordinates)
- Origin: Bottom-left (0, 0)
- Radar center: (0.5, 0.15) after `u_uvYOffset` adjustment
- Radius: ~0.51 in UV units
- Aspect ratio: 2048 / 1504 ≈ 1.36

### Sweep Angles
- 0° = North (up)
- Positive = Clockwise
- Range: -100° to +100° (±100° sector)
- Conversion: `atan(y, x)` rotated by +90° for 0° = up

### Screen Space
- Panel texture: 2048×2048 pixels
- Radar viewport: 2048×1504 pixels (bottom portion)
- Bezel size: 2048×1054 pixels

## Render Targets

All targets are 2048×1504 pixels:

| Target | Purpose |
|--------|---------|
| `radar_composite_tex` | Returns + sweep geometry |
| `radar_bloom_pass1` | Horizontal bloom |
| `radar_bloom_pass2` | Vertical bloom (final returns) |
| `radar_beam_tex` | Sweep beam line |
| `radar_beam_bloom1` | Beam horizontal bloom |
| `radar_beam_bloom2` | Beam vertical bloom |
| `previous_frame_a` | Persistence ping-pong buffer A |
| `previous_frame_b` | Persistence ping-pong buffer B |
| `final_composite` | Combined returns + beam |

## Performance Considerations

**Render passes per frame**: 8+
- 1× radar returns
- 1× sweep geometry
- 2× bloom (returns)
- 1× sweep beam
- 2× bloom (beam)
- 1× persistence
- 1× final composite

**Optimizations**:
- Separable Gaussian blur (2 passes instead of N²)
- Ping-pong buffers avoid full-screen copy
- Shader branching minimized (use mix/step instead of if)
- Aspect ratio correction done once in vertex shader where possible

## Tuning Parameters

### Return Intensity (groza_radar.frag)

```glsl
u_gain = 0.09           // Signal amplification
u_bias = 0.06           // Noise floor threshold
u_gamma = 0.25          // Gamma correction (lower = brighter mids)
u_brightness = 0.02     // Brightness offset
u_contrast = 1.8        // Contrast multiplier
```

**Adjusting for visibility**:
- Weak returns not visible → Increase `u_gain` or decrease `u_bias`
- Too washed out → Decrease `u_gamma` or increase `u_contrast`
- Need more dynamic range → Adjust `u_brightness` and `u_contrast` together

### Persistence Decay

```glsl
u_decay = 0.92          // ~8% fade per frame at 60fps
u_floorSubtract = 0.0011
u_floorThreshold = 0.0001
```

**Adjusting decay**:
- Slower fade (longer trails) → Increase `u_decay` (e.g., 0.95)
- Faster fade (crisp) → Decrease `u_decay` (e.g., 0.88)
- Ghosting issues → Lower `u_floorThreshold`

### Bloom Intensity

```lua
-- Returns bloom
intensity = 1.5

-- Beam bloom
intensity = 4.0
```

**Adjusting glow**:
- More CRT glow → Increase intensity values
- Sharper image → Decrease intensity or reduce kernel weights in shader

### Sweep Animation

```lua
sweep_speed_max = 80        -- Degrees/second at center
delay_timer = 0.2           -- Pause at edges (seconds)
slowdown_factor = 1 - (norm * norm)  -- Quadratic edge slowdown
```

**Adjusting sweep**:
- Faster scan → Increase `sweep_speed_max`
- Smoother motion → Adjust slowdown curve (e.g., cubic: `norm * norm * norm`)
- Longer pause at edges → Increase `delay_timer`

## Contour Mode

When `u_contourMode = true` in `groza_radar.frag`:

**Behavior**: Areas with return intensity above `u_contourThreshold` are rendered black (voided), creating a "cloud core" visualization where the most intense precipitation appears as dark voids.

**Physics**: Simulates X-band radar attenuation where extremely heavy precipitation can appear as shadows (attenuation zones).

**Implementation**:
```glsl
float contourMask = 1.0 - (u_contourMode ? step(u_contourThreshold, r) : 0.0);
r *= contourMask;  // Zero out cores
```

## Integration with Aircraft

### Component Declaration

In `main_panel.lua`:
```lua
radar {
    position = { x, y, width, height },  -- Panel texture position
},
```

The radar component automatically instantiates:
1. `antenna_logic` — Antenna control system (runs in update loop)
2. `radar_screen` — Display rendering (runs in draw loop)

### Cockpit Panel Integration

**Required Controls**:

1. **Power Switch** → `tu154b/custom/systems/radar/antenna_power`
   - 0 = OFF, 1 = ON
   - Initiates 4-minute warmup sequence
   
2. **Mode Selector** → `tu154b/custom/systems/radar/mode`
   - 0 = Ready (Готов) - standby
   - 1 = Map (Земля) - terrain mapping
   - 2 = Weather (Гроза) - storm detection
   - 3 = Turb (Турбулентность) - turbulence
   - 4 = Drift (Снос) - drift angle measurement
   
3. **Tilt Knob** → `tu154b/custom/systems/radar/antenna_commanded_elevation`
   - Range: -10° (up) to +15° (down)
   - Can be linked to rotary encoder or up/down commands

4. **Stabilization Switch** → `tu154b2/custom/systems/radar/stabilization_sw`
   - 0 = OFF (raw antenna-relative returns)
   - 1 = ON (X-Plane applies pitch/roll compensation)
   - Toggle command: `tu154b2/radar/stabilization_toggle`

**Optional Controls**:
- Range selector → `tu154b/custom/systems/radar/range` (30/50/125/250/375 km)
- Brightness → `tu154b/custom/systems/radar/brightness`
- Contrast → `tu154b/custom/systems/radar/contrast`

**Warmup Indicator**:
- Monitor `tu154b2/custom/systems/radar/warmup_progress` (0.0 to 1.0) for warmup status
- Display can show "WARMING UP" or progress bar during 4-minute sequence

### Electrical System Integration

The antenna logic automatically monitors:
- `tu154b2/custom/elec/bus27_volt_left` (requires >24V)
- `tu154b2/custom/elec/bus36_volt_left` (requires >32V, 400Hz)
- `tu154b2/custom/elec/bus115_1_volt` (requires >110V)

Writes current consumption to `tu154b2/custom/radio/radar_cc`:
- Ready: 0.5A
- Warmup: 2.5A
- Scanning: 4.0A
- Transmitting: 10.0A (includes 9kW pulse power)

Ensure your electrical system reads `radar_cc` and applies load to 27V bus.

### Failure System Integration

Set `tu154b2/custom/failures/radar_fail` to 1 to simulate radar failure. The antenna system will:
- Immediately shut down
- Park antenna at center
- Zero power consumption
- Stop X-Plane radar returns

### Display Integration

If integrating the radar display into a 3D cockpit or popup panel, reference the `radar_device` avionicsDevice. The display automatically updates when the antenna is scanning.

## Debugging

### Visual Debugging

To isolate rendering stages, comment out passes in `radar_screen.lua:draw()`:

```lua
-- Skip persistence to see raw returns
-- sasl.gl.useShaderProgram(groza_pers_shader)
-- ...

-- Show only bloom output
sasl.gl.drawTexture(radar_bloom_pass2, 0, 0, size[1], size[2], {1,1,1,1})
```

### Common Issues

**No radar returns visible**:
1. Check X-Plane weather is enabled and radar texture is loaded
2. Verify `u_gain` and `u_bias` values (may need higher gain)
3. Ensure sweep animation is running (`get(antenna_sweep)` changing)
4. Check bloom passes aren't over-saturating alpha channel

**Ghosting/persistence artifacts**:
1. Increase `u_floorSubtract` to eliminate "zombie pixels"
2. Lower `u_decay` for faster fade
3. Check ping-pong buffer swap logic in `draw()`

**Sweep beam not visible**:
1. Verify beam bloom intensity (should be ~4.0)
2. Check beam geometry drawing in sweep passes
3. Ensure beam texture is composited in final output

**Performance issues**:
1. Reduce bloom kernel size (fewer taps in `groza_bloom.frag`)
2. Lower render target resolution (modify `size` in `radar_screen.lua`)
3. Disable persistence (comment out persistence pass)

## Future Enhancements

Potential improvements not yet implemented:

- **Gain/tilt controls**: Wire cockpit knobs to shader uniforms
- **Sector scan mode**: Narrow scan sector (e.g., ±30°) for focused weather analysis
- **TAWS integration**: Overlay terrain returns from separate system
- **Turbulence mode**: Different color mapping for turbulence detection
- **Manual gain**: User-adjustable `u_gain` and `u_contrast` via cockpit controls
- **Range rings**: Dynamic range markings based on selected range (currently static)

## Technical Notes

### Why Ping-Pong Buffers?

Reading and writing to the same render target in a single shader pass is undefined behavior. Ping-pong buffers ensure:
- Previous frame is read from buffer A
- Current frame is written to buffer B
- Next frame swaps: read B, write A

This creates frame-to-frame persistence without feedback loops.

### Aspect Ratio Correction

The radar display is not square (2048×1504), but the radar scope should appear circular. Shaders apply aspect ratio correction:

```glsl
vec2 pCorrected = vec2(p.x * kAspectRatio, p.y);
float r = length(pCorrected);  // Circular in corrected space
```

Without correction, the scope would appear elliptical.

### Sweep Reveal Algorithm

The shader calculates whether a pixel should be visible based on sweep position:

1. Calculate pixel angle relative to radar center
2. Compute angular difference from sweep beam center
3. Generate mask with sharp leading edge (newly swept area) and soft trailing edge (fading behind beam)
4. Blend between clockwise/counter-clockwise beam shapes based on `u_sweepDirection`

This creates the classic "wiping" reveal as the antenna rotates.

## File Dependencies

**Required textures**:
- X-Plane: `AIRCRAFT_WXR_PILOT_TEX` (weather returns)
- Local: `Reticle.png` (currently unused in render)

**Required SASL APIs**:
- `sasl.gl.createRenderTarget()`
- `sasl.gl.createShaderProgram()`
- `sasl.gl.loadShader()`, `sasl.gl.linkShaderProgram()`
- `sasl.gl.useShaderProgram()`, `sasl.gl.setShaderUniform()`
- `sasl.gl.importXPTexture()`

**Global dependencies**:
- `tu154b2/custom/time/frame_time` — Delta time for sweep animation

## Attribution

Shader implementation based on CRT phosphor persistence techniques and standard radar sweep animation patterns. Gaussian bloom uses separable filter optimization.
