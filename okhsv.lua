--Implements OKHSV conversions
--Adapted from https://bottosson.github.io/posts/colorpicker/, which was licensed under MIT:
--
--Copyright (c) 2021 Björn Ottosson
--
--Permission is hereby granted, free of charge, to any person obtaining a copy of
--this software and associated documentation files (the "Software"), to deal in
--the Software without restriction, including without limitation the rights to
--use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
--of the Software, and to permit persons to whom the Software is furnished to do
--so, subject to the following conditions:
--
--The above copyright notice and this permission notice shall be included in all
--copies or substantial portions of the Software.
--
--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--SOFTWARE.
local colours = require("oklua.colours")

local lib = {}

---Finds the maximum saturation possible for a given hue that fits in sRGB  
---Saturation here is defined as S = C/L  
---a and b must be normalized so a^2 + b^2 == 1
---@param a number
---@param b number
---@return number
local function compute_max_saturation(a, b)
    -- Max saturation will be when one of r, g or b goes below zero.

    -- Select different coefficients depending on which component goes below zero first
    local k0, k1, k2, k3, k4, wl, wm, ws

    if (-1.88170328 * a - 0.80936493 * b > 1) then
        -- Red component
        k0 = 1.19086277
        k1 = 1.76576728
        k2 = 0.59662641
        k3 = 0.75515197
        k4 = 0.56771245
        wl = 4.0767416621
        wm = -3.3077115913
        ws = 0.2309699292
    elseif (1.81444104 * a - 1.19445276 * b > 1) then
        -- Green component
        k0 = 0.73956515
        k1 = -0.45954404
        k2 = 0.08285427
        k3 = 0.12541070
        k4 = 0.14503204
        wl = -1.2684380046
        wm = 2.6097574011
        ws = -0.3413193965
    else
        -- Blue component
        k0 = 1.35733652
        k1 = -0.00915799
        k2 = -1.15130210
        k3 = -0.50559606
        k4 = 0.00692167
        wl = -0.0041960863
        wm = -0.7034186147
        ws = 1.7076147010
    end

    -- Approximate max saturation using a polynomial:
    local S = k0 + k1 * a + k2 * b + k3 * a * a + k4 * a * b

    -- Do one step Halley's method to get closer
    -- this gives an error less than 10e6, except for some blue hues where the dS/dh is close to infinite
    -- this should be sufficient for most applications, otherwise do two/three steps 

    local k_l =  0.3963377774 * a + 0.2158037573 * b
    local k_m = -0.1055613458 * a - 0.0638541728 * b
    local k_s = -0.0894841775 * a - 1.2914855480 * b

    local l_ = 1 + S * k_l
    local m_ = 1 + S * k_m
    local s_ = 1 + S * k_s

    local l = l_ * l_ * l_
    local m = m_ * m_ * m_
    local s = s_ * s_ * s_

    local l_dS = 3 * k_l * l_ * l_
    local m_dS = 3 * k_m * m_ * m_
    local s_dS = 3 * k_s * s_ * s_

    local l_dS2 = 6 * k_l * k_l * l_
    local m_dS2 = 6 * k_m * k_m * m_
    local s_dS2 = 6 * k_s * k_s * s_

    local f  = wl * l     + wm * m     + ws * s
    local f1 = wl * l_dS  + wm * m_dS  + ws * s_dS
    local f2 = wl * l_dS2 + wm * m_dS2 + ws * s_dS2

    S = S - f * f1 / (f1*f1 - 0.5 * f * f2)

    return S
end

---finds L_cusp and C_cusp for a given hue  
---a and b must be normalized so a^2 + b^2 == 1
---@param a number
---@param b number
---@return Vector2
local function find_cusp(a, b)
    -- First, find the maximum saturation (saturation S = C/L)
	local S_cusp = compute_max_saturation(a, b)

	-- Convert to linear sRGB to find the first point where at least one of r,g or b >= 1:
	local rgb_at_max = colours.oklabToLinear(vec( 1, S_cusp * a, S_cusp * b ))
	local L_cusp = math.pow(1 / math.max(rgb_at_max.r, rgb_at_max.g, rgb_at_max.b), 1/3)
	local C_cusp = L_cusp * S_cusp

	return vec(L_cusp , C_cusp)
