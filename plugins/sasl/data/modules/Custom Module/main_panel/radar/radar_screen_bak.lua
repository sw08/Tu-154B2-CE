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
dst_prev = 0

local radar_reticle = sasl.gl.loadImage("Reticle.png")

local final_composite = sasl.gl.createRenderTarget(size[1], size[2])
local final_frame = sasl.gl.createRenderTarget(size[1], size[2])

-- current sweep angle
antenna_sweep = createGlobalPropertyf("tu154b2/custom/wxr/antenna_sweep", 0)
antenna_speed_dps = createGlobalPropertyf("tu154b2/custom/wxr/antenna_speed_dps", 0)
-- Define frame time property
frame_time = globalPropertyf("tu154b2/custom/time/frame_time")
delay_timer = 0

local wxr_returns = nil
local dt = 0
local sweep_direction = 1

function update()
    dt = dt + 0.016
    if dt > 1 then
        dt = 0
    end

    -- Animate sweep angle from -100 to 100 with smooth slowdown near edges
    local sweep_speed_max = 80 -- maximum degrees per second at center
    local current_sweep = get(antenna_sweep)
    local delta_time = get(frame_time)
    local velocity = 0

    -- Initialize delay timer if needed
    if delay_timer == nil then
        delay_timer = 0
    end

    -- If we're in a pause at the edge, count down and hold the edge position
    if delay_timer > 0 then
        delay_timer = delay_timer - delta_time
        if sweep_direction == -1 then
            current_sweep = 100
        else
            current_sweep = -100
        end
        velocity = 0
    else
        -- Smooth speed: fast in center, slows toward edges using a quadratic falloff
        local norm = current_sweep / 115
        if norm > 1 then norm = 1 elseif norm < -1 then norm = -1 end
        local slowdown_factor = 1 - (norm * norm) -- 1.0 at center, 0.0 at edges
        velocity = sweep_speed_max * slowdown_factor

        -- Compute next sweep position
        local next_sweep = current_sweep + (velocity * delta_time * sweep_direction)

        -- If we would cross the edge, snap to edge, start delay, and reverse
        if sweep_direction == 1 and next_sweep >= 100 then
            current_sweep = 100
            delay_timer = 0.2
            sweep_direction = -1
        elseif sweep_direction == -1 and next_sweep <= -100 then
            current_sweep = -100
            delay_timer = 0.2
            sweep_direction = 1
        else
            current_sweep = next_sweep
        end
    end

    set(antenna_sweep, current_sweep)
    set(antenna_speed_dps, velocity)

    --region FIRST PASS
    ----------------------------------------------------------------------------------------
    --
    -- FIRST PASS
    -- Base Radar and sweep
    ----------------------------------------------------------------------------------------
    sasl.gl.setRenderTarget(radar_composite_tex)
    -- render pass 1 - radar returns
    sasl.gl.useShaderProgram(radar_shader)
    sasl.gl.setShaderUniform(radar_shader, "u_returns", TYPE_SAMPLER, wxr_returns, 0)
    -- Sweep reveal uniforms
    sasl.gl.setShaderUniform(radar_shader, "kViewportSize", TYPE_FLOAT_ARRAY, size)
    sasl.gl.setShaderUniform(radar_shader, "u_sweepAngleDeg", TYPE_FLOAT, current_sweep)
    sasl.gl.setShaderUniform(radar_shader, "u_beamWidthDeg", TYPE_FLOAT, 4.0) -- tweak beam width
    sasl.gl.setShaderUniform(radar_shader, "u_uvYOffset", TYPE_FLOAT, 0.15)
    sasl.gl.setShaderUniform(radar_shader, "u_sweepDirection", TYPE_FLOAT, sweep_direction)

    sasl.gl.drawRectangle(0, 230, size[1], size[2], { 1, 1, 1, 1 })
    sasl.gl.stopShaderProgram(radar_shader)

    --sasl.gl.setBlendEquation(BLEND_EQUATION_ADD)

    -- radar sweep
    sasl.gl.useShaderProgram(groza_sweep_shader)
    sasl.gl.setShaderUniform(groza_sweep_shader, "time", TYPE_FLOAT, dt)
    --sasl.gl.setShaderUniform(groza_sweep_shader, "beam_angle", TYPE_FLOAT, current_sweep)

    local sweep_angle = get(antenna_sweep)
    local center_x = 1024
    local center_y = 100
    local radius = 1050
    local end_x = center_x + math.cos(-math.rad(sweep_angle - 90)) * radius
    local end_y = center_y + math.sin(-math.rad(sweep_angle - 90)) * radius
    sasl.gl.saveGraphicsContext()
    sasl.gl.setTranslateTransform(1024, 230)
    sasl.gl.setRotateTransform(sweep_angle)

    local beam_offset = 0.0

    if sweep_direction == 1 then
        beam_offset = 12
    elseif sweep_direction == -1 then
        beam_offset = -12
    end

    --sasl.gl.drawRectangle(-10 + beam_offset, 0, 20, 1050, { 1, 1, 1, 1 })
    -- -- Beam geometry (fan-shaped)
    local beam_half_angle = 6.0 -- degrees, controls beam width

    -- Convert half-angle to radians
    local half_rad = math.rad(beam_half_angle)

    -- Define beam triangle vertices
    local x1, y1 = 0, 0
    local x2, y2 = 0, 0
    local x3, y3 = 0, 0
    if sweep_direction == -1 then
        x2, y2 = math.sin(-half_rad + half_rad) * radius, math.cos(-half_rad + half_rad) * radius
        x3, y3 = math.sin(half_rad + half_rad) * radius, math.cos(half_rad + half_rad) * radius
    elseif sweep_direction == 1 then
        x2, y2 = math.sin(-half_rad - half_rad) * radius, math.cos(-half_rad - half_rad) * radius
        x3, y3 = math.sin(half_rad - half_rad) * radius, math.cos(half_rad - half_rad) * radius
    end

    -- Draw expanding triangular beam
    sasl.gl.drawTriangle(x1, y1, x2, y2, x3, y3, { 1, 1, 1, 1 })

    --sasl.gl.drawLine(center_x, center_y, end_x, end_y, { 0, 1, 0, 1 })
    sasl.gl.restoreGraphicsContext()
    sasl.gl.stopShaderProgram(groza_sweep_shader)

    sasl.gl.restoreRenderTarget()
    --endregion
    --
    ----------------------------------------------------------------------------------------
    --
    -- SECOND AND THIRD PASS
    -- Bloom
    ----------------------------------------------------------------------------------------
    -- radar bloom

    sasl.gl.setRenderTarget(radar_bloom_pass1)
    sasl.gl.useShaderProgram(groza_bloom_shader)
    sasl.gl.setShaderUniform(groza_bloom_shader, "render_target", TYPE_SAMPLER, radar_composite_tex, 0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "dirx", TYPE_FLOAT, 1.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "diry", TYPE_FLOAT, 0.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "intensity", TYPE_FLOAT, 1.5)
    sasl.gl.drawRectangle(0, 0, size[1], size[2], { 1, 1, 1, 1 })
    sasl.gl.stopShaderProgram(groza_bloom_shader)
    sasl.gl.restoreRenderTarget()

    sasl.gl.setRenderTarget(radar_bloom_pass2)
    sasl.gl.useShaderProgram(groza_bloom_shader)
    sasl.gl.setShaderUniform(groza_bloom_shader, "render_target", TYPE_SAMPLER, radar_bloom_pass1, 0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "dirx", TYPE_FLOAT, 0.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "diry", TYPE_FLOAT, 1.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "intensity", TYPE_FLOAT, 1.5)
    sasl.gl.drawRectangle(0, 0, size[1], size[2], { 1, 1, 1, 1 })
    sasl.gl.stopShaderProgram(groza_bloom_shader)
    sasl.gl.restoreRenderTarget()
    --
    --sasl.gl.useShaderProgram(groza_bloom_shader)
    --sasl.gl.setShaderUniform(groza_bloom_shader, "render_target", TYPE_SAMPLER, radar_composite_tex, 0)
    --sasl.gl.setShaderUniform(groza_bloom_shader, "dir", TYPE_FLOAT_ARRAY, { 0.0, 1.0 })
    --sasl.gl.drawRectangle(0, 0, 2048, 2048, { 1, 1, 1, 1 })
    --sasl.gl.stopShaderProgram(groza_bloom_shader)
    --
    --
    --
    -- Pick previous and destination ping-pong targets
    --



    sasl.gl.setRenderTarget(radar_beam_tex)
    sasl.gl.useShaderProgram(groza_sweep2_shader)
    sasl.gl.setShaderUniform(groza_sweep2_shader, "time", TYPE_FLOAT, dt)
    sasl.gl.saveGraphicsContext()
    sasl.gl.setTranslateTransform(1024, 230)
    sasl.gl.setRotateTransform(sweep_angle)
    sasl.gl.drawRectangle(-10, 0, 20, 1042, { 1, 1, 1, 1 })
    --sasl.gl.drawLine(center_x, center_y, end_x, end_y, { 0, 1, 0, 1 })
    sasl.gl.restoreGraphicsContext()
    sasl.gl.stopShaderProgram(groza_sweep2_shader)
    sasl.gl.restoreRenderTarget()

    -- radar beam bloom
    sasl.gl.setRenderTarget(radar_beam_bloom1)
    sasl.gl.useShaderProgram(groza_bloom_shader)
    sasl.gl.setShaderUniform(groza_bloom_shader, "render_target", TYPE_SAMPLER, radar_beam_tex, 0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "dirx", TYPE_FLOAT, 1.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "diry", TYPE_FLOAT, 0.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "intensity", TYPE_FLOAT, 4.0)
    sasl.gl.drawRectangle(0, 0, size[1], size[2], { 1, 1, 1, 1 })
    sasl.gl.stopShaderProgram(groza_bloom_shader)
    sasl.gl.restoreRenderTarget()

    sasl.gl.setRenderTarget(radar_beam_bloom2)
    sasl.gl.useShaderProgram(groza_bloom_shader)
    sasl.gl.setShaderUniform(groza_bloom_shader, "render_target", TYPE_SAMPLER, radar_beam_bloom1, 0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "intensity", TYPE_FLOAT, 4.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "dirx", TYPE_FLOAT, 0.0)
    sasl.gl.setShaderUniform(groza_bloom_shader, "diry", TYPE_FLOAT, 1.0)
    sasl.gl.drawRectangle(0, 0, size[1], size[2], { 1, 1, 1, 1 })
    sasl.gl.stopShaderProgram(groza_bloom_shader)
    sasl.gl.restoreRenderTarget()


    --sasl.gl.setBlendFunction(1, 0)




    --sasl.gl.resetBlending()
