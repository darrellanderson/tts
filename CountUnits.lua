

local data = {
    -- Map from hex id (tostring(hex)) to set of guids (map from guid to true).
    -- e.g. { '<0,0,0>' = { 'guid1' = true, 'guid2' = true }}.
    unitsInHex = {},

    -- The last hex where a command token dropped.
    lastActivatedHex = nil,
}

-------------------------------------------------------------------------------
-- Hex grid math from redblobgames
-- https://www.redblobgames.com/grids/hexagons/implementation.html

local HexGrid = {}
HexGrid.hex_metatable = {
    __tostring = function(hex)
        return '<' .. hex.q .. ',' .. hex.r .. ',' .. hex.s .. '>'
    end
}
function HexGrid.Hex(q, r, s)
    assert(not (math.floor (0.5 + q + r + s) ~= 0), "q + r + s must be 0")
    local result = { q = q, r = r, s = s }
    setmetatable(result, HexGrid.hex_metatable)
    return result
end
function HexGrid.Point(x, y)
    return {x = x, y = y}
end
function HexGrid.Orientation(f0, f1, f2, f3, b0, b1, b2, b3, start_angle)
    return {f0 = f0, f1 = f1, f2 = f2, f3 = f3, b0 = b0, b1 = b1, b2 = b2, b3 = b3, start_angle = start_angle}
end
function HexGrid.Layout(orientation, size, origin)
    return {orientation = orientation, size = size, origin = origin}
end
function HexGrid.hex_add (a, b)
    return HexGrid.Hex(a.q + b.q, a.r + b.r, a.s + b.s)
end
HexGrid.hex_directions = {
    HexGrid.Hex(1, 0, -1),
    HexGrid.Hex(1, -1, 0),
    HexGrid.Hex(0, -1, 1),
    HexGrid.Hex(-1, 0, 1),
    HexGrid.Hex(-1, 1, 0),
    HexGrid.Hex(0, 1, -1)
}
function HexGrid.hex_neighbors (hex)
    result = {}
    for _, d in ipairs(HexGrid.hex_directions) do
        table.insert(result, HexGrid.hex_add(hex, d))
    end
    return result
end
function HexGrid.hex_round (h)
    local qi = math.floor(math.floor (0.5 + h.q))
    local ri = math.floor(math.floor (0.5 + h.r))
    local si = math.floor(math.floor (0.5 + h.s))
    local q_diff = math.abs(qi - h.q)
    local r_diff = math.abs(ri - h.r)
    local s_diff = math.abs(si - h.s)
    if q_diff > r_diff and q_diff > s_diff then
        qi = -ri - si
    else
        if r_diff > s_diff then
            ri = -qi - si
        else
            si = -qi - ri
        end
    end
    return HexGrid.Hex(qi, ri, si)
end
function HexGrid.hex_to_pixel (layout, h)
    local M = layout.orientation
    local size = layout.size
    local origin = layout.origin
    local x = (M.f0 * h.q + M.f1 * h.r) * size.x
    local y = (M.f2 * h.q + M.f3 * h.r) * size.y
    return HexGrid.Point(x + origin.x, y + origin.y)
end
function HexGrid.pixel_to_hex (layout, p)
    local M = layout.orientation
    local size = layout.size
    local origin = layout.origin
    local pt = HexGrid.Point((p.x - origin.x) / size.x, (p.y - origin.y) / size.y)
    local q = M.b0 * pt.x + M.b1 * pt.y
    local r = M.b2 * pt.x + M.b3 * pt.y
    return HexGrid.Hex(q, r, -q - r)
end
function HexGrid.hex_corner_offset (layout, corner)
    local M = layout.orientation
    local size = layout.size
    local angle = 2.0 * math.pi * (M.start_angle - corner) / 6.0
    return HexGrid.Point(size.x * math.cos(angle), size.y * math.sin(angle))
