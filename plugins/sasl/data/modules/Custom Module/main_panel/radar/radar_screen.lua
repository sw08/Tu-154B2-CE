local size = { 2048, 1504 }

local radar_shader = sasl.gl.createShaderProgram()
sasl.gl.loadShader(radar_shader, "groza_radar.vert", SHADER_TYPE_VERTEX)
sasl.gl.loadShader(radar_shader, "groza_radar.frag", SHADER_TYPE_FRAGMENT)
sasl.gl.linkShaderProgram(radar_shader)

local groza_sweep_shader = sasl.gl.createShaderProgram()
sasl.gl.loadShader(groza_sweep_shader, "groza_radar.vert", SHADER_TYPE_VERTEX)
sasl.gl.loadShader(groza_sweep_shader, "groza_sweep.frag", SHADER_TYPE_FRAGMENT)
sasl.gl.linkShaderProgram(groza_sweep_shader)

local groza_sweep2_shader = sasl.gl.createShaderProgram()
sasl.gl.loadShader(groza_sweep2_shader, "groza_radar.vert", SHADER_TYPE_VERTEX)
sasl.gl.loadShader(groza_sweep2_shader, "groza_sweep.frag", SHADER_TYPE_FRAGMENT)
sasl.gl.linkShaderProgram(groza_sweep2_shader)

local groza_post_shader = sasl.gl.createShaderProgram()
sasl.gl.loadShader(groza_post_shader, "groza_radar.vert", SHADER_TYPE_VERTEX)
sasl.gl.loadShader(groza_post_shader, "groza_postprocessing.frag", SHADER_TYPE_FRAGMENT)
sasl.gl.linkShaderProgram(groza_post_shader)

local groza_pers_shader = sasl.gl.createShaderProgram()
sasl.gl.loadShader(groza_pers_shader, "groza_radar.vert", SHADER_TYPE_VERTEX)
sasl.gl.loadShader(groza_pers_shader, "groza_persistence.frag", SHADER_TYPE_FRAGMENT)
sasl.gl.linkShaderProgram(groza_pers_shader)

local groza_bloom_shader = sasl.gl.createShaderProgram()
sasl.gl.loadShader(groza_bloom_shader, "groza_radar.vert", SHADER_TYPE_VERTEX)
sasl.gl.loadShader(groza_bloom_shader, "groza_bloom.frag", SHADER_TYPE_FRAGMENT)
sasl.gl.linkShaderProgram(groza_bloom_shader)

local radar_composite_tex = sasl.gl.createRenderTarget(size[1], size[2])
local radar_bloom_pass1 = sasl.gl.createRenderTarget(size[1], size[2])
local radar_bloom_pass2 = sasl.gl.createRenderTarget(size[1], size[2])

local radar_beam_tex = sasl.gl.createRenderTarget(size[1], size[2])
local radar_beam_bloom1 = sasl.gl.createRenderTarget(size[1], size[2])
local radar_beam_bloom2 = sasl.gl.createRenderTarget(size[1], size[2])

-- Ping-pong buffers for previous frame (for persistence)
local previous_frame_a = sasl.gl.createRenderTarget(size[1], size[2])
local previous_frame_b = sasl.gl.createRenderTarget(size[1], size[2])
local use_prev_a = true

--local radar_reticle = sasl.gl.loadImage("Reticle.png")

local final_composite = sasl.gl.createRenderTarget(size[1], size[2])
local final_frame = sasl.gl.createRenderTarget(size[1], size[2])



local wxr_returns = nil
local dt = 0


local smooth_speed = 0.0       -- Smoothed antenna speed for masking
local SPEED_ATTACK_TIME = 22.0 -- Seconds to open sector (slow attack)
local SPEED_DECAY_TIME = 0.5   -- Seconds to close sector (fast decay)

-- Range arcs (normalized fractions of max range for each scale setting)
-- Based on table: scale marks at specific km intervals
local range_arcs = {
    [0] = { 0.333, 0.667, 1.0, 0, 0 }, -- 30km:  marks at 10, 20, 30 km
    [1] = { 0.2, 0.4, 0.6, 0.8, 1.0 }, -- 50km:  marks at 10, 20, 30, 40, 50 km
    [2] = { 0.2, 0.4, 0.6, 0.8, 1.0 }, -- 125km: marks at 25, 50, 75, 100, 125 km
    [3] = { 0.2, 0.4, 0.6, 0.8, 1.0 }, -- 250km: marks at 50, 100, 150, 200, 250 km
    [4] = { 0.25, 0.5, 0.75, 1.0, 0 }  -- 375km: marks at 250, 300, 350, 400 km (200-400 range)
}