end

---@param x number
---@return number
local function toe(x)
	local k_1 = 0.206
	local k_2 = 0.03
	local k_3 = (1 + k_1) / (1 + k_2)
	return 0.5 * (k_3 * x - k_1 + math.sqrt((k_3 * x - k_1) * (k_3 * x - k_1) + 4 * k_2 * k_3 * x))
end

---@param x number
---@return number
local function toe_inv(x)
	local k_1 = 0.206
	local k_2 = 0.03
	local k_3 = (1 + k_1) / (1 + k_2)
	return (x * x + k_1 * x) / (k_3 * (x + k_2))
end

---@param cusp Vector2
---@return Vector2
local function to_ST(cusp)
    local L = cusp.x
	local C = cusp.y
	return vec(C / L, C / (1 - L))
end

---Converts OKHSV to sRGB
---@param hsv Vector3
---@return Vector3
function lib.okhsv_to_srgb(hsv)
	local h = hsv.x
	local s = hsv.y
	local v = hsv.z

	local a_ = math.cos(2 * math.pi * h)
	local b_ = math.sin(2 * math.pi * h)
	
	local cusp = find_cusp(a_, b_)
	local ST_max = to_ST(cusp)
	local S_max = ST_max.x
	local T_max = ST_max.y
	local S_0 = 0.5
	local k = 1 - S_0 / S_max

	-- first we compute L and V as if the gamut is a perfect triangle:

	-- L, C when v==1:
	local L_v = 1     - s * S_0 / (S_0 + T_max - T_max * k * s)
	local C_v = s * T_max * S_0 / (S_0 + T_max - T_max * k * s)

	local L = v * L_v
	local C = v * C_v

	-- then we compensate for both toe and the curved top part of the triangle:
    local L_vt = toe_inv(L_v)
	local C_vt = C_v * L_vt / L_v

	local L_new = toe_inv(L)
	C = C * L_new / L
	L = L_new

	local rgb_scale = colours.oklabToLinear(vec(L_vt, a_ * C_vt, b_ * C_vt))
	local scale_L = math.pow(1 / math.max(rgb_scale.r, rgb_scale.g, rgb_scale.b, 0), 1/3)

	L = L * scale_L
	C = C * scale_L

	local rgb = colours.oklabToLinear(vec(L, C * a_, C * b_))
	return colours.linearToSrgb(rgb)
end

---Converts sRGB to OKHSV
---@param rgb Vector3
---@return Vector3
function lib.srgb_to_okhsv(rgb)
	local lab = colours.linearToOklab(colours.srgbToLinear(rgb))

	local C = math.sqrt(lab.y * lab.y + lab.z * lab.z)
	local a_ = lab.y / C
	local b_ = lab.z / C

	local L = lab.x
	local h = 0.5 + 0.5 * math.atan2(-lab.z, -lab.y) / math.pi

	local cusp = find_cusp(a_, b_)
	local ST_max = to_ST(cusp)
	local S_max = ST_max.x
	local T_max = ST_max.y
	local S_0 = 0.5
	local k = 1 - S_0 / S_max

	-- first we find L_v, C_v, L_vt and C_vt

	local t = T_max / (C + L * T_max)
	local L_v = t * L
	local C_v = t * C

	local L_vt = toe_inv(L_v)
	local C_vt = C_v * L_vt / L_v

	-- we can then use these to invert the step that compensates for the toe and the curved top part of the triangle:
	local rgb_scale = colours.oklabToLinear(vec(L_vt, a_ * C_vt, b_ * C_vt))
	local scale_L = math.pow(1 / math.max(rgb_scale.r, rgb_scale.g, rgb_scale.b, 0), 1/3)

	L = L / scale_L
	C = C / scale_L

	C = C * toe(L) / L
	L = toe(L)

	-- we can now compute v and s:

	local v = L / L_v
	local s = (S_0 + T_max) * C_v / ((T_max * S_0) + T_max * k * C_v)

	return vec(h, s, v)
end

lib.hsvToRGB = lib.okhsv_to_srgb
lib.rgbToHSV = lib.srgb_to_okhsv

return lib