end
function HexGrid.polygon_corners (layout, h)
    local corners = {}
    local center = HexGrid.hex_to_pixel(layout, h)
    for i = 0, 5 do
        local offset = HexGrid.hex_corner_offset(layout, i)
        table.insert(corners, HexGrid.Point(center.x + offset.x, center.y + offset.y))
    end
    return corners
end
HexGrid.orientation_pointy = HexGrid.Orientation(math.sqrt(3.0), math.sqrt(3.0) / 2.0, 0.0, 3.0 / 2.0, math.sqrt(3.0) / 3.0, -1.0 / 3.0, 0.0, 2.0 / 3.0, 0.5)
HexGrid.orientation_flat = HexGrid.Orientation(3.0 / 2.0, 0.0, math.sqrt(3.0) / 2.0, math.sqrt(3.0), 2.0 / 3.0, 0.0, -1.0 / 3.0, math.sqrt(3.0) / 3.0, 0.0)

-------------------------------------------------------------------------------

--- TI4 grid.  It would be nice if TTS exposed grid settings to scripts.
local ti4HexGridLayout = HexGrid.Layout(HexGrid.orientation_flat, HexGrid.Point(3.5, 3.5), HexGrid.Point(0, 0))

--- Get the hex at the given position.
-- @param position {x, y, z} table.
-- @return hex, neighbors list
function getHex(position)
    local p = HexGrid.Point(position.x, position.z)
    local hex = HexGrid.pixel_to_hex(ti4HexGridLayout, p)
    hex = HexGrid.hex_round(hex)
    return hex

--- Get neighboring hexes.
-- @param hex
-- @return neighbor hexes list
function getNeighborHexes(hex)
    return HexGrid.hex_neighbors(hex)
end

--- Generate hex outline suitable for Global.setVectorLines({value}).
-- Useful for verifying hex grid here matches the TTS grid.
-- @param hex
-- @return vectors list entry
function getHexVectorLines(hex)
    local corners = HexGrid.polygon_corners(ti4HexGridLayout, hex)
    local line = {
        points = {},
        color = {1, 1, 1},
        thickness = 0.1,
        rotation = {0, 0, 0},
        loop = true,
        square = false,
    }
    y = 1
    for i, point in ipairs(corners) do
        table.insert(line.points, {point.x, y, point.y})
    end
    return line
end

-------------------------------------------------------------------------------

local Util = {}
function Util.printTable(table, indent)
    if not indent then
        indent = ''
    end
    if not table then
        print(indent .. 'nil')
        return
    end
    for k, v in pairs(table) do
        if type(v) ~= 'table' then
            print(indent .. tostring(k) .. ' = ' .. tostring(v))
        else
            print(indent .. tostring(k) .. ' = {')
            Util.printTable(v, '  ' .. indent)
            print(indent .. '}')
        end
    end
end

-------------------------------------------------------------------------------

function attacker()
    return playerColor
end

function defender()
    return playerColor
end

function hasPDS2(playerColor)
    return false
end

function hasAntimassDeflector(playerColor)
    return false
end

-------------------------------------------------------------------------------

function onLoad(save_state)
    print('onLoad')
end

function onObjectPickUp(picked_up_object, player_color)
    local hex = getHex(picked_up_object.getPosition())
    local unitsSet = data.unitsInHex[hex]
    if unitsSet then
        unitsSet[picked_up_object.getGUID()] = nil
    end
end

function onObjectDrop(dropped_object, player_color)
    local hexKey = tostring()
end

function onPickUp(player_color)
    -- body...
end

function onDrop(player_color)
    local hex = getHex(self.getPosition())
    print(hex)
    print(tostring(hex))

    local vectors = { getHexVectorLines(hex) }
    vectors[1].color = {1, 0, 0, 0.5}
    vectors[1].thickness = 2
    for _, neighbor in ipairs(neighbors) do
        table.insert(vectors, getHexVectorLines(neighbor))
        vectors[#vectors].color = {1, 1, 1, 0.5}
    end
    Global.setVectorLines(vectors)
end
