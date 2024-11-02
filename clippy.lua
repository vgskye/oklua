--Implements gamut clipping with adaptive L0​​ with α=0.05 and L0=0.5
--Adapted from https://bottosson.github.io/posts/gamutclipping/, which was licensed under MIT:
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
    local S = k0 + k1 * a + k2 * b + k3 * a * a + k4 * a * b;

    -- Do one step Halley's method to get closer
    -- this gives an error less than 10e6, except for some blue hues where the dS/dh is close to infinite
    -- this should be sufficient for most applications, otherwise do two/three steps 

    local k_l =  0.3963377774 * a + 0.2158037573 * b;
    local k_m = -0.1055613458 * a - 0.0638541728 * b;
    local k_s = -0.0894841775 * a - 1.2914855480 * b;

    local l_ = 1 + S * k_l;
    local m_ = 1 + S * k_m;
    local s_ = 1 + S * k_s;

    local l = l_ * l_ * l_;
    local m = m_ * m_ * m_;
    local s = s_ * s_ * s_;

    local l_dS = 3 * k_l * l_ * l_;
    local m_dS = 3 * k_m * m_ * m_;
    local s_dS = 3 * k_s * s_ * s_;

    local l_dS2 = 6 * k_l * k_l * l_;
    local m_dS2 = 6 * k_m * k_m * m_;
    local s_dS2 = 6 * k_s * k_s * s_;

    local f  = wl * l     + wm * m     + ws * s;
    local f1 = wl * l_dS  + wm * m_dS  + ws * s_dS;
    local f2 = wl * l_dS2 + wm * m_dS2 + ws * s_dS2;

    S = S - f * f1 / (f1*f1 - 0.5 * f * f2);

    return S
end

---finds L_cusp and C_cusp for a given hue  
---a and b must be normalized so a^2 + b^2 == 1
---@param a number
---@param b number
---@return Vector2
local function find_cusp(a, b)
    -- First, find the maximum saturation (saturation S = C/L)
	local S_cusp = compute_max_saturation(a, b);

	-- Convert to linear sRGB to find the first point where at least one of r,g or b >= 1:
	local rgb_at_max = colours.oklabToLinear(vec( 1, S_cusp * a, S_cusp * b ));
	local L_cusp = math.pow(1 / math.max(rgb_at_max.r, rgb_at_max.g, rgb_at_max.b), 1/3);
	local C_cusp = L_cusp * S_cusp;

	return vec(L_cusp , C_cusp)
end

---Finds intersection of the line defined by   
---L = L0 * (1 - t) + t * L1;  
---C = t * C1;  
---a and b must be normalized so a^2 + b^2 == 1
---@param a number
---@param b number
---@param L1 number
---@param C1 number
---@param L0 number
---@return number
local function find_gamut_intersection(a, b, L1, C1, L0)
	-- Find the cusp of the gamut triangle
	local cusp = find_cusp(a, b)

	-- Find the intersection for upper and lower half seprately
	local t
	if (((L1 - L0) * cusp.y - (cusp.x - L0) * C1) <= 0) then
		-- Lower half

		t = cusp.y * L0 / (C1 * cusp.x + cusp.y * (L0 - L1));
	else
		-- Upper half

		-- First intersect with triangle
		t = cusp.y * (L0 - 1) / (C1 * (cusp.x - 1) + cusp.y * (L0 - L1));

		-- Then one step Halley's method
        local dL = L1 - L0;
        local dC = C1;

        local k_l = 0.3963377774 * a + 0.2158037573 * b;
        local k_m = -0.1055613458 * a - 0.0638541728 * b;
        local k_s = -0.0894841775 * a - 1.2914855480 * b;

        local l_dt = dL + dC * k_l;
        local m_dt = dL + dC * k_m;
        local s_dt = dL + dC * k_s;

        
        -- If higher accuracy is required, 2 or 3 iterations of the following block can be used:
        local L = L0 * (1 - t) + t * L1;
        local C = t * C1;

        local l_ = L + C * k_l;
        local m_ = L + C * k_m;
        local s_ = L + C * k_s;

        local l = l_ * l_ * l_;
        local m = m_ * m_ * m_;
        local s = s_ * s_ * s_;

        local ldt = 3 * l_dt * l_ * l_;
        local mdt = 3 * m_dt * m_ * m_;
        local sdt = 3 * s_dt * s_ * s_;

        local ldt2 = 6 * l_dt * l_dt * l_;
        local mdt2 = 6 * m_dt * m_dt * m_;
        local sdt2 = 6 * s_dt * s_dt * s_;

        local r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s - 1;
        local r1 = 4.0767416621 * ldt - 3.3077115913 * mdt + 0.2309699292 * sdt;
        local r2 = 4.0767416621 * ldt2 - 3.3077115913 * mdt2 + 0.2309699292 * sdt2;

        local u_r = r1 / (r1 * r1 - 0.5 * r * r2);
        local t_r = -r * u_r;

        local g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s - 1;
        local g1 = -1.2684380046 * ldt + 2.6097574011 * mdt - 0.3413193965 * sdt;
        local g2 = -1.2684380046 * ldt2 + 2.6097574011 * mdt2 - 0.3413193965 * sdt2;

        local u_g = g1 / (g1 * g1 - 0.5 * g * g2);
        local t_g = -g * u_g;

        local b_ = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s - 1;
        local b1 = -0.0041960863 * ldt - 0.7034186147 * mdt + 1.7076147010 * sdt;
        local b2 = -0.0041960863 * ldt2 - 0.7034186147 * mdt2 + 1.7076147010 * sdt2;

        local u_b = b1 / (b1 * b1 - 0.5 * b_ * b2);
        local t_b = -b_ * u_b;

        t_r = u_r >= 0. and t_r or 1.7976931348623158e+308;
        t_g = u_g >= 0. and t_g or 1.7976931348623158e+308;
        t_b = u_b >= 0. and t_b or 1.7976931348623158e+308;

        t = t + math.min(t_r, t_g, t_b);
	end

	return t;
end

---Clips a OKLAB colour to be in gamut
---@param colour Vector3
---@return Vector3
function lib.clipOklab(colour)
    local L = colour.x;
    local eps = 0.00001;
    local C = math.max(eps, math.sqrt(colour.y * colour.y + colour.z * colour.z));
    local a_ = colour.y / C;
    local b_ = colour.z / C;

    local Ld = L - 0.5;
    local e1 = 0.5 + math.abs(Ld) + 0.05 * C;
    local L0 = 0.5*(1 + math.sign(Ld) * (e1 - math.sqrt(e1 * e1 - 2 * math.abs(Ld))));

    local t = find_gamut_intersection(a_, b_, L, C, L0);
    local L_clipped = L0 * (1 - t) + t * L;
    local C_clipped = t * C;

    return vec(L_clipped, C_clipped * a_, C_clipped * b_);
end

---Clips a Linear sRGB colour to be in gamut
---@param colour Vector3
---@return Vector3
function lib.clipLinear(colour)
    if colour.r < 1 and colour.g < 1 and colour.b < 1 and colour.r > 0 and colour.g > 0 and colour.b > 0 then
        return colour
    end

    return colours.oklabToLinear(lib.clipOklab(colours.linearToOklab(colour)));
end

---Clips a sRGB colour to be in gamut
---@param colour Vector3
---@return Vector3
function lib.clipSrgb(colour)
    if colour.r < 1 and colour.g < 1 and colour.b < 1 and colour.r > 0 and colour.g > 0 and colour.b > 0 then
        return colour
    end

    return colours.linearToSrgb(lib.clipLinear(colours.srgbToLinear(colour)))
end

return lib