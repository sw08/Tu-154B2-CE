--------------------------------------------------------------------------------
-- Groza-26 Weather Radar - Main Logic
--------------------------------------------------------------------------------

-- X-Plane datarefs
frame_time = globalPropertyf("tu154b2/custom/time/frame_time")

-- Radar control inputs (from cockpit panel)
--radar_power = globalPropertyi("tu154b/custom/systems/radar/antenna_power")
--radar_mode = globalPropertyf("tu154b/custom/systems/radar/mode")
--radar_range = globalPropertyf("tu154b/custom/systems/radar/range")
--azimuth_commanded = globalPropertyf("tu154b/custom/systems/radar/antenna_commanded_azimuth")
--tilt_commanded = globalPropertyf("tu154b/custom/systems/radar/antenna_commanded_elevation")

-- Electrical system (Groza-26 requires 27V DC, 115V AC, 36V AC)
bus27_volt = globalPropertyf("tu154b2/custom/elec/bus27_volt_left")
bus36_volt = globalPropertyf("tu154b2/custom/elec/bus36_volt_left")
bus115_volt = globalPropertyf("tu154b2/custom/elec/bus115_1_volt")

-- Failures
radar_fail = globalPropertyi("tu154b2/custom/failures/radar_fail")

-- Radar outputs (for rendering) - created as new global properties
antenna_azimuth = createGlobalPropertyf("tu154b2/custom/systems/radar/antenna_azimuth", 0)
antenna_elevation = createGlobalPropertyf("tu154b2/custom/systems/radar/antenna_elevation", 0)
antenna_speed_dps = createGlobalPropertyf("tu154b2/custom/systems/radar/antenna_speed_dps", 0)
antenna_velocity = createGlobalPropertyf("tu154b2/custom/systems/radar/antenna_velocity", 0)
scan_active = createGlobalPropertyi("tu154b2/custom/systems/radar/scan_active", 0)
warmup_progress = createGlobalPropertyf("tu154b2/custom/systems/radar/warmup_progress", 0)
stabilization_sw = createGlobalPropertyi("tu154b2/custom/systems/radar/stabilization_sw", 0)


-- X-Plane radar API drefs
gcs = globalPropertyi("sim/cockpit2/EFIS/EFIS_weather_gcs")

-- X-Plane radar control (actual returns calculation)
xp_radar_azimuth = globalPropertyf("sim/cockpit2/EFIS/EFIS_weather_pilot_angle")
xp_radar_tilt = globalPropertyf("sim/cockpit2/EFIS/EFIS_weather_tilt")
xp_radar_sector = globalPropertyf("sim/cockpit2/EFIS/EFIS_weather_sector_width")
xp_radar_stab = globalPropertyi("sim/cockpit2/EFIS/EFIS_weather_stab") -- X-Plane stabilization: 1=on, 0=off
xp_radar_range = globalPropertyi("sim/cockpit/switches/EFIS_map_range_selector", 0)

-- Power consumption
radar_cc = globalPropertyf("tu154b2/custom/radio/radar_cc")

local RADAR_DEBUG = true

--------------------------------------------------------------------------------
-- Constants - Groza-26 Specifications
--------------------------------------------------------------------------------
local GROZA_SPECS = {
    -- Scan sector (from aircraft structural axis)
    AZIMUTH_MIN = -100, -- degrees left
    AZIMUTH_MAX = 100,  -- degrees right

    -- Tilt limits (manual antenna tilt)
    TILT_UP = -10,  -- 10° up
    TILT_DOWN = 15, -- 15° down

    -- Antenna dynamics
    AZIMUTH_RATE_MAX = 90, -- degrees/second maximum slew rate
    TILT_RATE = 5,         -- degrees/second

    -- Timing
    --WARMUP_TIME = 240.0,    -- 4 minutes (3-5 minutes per spec, using 4)
    WARMUP_TIME = 2.0,      -- testing
    EDGE_PAUSE_TIME = 0.15, -- seconds pause at scan edges

    -- Power consumption (amps at 27V)
    CURRENT_STANDBY = 0.5,
    CURRENT_WARMUP = 2.5,
    CURRENT_SCAN = 4.0,
    CURRENT_TRANSMIT = 6.0, -- Additional when transmitting (9kW pulse power)

    -- Transmitter specs
    PULSE_POWER_KW = 9,   -- minimum 9 kilowatts
    FREQUENCY_MHZ = 9370, -- 9,370 MHz carrier
}