--------------------------------------------------------------------------------
-- Get current antenna state for rendering
--------------------------------------------------------------------------------
local function getAntennaState()
    return {
        azimuth = get(antenna_azimuth),
        elevation = get(antenna_elevation),
        velocity = get(antenna_velocity),
        active = get(scan_active) > 0
    }
end

--------------------------------------------------------------------------------
-- PASS 1: Render radar returns with sweep reveal masking
--------------------------------------------------------------------------------
local function renderRadarReturns(antenna)
    sasl.gl.setRenderTarget(radar_composite_tex)

    sasl.gl.useShaderProgram(radar_shader)
    sasl.gl.setShaderUniform(radar_shader, "u_returns", TYPE_SAMPLER, wxr_returns, 0)
    sasl.gl.setShaderUniform(radar_shader, "kViewportSize", TYPE_FLOAT_ARRAY, size)
    sasl.gl.setShaderUniform(radar_shader, "u_sweepAngleDeg", TYPE_FLOAT, antenna.azimuth)
    sasl.gl.setShaderUniform(radar_shader, "u_beamWidthDeg", TYPE_FLOAT, 4.0)
    sasl.gl.setShaderUniform(radar_shader, "u_uvYOffset", TYPE_FLOAT, 0.15)

    local speed_dps = math.abs(antenna.velocity)
    sasl.gl.setShaderUniform(radar_shader, "u_antennaSpeedDPS", TYPE_FLOAT, speed_dps)

    -- Determine sweep direction from velocity
    -- Determine sweep direction from velocity (negative => -1, positive or zero => 1)
    local sweep_dir = (antenna.velocity < 0) and -1 or 1
    sasl.gl.setShaderUniform(radar_shader, "u_sweepDirection", TYPE_FLOAT, sweep_dir)

    sasl.gl.drawRectangle(0, 230, size[1], size[2], { 1, 1, 1, 1 })
    sasl.gl.stopShaderProgram(radar_shader)
end

--------------------------------------------------------------------------------
-- PASS 2: Render sweep geometry (range rings and triangular beam)
--------------------------------------------------------------------------------
local function renderSweepGeometry(antenna)
    local radius = 1050
    local speed_dps = math.abs(antenna.velocity)

    local dt = frame_time:get() -- Approximate frame time
    local actual_speed = math.abs(antenna.velocity)

    if actual_speed > smooth_speed then
        -- Attack: slowly increase smooth_speed (sector opening)
        local attack_rate = 90.0 / SPEED_ATTACK_TIME -- degrees/s²
        smooth_speed = smooth_speed + attack_rate * dt
        smooth_speed = math.min(smooth_speed, actual_speed)
    else
        -- Decay: quickly decrease smooth_speed (sector closing)
        local decay_rate = 90.0 / SPEED_DECAY_TIME
        smooth_speed = smooth_speed - decay_rate * dt
        smooth_speed = math.max(smooth_speed, actual_speed)
    end

    -- Dynamic beam width based on antenna speed
    -- Slow/stopped: narrow beam (1°), Fast (55+ dps): wide sector (101°)
    local speedFactor = math.min(smooth_speed / 55.0, 1.0)
    local beam_half_angle = 1.0 + (50.0 - 1.0) * speedFactor
    local half_rad = math.rad(beam_half_angle)

    sasl.gl.useShaderProgram(groza_sweep_shader)
    sasl.gl.setShaderUniform(groza_sweep_shader, "time", TYPE_FLOAT, dt)
    sasl.gl.setShaderUniform(groza_sweep_shader, "sym_brt", TYPE_FLOAT, get(radar_symbol_brightness))
    sasl.gl.setShaderUniform(groza_sweep_shader, "arcs", TYPE_FLOAT_ARRAY, range_arcs[radar_range:get()])


    sasl.gl.saveGraphicsContext()
    sasl.gl.setTranslateTransform(1024, 230)
    sasl.gl.setRotateTransform(antenna.azimuth)

    local x1, y1 = 0, 0
    local x2, y2, x3, y3

    -- Determine sweep direction from azimuth position
    local sweep_dir = (antenna.velocity < 0) and -1 or 1

    if sweep_dir == -1 then
        x2, y2 = math.sin(-half_rad + half_rad) * radius, math.cos(-half_rad + half_rad) * radius
        x3, y3 = math.sin(half_rad + half_rad) * radius, math.cos(half_rad + half_rad) * radius
    elseif sweep_dir == 1 then
        x2, y2 = math.sin(-half_rad - half_rad) * radius, math.cos(-half_rad - half_rad) * radius
        x3, y3 = math.sin(half_rad - half_rad) * radius, math.cos(half_rad - half_rad) * radius
    end

    sasl.gl.drawTriangle(x1, y1, x2, y2, x3, y3, { 1, 1, 1, 1 })
    sasl.gl.restoreGraphicsContext()
    sasl.gl.stopShaderProgram(groza_sweep_shader)

    sasl.gl.restoreRenderTarget()
