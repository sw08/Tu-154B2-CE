radar_power = createGlobalPropertyi("tu154b/custom/systems/radar/antenna_power", 1)
radar_mode = createGlobalPropertyf("tu154b/custom/systems/radar/mode", 0)
radar_range = createGlobalPropertyf("tu154b/custom/systems/radar/range", 0)
azimuth_commanded = createGlobalPropertyf("tu154b/custom/systems/radar/antenna_commanded_azimuth", 0)
tilt_commanded = createGlobalPropertyf("tu154b/custom/systems/radar/antenna_commanded_elevation", 0)


radar_symbol_brightness = createGlobalPropertyf("tu154b/custom/systems/radar/symbrt", 1)

-- Antenna position (driven by antenna_logic.lua)
antenna_azimuth = createGlobalPropertyf("tu154b2/custom/systems/radar/antenna_azimuth", 0)
antenna_elevation = createGlobalPropertyf("tu154b2/custom/systems/radar/antenna_elevation", 0)
antenna_speed_dps = createGlobalPropertyf("tu154b2/custom/systems/radar/antenna_speed_dps", 0)
antenna_velocity = createGlobalPropertyf("tu154b2/custom/systems/radar/antenna_velocity", 0)
scan_active = createGlobalPropertyi("tu154b2/custom/systems/radar/scan_active", 0)
frame_time = createGlobalPropertyf("tu154b2/custom/time/frame_time", 0)

radar_device = avionicsDevice({
    name = "Groza Weather Radar",
    id = "WEATHER_RADAR",
    size = { 2048, 2048 },
    drawOnDemand = false,
    screenClear = true,
    components = {
        antenna_logic {},
        radar_screen {}
    }
})
