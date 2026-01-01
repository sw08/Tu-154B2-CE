# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a highly detailed X-Plane 12 aircraft addon for the Soviet Tupolev Tu-154B2 three-engine airliner. The project uses a plugin-based architecture with Lua scripting for systems simulation.

## Architecture

### Core Plugin Structure

The project uses multiple frameworks at once:
SASL, Scriptable Aviation Simulation Library by 1sim
XTLua, simple Lua framework with some multithreading by MSparks

```
plugins/
├── sasl/                    # SASL 3.20.1 - Main scripting framework
│   └── data/modules/Custom Module/  # All Tu-154 custom Lua modules
├── xtlua/                   # Additional Lua code based on MSparks's XTLua framework
│   └── init/scripts/T154.*/ # System-specific scripts
├── KLN90B/                  # Bendix King KLN90B GPS Navigator
└── kontur_fp_transfer/      # Flight plan data transfer
```

### SASL Codebase (`plugins/sasl/data/modules/Custom Module/`)

Organized by aircraft system:
- `engines_system/` - Engine management, fuel consumption, thrust
- `fuel_system/` - Fuel tanks, pumps, distribution
- `hydro_system/` - Hydraulic systems
- `electric_system/` - Electrical generation and distribution
- `fire_system/` - Fire detection and suppression
- `apu_system/` - Auxiliary Power Unit
- `controls/` - Flight control systems
- `main_panel/` - Instrument subsystems:
  - `nvu/` - Doppler navigation system with moving map
  - `radar/` - Weather radar
  - `rsbn/` - Russian RSBN navigation
  - `absu/` - AFCS, automatic flight control system
  - `taws/`, `tcas/` - Safety systems

### Key Files

- `tu154.acf` - Master aircraft definition (aerodynamics, weight, flight model)
- `smartcopilot.cfg` - SmartCopilot plugin config with 100+ custom dataref definitions
- `panels.txt` - 2D panel position definitions (Lua table format)
- `AviTab.json` - Tablet integration geometry

### DataRef Naming

```
tu154b2/custom/system/subsystem/name    # Tu-154 specific
sim/custom/system/name                   # X-Plane convention
```

## Documentation

SASL documentation is available as PDF file at:
https://1-sim.com/files/SASL3Manual.pdf

All simulator datarefs are documented here:
https://developer.x-plane.com/datarefs/

## Development Workflow

### Reloading Changes

Lua script changes take effect after reload: **In X-Plane menu: Tu-154 -> Reload all custom**

### Testing

1. Launch X-Plane with Tu-154 addon
2. Make code changes to Lua files
3. Open SASL developer widget: Plugins -> Tu154B2 (SASL) -> Show Widget
4. Reload via Reboot button in the widget
5. Check `plugins/sasl/data/output/SASLLog.txt` for SASL-specific logs

### Lua Module Pattern (SASL)

```lua
components = {
    subsystem_ui {},
    subsystem_logic {},
    subsystem_failures {},
}
```

### Global Utility Functions (`functions.lua`)

- `interpolate(tbl, value)` - Interpolate from lookup table
- `map(value, x1, x2, y1, y2)` - Linear value remapping
- `line(x, x1, y1, x2, y2)` - Line equation solver
- `bool2int(var)` - Convert boolean to 0/1

## Asset Locations

- **3D Models**: `objects/*.obj` - Cockpit, fuselage, wings, engines, landing gear
- **Textures**: `objects/*.png` - `*_LIT.png` (illuminated), `*_NML.png` (normal maps), `*_RUS.png` (Russian text)
- **Cockpit Displays**: `cockpit_3d/generic/` - CRT displays, EFIS, TCAS, navigation systems
- **Airfoils**: `airfoils/*.afl` - Aerodynamic profiles for wings and stabilizers
- **Liveries**: `liveries/*/` - Each contains `tu154_icon11.png`, `T154_config.dat`, `saved_state.ini`
- **Documentation**: `docs/*.pdf` - Russian technical manuals

## Creating a New Livery

1. Copy existing livery folder: `liveries/85554/` → `liveries/new_reg/`
2. Replace `tu154_icon11.png` and `tu154_icon11_thumb.png`
3. Update `T154_config.dat` with new livery name