end

--------------------------------------------------------------------------------
-- PASS 3-4: Apply two-pass bloom to radar returns
--------------------------------------------------------------------------------
local function applyRadarBloom()
    -- Horizontal bloom pass
    sasl.gl.setRenderTarget(radar_bloom_pass1)
    sasl.gl.useShaderProgram(groza_bloom_shader)
    sasl.gl.setShaderUniform(groza_bloom_shader, "render_target", TYPE_SAMPLER, radar_composite_tex, 0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "dirx", TYPE_FLOAT, 1.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "diry", TYPE_FLOAT, 0.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "intensity", TYPE_FLOAT, 1.5)
    sasl.gl.drawRectangle(0, 0, size[1], size[2], { 1, 1, 1, 1 })
    sasl.gl.stopShaderProgram(groza_bloom_shader)
    sasl.gl.restoreRenderTarget()

    -- Vertical bloom pass
    sasl.gl.setRenderTarget(radar_bloom_pass2)
    sasl.gl.useShaderProgram(groza_bloom_shader)
    sasl.gl.setShaderUniform(groza_bloom_shader, "render_target", TYPE_SAMPLER, radar_bloom_pass1, 0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "dirx", TYPE_FLOAT, 0.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "diry", TYPE_FLOAT, 1.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "intensity", TYPE_FLOAT, 1.5)
    sasl.gl.drawRectangle(0, 0, size[1], size[2], { 1, 1, 1, 1 })
    sasl.gl.stopShaderProgram(groza_bloom_shader)
    sasl.gl.restoreRenderTarget()
end

--------------------------------------------------------------------------------
-- PASS 5: Render bright sweep beam line
--------------------------------------------------------------------------------
local function renderSweepBeam(antenna)
    sasl.gl.setRenderTarget(radar_beam_tex)
    sasl.gl.useShaderProgram(groza_sweep2_shader)
    sasl.gl.setShaderUniform(groza_sweep2_shader, "time", TYPE_FLOAT, dt)
    sasl.gl.setShaderUniform(groza_sweep_shader, "arcs", TYPE_FLOAT_ARRAY, range_arcs[radar_range:get()])
    sasl.gl.setShaderUniform(groza_sweep_shader, "sym_brt", TYPE_FLOAT, get(radar_symbol_brightness))

    sasl.gl.saveGraphicsContext()
    sasl.gl.setTranslateTransform(1024, 230)
    sasl.gl.setRotateTransform(antenna.azimuth)
    sasl.gl.drawRectangle(-10, 0, 20, 1042, { 1, 1, 1, 1 })
    sasl.gl.restoreGraphicsContext()

    sasl.gl.stopShaderProgram(groza_sweep2_shader)
    sasl.gl.restoreRenderTarget()
end