end

function onModuleInit()
    wxr_returns = sasl.gl.importXPTexture(AIRCRAFT_WXR_PILOT_TEX)
end

function draw()
    local prev_tex = use_prev_a and previous_frame_a or previous_frame_b
    dst_prev = use_prev_a and previous_frame_b or previous_frame_a

    -- 1) Render postprocessing + persistence INTO the destination previous-frame buffer
    --

    sasl.gl.setRenderTarget(dst_prev)
    sasl.gl.useShaderProgram(groza_pers_shader)
    sasl.gl.setShaderUniform(groza_pers_shader, "render_target", TYPE_SAMPLER, radar_bloom_pass2, 0)
    sasl.gl.setShaderUniform(groza_pers_shader, "u_prev", TYPE_SAMPLER, prev_tex, 1)
    --sasl.gl.setShaderUniform(groza_pers_shader, "u_persistence", TYPE_FLOAT, 12.22)
    sasl.gl.setShaderUniform(groza_pers_shader, "u_decay", TYPE_FLOAT, 0.50012)
    sasl.gl.drawRectangle(0, 0, size[1], size[2], { 1, 1, 1, 1 })
    sasl.gl.stopShaderProgram(groza_pers_shader)
    sasl.gl.restoreRenderTarget()

    sasl.gl.setRenderTarget(final_composite)

    sasl.gl.drawTexture(dst_prev, 0, 0, size[1], size[2], { 1, 1, 1, 1 })
    --sasl.gl.setBlendEquation(BLEND_EQUATION_MAX)
    sasl.gl.drawTexture(radar_beam_bloom2, 0, 0, size[1], size[2], { 0.7, 1, 0.4, 1 })
    sasl.gl.restoreRenderTarget()


    use_prev_a = not use_prev_a

    sasl.gl.setBlendFunction(BLEND_SOURCE_ALPHA, 1)
    sasl.gl.setBlendEquation(BLEND_EQUATION_ADD)
    sasl.gl.drawTexture(final_composite, 0, 0, size[1], size[2], { 2, 2, 2, 2 })
    sasl.gl.resetBlending()

    --
    --
    --sasl.gl.drawTexture(wxr_returns, 0, 230, 2048, 1504, { 1, 1, 1, 1.0 })


    -- 3) Overlay reticle (don’t bake it into persistence)
    --sasl.gl.setBlendEquation(BLEND_SOURCE_ALPHA)
    --if sasl.gl.isLitStage() then
    --    sasl.gl.drawTexture(radar_reticle, 0, 100, 2048, 1300, { 0.02, 0.02, 0.02, 0.2 })
    --end

    -- 4) Swap ping-pong buffers so next frame reads what we just rendered
end