-- Operating modes (from radar.lua)
local MODES = {
    READY = 0,   -- Ready/Standby
    MAP = 1,     -- "Earth" - terrain mapping
    WEATHER = 2, -- "Weather" - storm detection
    TURB = 3,    -- Turbulence detection
    DRIFT = 4,   -- "Drift" - wind correction/drift angle measurement
}

--------------------------------------------------------------------------------
-- State variables
--------------------------------------------------------------------------------
local state = {
    -- Antenna physical state
    azimuth = 0,          -- Current azimuth angle (degrees)
    elevation = 0,        -- Current elevation/tilt angle (degrees)
    azimuth_velocity = 0, -- Current rotation speed (degrees/second)

    -- Scan pattern state
    scan_direction = 1,   -- 1 = right, -1 = left
    edge_pause_timer = 0, -- Timer for pause at scan edges

    -- System state
    mode = MODES.READY,
    warmup_timer = 0,
    power_available = false,
    failed = false,
    transmitting = false,
}

--------------------------------------------------------------------------------
-- Helper functions
--------------------------------------------------------------------------------

-- Check if adequate power is available (27V DC, 115V AC, 36V AC required)
local function checkPower()
    local bus27 = bus27_volt:get()
    local bus36 = bus36_volt:get()
    local bus115 = bus115_volt:get()

    return true

    --return bus27 > 24 and bus36 > 32 and bus115 > 110
end

-- Calculate power consumption based on current state
local function calculatePowerConsumption()
    if not state.power_available or state.failed then
        return 0
    end

    if state.mode == MODES.READY and state.warmup_timer <= 0 then
        return GROZA_SPECS.CURRENT_STANDBY
    elseif state.warmup_timer > 0 then
        return GROZA_SPECS.CURRENT_WARMUP
    else
        -- Active scanning
        local base = GROZA_SPECS.CURRENT_SCAN
        -- Add transmit power when actually scanning (9kW pulse power)
        if state.transmitting and math.abs(state.azimuth_velocity) > 1 then
            base = base + GROZA_SPECS.CURRENT_TRANSMIT
        end
        return base
    end
end

--------------------------------------------------------------------------------
-- Antenna azimuth control - servo to commanded position
--------------------------------------------------------------------------------

local function updateAzimuthServo(dt)
    -- Read commanded azimuth setpoint
    local commanded = azimuth_commanded:get()

    -- Clamp commanded position to physical limits
    commanded = math.max(GROZA_SPECS.AZIMUTH_MIN, math.min(GROZA_SPECS.AZIMUTH_MAX, commanded))

    -- Calculate error
    local error = commanded - state.azimuth

    -- Calculate target velocity based on error (simple proportional control with max rate limit)
    local target_velocity = 0
    if math.abs(error) > 0.4 then
        -- Proportional gain: higher error = faster movement, clamped to max rate
        local gain = 2.0 -- Proportional gain factor
        target_velocity = error * gain
        target_velocity = math.max(-GROZA_SPECS.AZIMUTH_RATE_MAX,
            math.min(GROZA_SPECS.AZIMUTH_RATE_MAX, target_velocity))
    end

    -- Smooth velocity changes (acceleration limiting)
    local ACCEL = 120 -- degrees/second²
    local velocity_error = target_velocity - state.azimuth_velocity
    local max_accel = ACCEL * dt

    if math.abs(velocity_error) <= max_accel then
        state.azimuth_velocity = target_velocity
    elseif velocity_error > 0 then
        state.azimuth_velocity = state.azimuth_velocity + max_accel
    else
        state.azimuth_velocity = state.azimuth_velocity - max_accel
    end

    -- Update position
    state.azimuth = state.azimuth + state.azimuth_velocity * dt

    -- Clamp to physical limits
    state.azimuth = math.max(GROZA_SPECS.AZIMUTH_MIN,
        math.min(GROZA_SPECS.AZIMUTH_MAX, state.azimuth))

    antenna_velocity:set(state.azimuth_velocity)
