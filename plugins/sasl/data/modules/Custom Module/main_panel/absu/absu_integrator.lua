-- this script provides the integrals of delta M, delta V and delta H



-- SVS
defineProperty("mach_svs", globalPropertyf("tu154b2/custom/svs/machno")) -- Mach number
defineProperty("alt_svs", globalPropertyf("sim/flightmodel2/position/pressure_altitude")) -- Altitude by 1013 hpa
defineProperty("tas_svs", globalPropertyf("tu154b2/custom/svs/true_airspeed")) -- TAS

defineProperty("ias", globalPropertyf("sim/cockpit2/gauges/indicators/airspeed_kts_pilot")) -- indicated airspeed in KTS
defineProperty("pitch_sub_mode", globalPropertyi("tu154b2/custom/absu/pitch_sub_mode"))
defineProperty("frame_time", globalPropertyf("tu154b2/custom/time/frame_time")) -- time of frame

defineProperty("h_integral", globalPropertyf("tu154b2/custom/absu/d_H_integral")) 
defineProperty("v_integral", globalPropertyf("tu154b2/custom/absu/d_V_integral")) 
defineProperty("m_integral", globalPropertyf("tu154b2/custom/absu/d_M_integral")) 



local H_stab=0
local V_stab=0
local M_stab=0
-- local int_step=0

-- local int_h = {}
-- local int_v = {}
-- local int_m = {}

local integ_h = 0
local integ_v = 0
local integ_m = 0

local V_smth = 0
local M_smth = 0	

local v_lim=1000
local h_lim=2000
local m_lim=1

local pitch_submode_prev=0

-- for i= 1, 600 do
   -- int_h[i] = 0
-- end

-- for i= 1, 300 do
   -- int_v[i] = 0
   -- int_m[i] = 0
-- end

function update()
	local pitch_submode = get(pitch_sub_mode)
	local passed = get(frame_time)
	local airspeed = get(ias) * 1.852
	local mach = get(mach_svs)
	local alt = get(alt_svs)*0.3048
	
	if pitch_submode==2 then
			
			
		--V
		V_smth = V_smth + (airspeed - V_smth) * passed * 1
		
		local P_V = V_smth - V_stab
		--int_step=int_step+passed
		-- moving integral (30s window, 0.1s timestep)
		--if int_step>0.1 then
			-- for i= 1, 299 do
			   -- int_v[i] = int_v[i+1]
			-- end
			-- int_v[300]=P_V*0.1
			-- int_step=0
			-- integ_v=0
			-- for i= 1, 300 do
			integ_v =integ_v+P_V* passed
			if integ_v>v_lim then
				integ_v=v_lim
			elseif integ_v<-v_lim then
				integ_v=-v_lim
			end
				
			--end
			
		--end	
		M_stab = mach
		M_smth = M_stab		
		H_stab = alt
		-- if integ_m~=0 then
			-- for i= 1, 300 do
			   -- int_m[i] = 0
			-- end
		integ_m=0
		--end
		-- if integ_h~=0 then
			-- for i= 1, 600 do
			   -- int_h[i] = 0
			-- end
		integ_h=0
		--end
		--set(db1,integ_v)
	elseif pitch_submode==3 then		
			

		-- Mach
		M_smth = M_smth + (mach - M_smth) * passed * 1
		
		local P_M = M_smth - M_stab
		
		-- int_step=int_step+passed
		-- -- moving integral (30s window, 0.1s timestep)
		-- if int_step>0.1 then
			-- for i= 1, 299 do
			   -- int_m[i] = int_m[i+1]
			-- end
			-- int_m[300]=P_M*0.1
			-- int_step=0
			-- integ_m=0
			-- for i= 1, 300 do
				-- integ_m =integ_m+int_m[i]
			-- end
			
		-- end	
		integ_m =integ_m+P_M* passed
		if integ_m>m_lim then
			integ_m=m_lim
		elseif integ_m<-m_lim then
			integ_m=-m_lim
		end
		
		V_stab = airspeed
		V_smth = V_stab
		-- if integ_h~=0 then
			-- for i= 1, 600 do
			   -- int_h[i] = 0
			-- end
			integ_h=0
		-- end
		-- if integ_v~=0 then
			-- for i= 1, 300 do
			   -- int_v[i] = 0
			-- end
			integ_v=0
		-- end
		H_stab = alt	
			
	elseif pitch_submode==4 then				
		
		-- H
		local P_H = alt - H_stab
		--int_step=int_step+passed
		-- moving integral (60s window, 0.1s timestep)
		-- if int_step>0.1 then
			-- for i= 1, 599 do
			   -- int_h[i] = int_h[i+1]
			-- end
			-- int_h[600]=P_H*0.1
			-- int_step=0
			-- integ_h=0
			-- for i= 1, 600 do
				-- integ_h =integ_h+int_h[i]
			-- end
		-- end	
		integ_h =integ_h+P_H* passed
		if integ_h>h_lim then
			integ_h=h_lim
		elseif integ_h<-h_lim then
			integ_h=-h_lim
		end
		
		V_stab = airspeed
		V_smth = V_stab
		-- if integ_m~=0 then
			-- for i= 1, 300 do
			   -- int_m[i] = 0
			-- end
			integ_m=0
		-- end
		-- if integ_v~=0 then
			-- for i= 1, 300 do
			   -- int_v[i] = 0
			-- end
			integ_v=0
		-- end
		M_stab = mach
		M_smth = M_stab
	
	else
		
		V_stab = airspeed
		V_smth = V_stab
		
		M_stab = mach
		M_smth = M_stab
		
		H_stab = alt			
		-- int_step=0
		-- if integ_m~=0 then
			-- for i= 1, 300 do
			   -- int_m[i] = 0
			-- end
			integ_m=0
		-- end
		-- if integ_v~=0 then
			-- for i= 1, 300 do
			   -- int_v[i] = 0
			-- end
			integ_v=0
		-- end
		-- if integ_h~=0 then
			-- for i= 1, 600 do
			   -- int_h[i] = 0
			-- end
			integ_h=0
		-- end
	
	end
	pitch_submode_prev=pitch_submode
	set(h_integral,integ_h)	
	set(v_integral,integ_v)	
	set(m_integral,integ_m)	
end


