local lib = {}

---@param x number
---@return number
local function fromLinear(x)
    if x >= 0.0031308 then
        return 1.055 * math.pow(x, 1.0/2.4) - 0.055
    else
        return 12.92 * x
    end
end

---@param x number
---@return number
local function toLinear(x)
    if x >= 0.04045 then
        return math.pow((x + 0.055)/(1 + 0.055), 2.4)
    else
        return x / 12.92
    end
end

---Converts from sRGB to Linear sRGB
---@param colour Vector3
---@return Vector3
function lib.srgbToLinear(colour)
    return colour:applyFunc(toLinear)
end

---Converts from Linear sRGB to sRGB
---@param colour Vector3
---@return Vector3
function lib.linearToSrgb(colour)
    return colour:applyFunc(fromLinear)
end

local linearToOklabLmsMatrix = matrices.mat3(
    vec(0.4122214708, 0.2119034982, 0.0883024619),
    vec(0.5363325363, 0.6806995451, 0.2817188376),
    vec(0.0514459929, 0.1073969566, 0.6299787005)
)

local lmsToOklabMatrix = matrices.mat3(
    vec(0.2104542553, 1.9779984951, 0.0259040371),
    vec(0.7936177850, -2.4285922050, 0.7827717662),
    vec(-0.0040720468, 0.4505937099, -0.8086757660)
)

---@param x number
---@return number
local function cbrt(x)
    return math.pow(x, 1/3)
end

---Converts from Linear sRGB to OKLAB
---@param colour Vector3
---@return Vector3
function lib.linearToOklab(colour)
    return colour:transform(linearToOklabLmsMatrix):applyFunc(cbrt):transform(lmsToOklabMatrix)
end

local oklabToLmsMatrix = matrices.mat3(
    vec(1, 1, 1),
    vec(0.3963377774, -0.1055613458, -0.0894841775),
    vec(0.2158037573, -0.0638541728, -1.2914855480)
)

local lmsToLinearMatrix = matrices.mat3(
    vec(4.0767416621, -1.2684380046, -0.0041960863),
    vec(-3.3077115913, 2.6097574011, -0.7034186147),
    vec(0.2309699292, -0.3413193965, 1.7076147010)
)

---@param x number
---@return number
local function cube(x)
    return x * x * x
end

---Converts from OKLAB to Linear sRGB
---@param colour Vector3
---@return Vector3
function lib.oklabToLinear(colour)
    return colour:transform(oklabToLmsMatrix):applyFunc(cube):transform(lmsToLinearMatrix)
end

---Converts from LAB to LCh
---@param colour Vector3
---@return Vector3
function lib.labToLch(colour)
    return vec(
        colour.x,
        math.sqrt(colour.y * colour.y + colour.z * colour.z),
        math.deg(math.atan2(colour.z, colour.y))
    )
end

---Converts from LCh to LAB
---@param colour Vector3
---@return Vector3
function lib.lchToLab(colour)
    return vec(
        colour.x,
        colour.y * math.cos(math.rad(colour.z)),
        colour.y * math.sin(math.rad(colour.z))
    )
end



---Converts from sRGB to OKLCh
---@param colour Vector3
---@return Vector3
function lib.srgbToOklch(colour)
    return lib.labToLch(lib.linearToOklab(lib.srgbToLinear(colour)))
end

---Converts from OKLCh to sRGB
---@param colour Vector3
---@return Vector3
function lib.oklchToSrgb(colour)
    return lib.linearToSrgb(lib.oklabToLinear(lib.lchToLab(colour)))
end

return lib