end

--------------------------------------------------------------------------------
-- Antenna elevation/tilt logic (X-Plane handles stabilization)
--------------------------------------------------------------------------------

local function updateElevation(dt)
    local commanded = tilt_commanded:get()

    -- Clamp to physical limits (10° up, 15° down)
    local target_elevation = math.max(GROZA_SPECS.TILT_UP,
        math.min(GROZA_SPECS.TILT_DOWN, commanded))

    -- Slew toward target
    local error = target_elevation - state.elevation
    local max_change = GROZA_SPECS.TILT_RATE * dt

    if math.abs(error) <= max_change then
        state.elevation = target_elevation
    elseif error > 0 then
        state.elevation = state.elevation + max_change
    else
        state.elevation = state.elevation - max_change
    end
end

--------------------------------------------------------------------------------
-- Automatic scan pattern generator (updates commanded azimuth)
--------------------------------------------------------------------------------

local function updateAutoScan(dt)
    local cmd_azimuth = azimuth_commanded:get()
    -- Only auto-scan when in active modes
    if state.mode == MODES.READY or not state.transmitting or state.warmup_timer > 0 then
        -- Park at center when not scanning
        cmd_azimuth = 0
        state.scan_direction = 1
        state.edge_pause_timer = 0
        return
    end

    -- If the antenna is very close to the commanded azimuth, reverse the command
    local CLOSE_THRESHOLD = 2.5 -- degrees
    if math.abs(state.azimuth - cmd_azimuth) <= CLOSE_THRESHOLD then
        -- Mirror the commanded azimuth about center (reverse scan)
        cmd_azimuth = -cmd_azimuth

        -- Ensure commanded stays within physical limits
        cmd_azimuth = math.max(GROZA_SPECS.AZIMUTH_MIN,
            math.min(GROZA_SPECS.AZIMUTH_MAX, cmd_azimuth))
    end

    azimuth_commanded:set(cmd_azimuth)
end

--------------------------------------------------------------------------------
-- Mode and power management
--------------------------------------------------------------------------------

local function updateSystemState(dt)
    -- Check failures
    state.failed = radar_fail:get() > 0
    if state.failed then
        state.mode = MODES.READY
        state.warmup_timer = 0
        state.transmitting = false
        return
    end

    -- Check power (Groza-26 requires 27V DC, 36V AC, 115V AC)
    state.power_available = checkPower()
    if not state.power_available then
        state.mode = MODES.READY
        state.warmup_timer = 0
        state.transmitting = false
        return
    end

    -- Read commanded mode
    local power_sw = radar_power:get()
    local mode_sel = radar_mode:get()

    if power_sw == 0 then
        state.mode = MODES.READY
        state.warmup_timer = 0
        state.transmitting = false
    else
        -- Warmup sequence (3-5 minutes, using 4 minutes)
        if state.warmup_timer > 0 then
            state.warmup_timer = state.warmup_timer - dt
            state.mode = MODES.READY
            state.transmitting = false
        else
            -- Operational modes
            if mode_sel == 0 then
                state.mode = MODES.READY
                state.transmitting = false
            elseif mode_sel == 1 then
                state.mode = MODES.MAP
                state.transmitting = true
            elseif mode_sel == 2 then
                state.mode = MODES.WEATHER
                state.transmitting = true
            elseif mode_sel == 3 then
                state.mode = MODES.TURB
                state.transmitting = true
            elseif mode_sel == 4 then
                state.mode = MODES.DRIFT
                state.transmitting = true
            else
                state.mode = MODES.READY
                state.transmitting = false
            end
        end
    end

    -- Trigger warmup on power-on
    if power_sw > 0 and state.warmup_timer <= 0 and not state.transmitting then
        -- Start warmup only if coming from powered-off state
        local prev_power = radar_power:get()
        if prev_power == 0 then
            state.warmup_timer = GROZA_SPECS.WARMUP_TIME
        end
    end