--------------------------------------------------------------------------------
-- PASS 6-7: Apply two-pass bloom to sweep beam
--------------------------------------------------------------------------------
local function applyBeamBloom()
    -- Horizontal bloom pass
    sasl.gl.setRenderTarget(radar_beam_bloom1)
    sasl.gl.useShaderProgram(groza_bloom_shader)
    sasl.gl.setShaderUniform(groza_bloom_shader, "render_target", TYPE_SAMPLER, radar_beam_tex, 0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "dirx", TYPE_FLOAT, 1.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "diry", TYPE_FLOAT, 0.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "intensity", TYPE_FLOAT, 4.0)
    sasl.gl.drawRectangle(0, 0, size[1], size[2], { 1, 1, 1, 1 })
    sasl.gl.stopShaderProgram(groza_bloom_shader)
    sasl.gl.restoreRenderTarget()

    -- Vertical bloom pass
    sasl.gl.setRenderTarget(radar_beam_bloom2)
    sasl.gl.useShaderProgram(groza_bloom_shader)
    sasl.gl.setShaderUniform(groza_bloom_shader, "render_target", TYPE_SAMPLER, radar_beam_bloom1, 0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "intensity", TYPE_FLOAT, 4.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "dirx", TYPE_FLOAT, 0.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "diry", TYPE_FLOAT, 1.0)
    sasl.gl.drawRectangle(0, 0, size[1], size[2], { 1, 1, 1, 1 })
    sasl.gl.stopShaderProgram(groza_bloom_shader)
    sasl.gl.restoreRenderTarget()
end

--------------------------------------------------------------------------------
-- PASS 8: Apply persistence/afterglow decay using ping-pong buffers
--------------------------------------------------------------------------------
local function applyPersistence(prev_tex, dst_prev)
    sasl.gl.setRenderTarget(dst_prev)
    sasl.gl.useShaderProgram(groza_pers_shader)
    sasl.gl.setShaderUniform(groza_pers_shader, "render_target", TYPE_SAMPLER, radar_bloom_pass2, 0)
    sasl.gl.setShaderUniform(groza_pers_shader, "u_prev", TYPE_SAMPLER, prev_tex, 1)
    sasl.gl.setShaderUniform(groza_pers_shader, "u_decay", TYPE_FLOAT, 0.50012)
    sasl.gl.drawRectangle(0, 0, size[1], size[2], { 1, 1, 1, 1 })
    sasl.gl.stopShaderProgram(groza_pers_shader)
    sasl.gl.restoreRenderTarget()
end

--------------------------------------------------------------------------------
-- PASS 9: Composite persistence and sweep beam
--------------------------------------------------------------------------------
local function compositeFinal(dst_prev)
    sasl.gl.setRenderTarget(final_composite)
    sasl.gl.drawTexture(dst_prev, 0, 0, size[1], size[2], { 1, 1, 1, 1 })
    sasl.gl.drawTexture(radar_beam_bloom2, 0, 0, size[1], size[2], { 0.7, 1, 0.4, 1 })
    sasl.gl.restoreRenderTarget()
end

--------------------------------------------------------------------------------
-- PASS 10: Final screen output with blending
--------------------------------------------------------------------------------
local function drawFinalOutput()
    sasl.gl.setBlendFunction(BLEND_SOURCE_ALPHA, 1)
    sasl.gl.setBlendEquation(BLEND_EQUATION_ADD)
    sasl.gl.drawTexture(final_composite, 0, 0, size[1], size[2], { 2, 2, 2, 2 })
    sasl.gl.resetBlending()
end

--------------------------------------------------------------------------------
-- Main update loop: Execute all render passes
--------------------------------------------------------------------------------
function update()
    dt = dt + 0.016
    if dt > 1 then
        dt = 0
    end

    -- Get current antenna state from antenna_logic.lua
    local antenna = getAntennaState()

    renderRadarReturns(antenna)
    renderSweepGeometry(antenna)
    applyRadarBloom()
    renderSweepBeam(antenna)
    applyBeamBloom()
end

function onModuleInit()
    wxr_returns = sasl.gl.importXPTexture(AIRCRAFT_WXR_PILOT_TEX)
end

--------------------------------------------------------------------------------
-- Main draw loop: Apply persistence and composite to screen
--------------------------------------------------------------------------------
function draw()
    local prev_tex = use_prev_a and previous_frame_a or previous_frame_b
    local dst_prev = use_prev_a and previous_frame_b or previous_frame_a

    applyPersistence(prev_tex, dst_prev)
    compositeFinal(dst_prev)
    drawFinalOutput()

    use_prev_a = not use_prev_a
end