end

--------------------------------------------------------------------------------
-- X-Plane radar integration
--------------------------------------------------------------------------------

local function updateXPlaneRadar()
    -- Only provide data to X-Plane when actively scanning
    if state.mode == MODES.READY or not state.transmitting then
        return
    end

    -- Set X-Plane radar parameters
    --xp_radar_azimuth:set(state.azimuth)
    xp_radar_tilt:set(state.elevation)

    -- Fixed scan sector width (±100°)
    xp_radar_sector:set(200) -- Total sector width

    -- Sync stabilization state to X-Plane (X-Plane handles the actual stabilization)
    local stab_switch = stabilization_sw:get()
    xp_radar_stab:set(stab_switch)
end

--------------------------------------------------------------------------------
-- Main update function
--------------------------------------------------------------------------------

function update()
    local dt = frame_time:get()
    if dt <= 0 or dt > 0.1 then dt = 0.016 end -- Sanity check

    -- Update system state and power
    updateSystemState(dt)

    -- Update automatic scan pattern (updates commanded azimuth)
    updateAutoScan(dt)

    -- Servo antenna to commanded positions
    updateAzimuthServo(dt)
    updateElevation(dt)

    -- Update X-Plane radar
    updateXPlaneRadar()

    -- Set output properties
    antenna_azimuth:set(state.azimuth)
    antenna_elevation:set(state.elevation)
    antenna_speed_dps:set(math.abs(state.azimuth_velocity))

    -- Scan active only when transmitting and warmup complete
    local is_scanning = state.transmitting and state.warmup_timer <= 0
    scan_active:set(is_scanning and 1 or 0)

    -- Warmup progress (0 to 1)
    local warmup_pct = 0
    if GROZA_SPECS.WARMUP_TIME > 0 then
        warmup_pct = 1.0 - (state.warmup_timer / GROZA_SPECS.WARMUP_TIME)
    end
    warmup_progress:set(math.max(0, math.min(1, warmup_pct)))

    -- Update power consumption
    local current = calculatePowerConsumption()
    radar_cc:set(current)
    xp_radar_range:set(radar_range:get())
end

--------------------------------------------------------------------------------
-- Commands for cockpit controls
--------------------------------------------------------------------------------

-- Stabilization toggle (toggles X-Plane's radar stabilization via switch)
sasl.registerCommandHandler(
    sasl.createCommand("tu154b2/radar/stabilization_toggle", "Toggle radar stabilization"),
    0,
    function(phase)
        if phase == SASL_COMMAND_BEGIN then
            local current = stabilization_sw:get()
            stabilization_sw:set(1 - current) -- Toggle between 0 and 1
        end
    end
)

-- Tilt up/down
sasl.registerCommandHandler(
    sasl.createCommand("tu154b2/radar/tilt_up", "Radar tilt up"),
    0,
    function(phase)
        if phase == SASL_COMMAND_BEGIN then
            local current = tilt_commanded:get()
            tilt_commanded:set(math.max(GROZA_SPECS.TILT_UP, current - 1))
        end
    end
)

sasl.registerCommandHandler(
    sasl.createCommand("tu154b2/radar/tilt_down", "Radar tilt down"),
    0,
    function(phase)
        if phase == SASL_COMMAND_BEGIN then
            local current = tilt_commanded:get()
            tilt_commanded:set(math.min(GROZA_SPECS.TILT_DOWN, current + 1))
        end
    end
)
