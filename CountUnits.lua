--- Auto-fill the_Mantis's TI4 MutliRoller (tested with v3.46.0).
-- @author bonkersbgg at boardgamegeek.com
--[[

This script keeps track of the last activated system (command token dropped
by the active player this turn), and scans the board to fill in the_Mantis's
excellent TI4 MultiRoller.

The active fleet takes into account if the MultiRoller belongs to the attacker,
defender, or third party who happens to have range with an adjacent PDS2.

It scans for Antimass Deflector on the other party, and reminds players with
Plasma Scoring to activate it for the appropriate unit depending on the next
action (e.g. Space Cannon vs Bombardment).

PDS2 targets adjacent and through-wormhole, including the Creuss flagship's
mobile delta wormhole.  The Winnu flagship sets its count to the number of
non-fighter opponents.  The Xxcha flagship has an adjacent-reaching PDS.
pp
Creuss players might want to enable "grid" on their homeworld so it aligns well
with the table grid, making sure units on the planet are counted.

This requires Turns be enabed to ignore when a non-active player touches a
command token.  (Turns are automatically enabled via the "place trade goods and
set turns" button.)  For a hot-seat like environment, a player must change color
to the current active turn in order to recognize system activation.

HOW TO USE:

Right click this object and select "Save Object".  Start a TI4 game, then
click "Objects" at the top, then "Saved Objects", then this saved object to
spawn one in the game.  Clicking the "add auto-fill buttons" adds an "auto-fill"
button to each MultiRoller sheet.

During a game, clicking the "auto-fill" button fills in the combat MultiRoller.
The script prints console messages to the clicking player, or right click to
broadcast them to the entire table.

--]]

local data = {
    -- Draw colors about activated, neighbor, and through-wormhole hexes.
    debugVisualizeEnabled = false,

    -- Verbose logging, not recommended for normal use.
    debugLogEnabled = false,

    -- Send light information to all players, suitable for normal use.
    -- Note that right-clicking the auto-fill button temporarily activates this.
    debugPrintToSelfEnabled = true,
    debugPrintToAllEnabled = false,

    -- The last position where the active player dropped a command token.
    lastActivatedPosition = nil,

    -- Map from auto-fill panel objects to the associated MutliRoller.
    autoFillPanelToMultiRoller = {},

    -- Is the current action done via alt(right)-clicking on a button?
    altClick = false,

    -- Unit attributes:
    -- "ship" boolean is this a ship (vs ground unit).
    units = {
        ['Infantry'] = {},
        ['Fighter'] = { ship = true },
        ['Cruiser'] = { ship = true },
        ['Destroyer'] = { ship = true },
        ['Carrier'] = { ship = true },
        ['Space Dock'] = {},
        ['PDS'] = {},
        ['Dreadnought'] = { ship = true },
        ['War Sun'] = { ship = true },
        ['Flagship'] = { ship = true },
    },

    -- The TTS mode renames flagships to the faction-specific name.
    -- Flagship attributes:
    -- "faction" string name.
    -- "wormhole" string wormhole name.
    -- "pds2Count" integer number of PDS2 attached.
    -- "nonFighterDice" boolean set count each to non-fighter opponents.
    flagships = {
        ['Duha Menaimon'] = { faction = 'The Arborec' },
        ['Arc Secundus'] = { faction = 'The Barony of Letnev' },
        ['Son of Ragh'] = { faction = 'The Clan of Saar' },
        ['The Inferno'] = { faction = 'The Embers of Muaat' },
        ['Wrath of Kenara'] = { faction = 'The Emirates of Hacan' },
        ['Genesis'] = { faction = 'The Federation of Sol' },
        ['Hil Colish'] = { faction = 'The Ghosts of Creuss', wormhole = 'delta' },
        ['[0.0.1]'] = { faction = 'The L1Z1X Mindnet' },
        ['Fourth Moon'] = { faction = 'The Mentak Coalition' },
        ['Matriarch'] = { faction = 'The Naalu Collective', fighersOnGround = true },
        ['The Alastor'] = { faction = 'The Nekro Virus', infantryInSpace = true },
        ["C'morran N'orr"] = { faction = "The Sardakk N'orr" },
        ['J.N.S. Hylarim'] = { faction = 'The Universities of Jol-Nar' },
        ['Salai Sai Corian'] = { faction = 'The Winnu', nonFighterDice = true },
        ['Loncara Ssodu'] = { faction = 'The Xxcha Kingdom', spaceCannon = true },
        ['Van Hauge'] = { faction = 'The Yin Brotherhood' },
        ["Y'sia Y'ssrila"] = { faction = 'The Yssaril Tribes' },
    },

    -- GUIDs for wormhole map tiles and Cruess tokens.
    wormholeObjects = {
        -- Planet tiles.
        ['c56a8a'] = 'delta',
        ['71e1bf'] = 'beta',
        ['f11ef5'] = 'alpha',
        ['0378a4'] = 'alpha',
        ['ccd7ac'] = 'beta',
        ['f38182'] = 'delta',

        -- Ghost flagship.
        -- Hmm, is this static?  Find it by name rather than guid.

        -- Ghost extra wormhole tokens.
        ['0d2f86'] = 'alpha',
        ['cba3a7'] = 'beta',
    },

    -- Card attrbitues:
    -- "owner" string "us" or "them", scan appropriate player.
    cards = {
        ['PDS II'] = { owner = 'us' },
        ['Antimass Deflectors'] = { owner = 'them' },
        ['Plasma Scoring'] = { owner = 'us' }
    },
}

-- Organize functions into namespaces.
local Debug = {}
local TI4Zone = {}
local RedBlobHexLib = {}
local TI4Hex = {}
local Util = {}

-------------------------------------------------------------------------------

function Debug.log(message)
    if data.debugLogEnabled then
        print(message)
    end
end

function Debug.logTable(name, table, indent)
    if not data.debugLogEnabled then
        return
    end
    if not indent then
        indent = ''
    end
    if not table then
        print(indent .. name .. ' = nil')
        return
    end
    print(indent .. name .. ' = {')
    if table then
        for k, v in pairs(table) do
            if type(v) ~= 'table' then
                print(indent .. tostring(k) .. ' = ' .. tostring(v))
            else
                Debug.logTable(tostring(k), v, '   ' .. indent)
            end
        end
    end
    print(indent .. '}')
end

-- If enabled, send messages.
function Debug.printToAll(message, color)
    -- Add a prefix to make it clear where the message came from.
    local message = self.getName() .. ': ' .. message
    if data.debugPrintToAllEnabled or data.altClick then
        printToAll(message, color)
    else if data.debugPrintToSelfEnabled then
        for _, seated in ipairs(getSeatedPlayers()) do
            if seated == color then
                printToColor(message, color, color)
                return
            end
        end
        -- If we get here, there is no player with that color.
        -- Just print to the cliker's console.
        print(message)
    end
    end
end

--- ALWAYS send these messages.
function Debug.errorToAll(message, color)
    printToAll(self.getName() .. ': ' .. message, color)
end

-------------------------------------------------------------------------------
-- TI4 zone locations, adapted from the TI4 mod Global.Lua
-- Could achieve something similar using seated players' hand locations,
-- but this is more flexible for handling things when a player is absent.

--- Get all zones in a single pass of getAllObjects.
-- @return table from color to zone index, table from zone index to color.
function TI4Zone.all()
    local colorToZoneIndex = {}
    local zoneIndexToColor = {}
    for _, obj in ipairs(getAllObjects()) do
        local name = obj.getName()
        local checkName = string.find(name, 'Command Sheet')
        if checkName ~= nil then
            local cmdSheetColor = string.sub(name, 16, -2)
            local pos = obj.getPosition()
            for zoneIndex = 1, 6 do
                if TI4Zone.inside(pos, zoneIndex) then
                    colorToZoneIndex[cmdSheetColor] = zoneIndex
                    zoneIndexToColor[zoneIndex] = cmdSheetColor
                    break
                end
            end
        end
    end
    return colorToZoneIndex, zoneIndexToColor
end

local xmin = {21, -21, -51, 21, -21, -51}
local xmax = {51, 21, -21, 51, 21, -21}
local zmin = {-50, -50, -50, 6, 21, 6}
local zmax = {-6, -21, -6, 49, 49, 49}

--- Is the given location inside the zone index?
-- @param pos {x, y, z} table.
-- @param zoneIndex numeric index per player, or 'Tiles' for map area.
-- @return boolean true if in zone.
function TI4Zone.inside(pos, zoneIndex)
    local minimumZ
    local maximumZ
    if zoneIndex == 2 then
        if pos.x > 1.5 then
            maximumZ = 0.6 * pos.x - 20.4
            return pos.x >= xmin[zoneIndex] and pos.x <= xmax[zoneIndex] and pos.z >= zmin[zoneIndex] and pos.z <= maximumZ
        elseif pos.x <-1.5 then
            maximumZ = -0.6 * pos.x - 20.4
            return pos.x >= xmin[zoneIndex] and pos.x <= xmax[zoneIndex] and pos.z >= zmin[zoneIndex] and pos.z <= maximumZ
        else
            return pos.x >= xmin[zoneIndex] and pos.x <= xmax[zoneIndex] and pos.z >= zmin[zoneIndex] and pos.z <= -21
        end
    elseif zoneIndex == 5 then
        if pos.x > 1.5 then
            minimumZ = -0.6 * pos.x + 20.4
            return pos.x >= xmin[zoneIndex] and pos.x <= xmax[zoneIndex] and pos.z >= minimumZ and pos.z <= zmax[zoneIndex]
        elseif pos.x <-1.5 then
            minimumZ = 0.6 * pos.x + 20.4
            return pos.x >= xmin[zoneIndex] and pos.x <= xmax[zoneIndex] and pos.z >= minimumZ and pos.z <= zmax[zoneIndex]
        else
            return pos.x >= xmin[zoneIndex] and pos.x <= xmax[zoneIndex] and pos.z >= 21 and pos.z <= zmax[zoneIndex]
        end
    elseif zoneIndex == 1 or zoneIndex == 3 or zoneIndex == 4 or zoneIndex == 6 then
        return pos.x >= xmin[zoneIndex] and pos.x <= xmax[zoneIndex] and pos.z >= zmin[zoneIndex] and pos.z <= zmax[zoneIndex]
    elseif zoneIndex == 'Tiles' then
        return pos.x >= -28 and pos.x <= 28 and pos.z >= -28 and pos.z <= 28
    end
end

--- Get the closest player zone index.
-- @param pos {x,y,z} table.
-- @return zoneIndex integer.
function TI4Zone.closest(pos)
    local bestZoneIndex = nil
    local bestDistanceSq = nil
    for zoneIndex = 1, 6 do
        local x = (xmin[zoneIndex] + xmax[zoneIndex]) / 2
        local z = (zmin[zoneIndex] + zmax[zoneIndex]) / 2
        local dx = pos.x - x
        local dz = pos.z - z
        local distanceSq = (dx * dx) + (dz * dz)
        if not bestDistanceSq or distanceSq < bestDistanceSq then
            bestZoneIndex = zoneIndex
            bestDistanceSq = distanceSq
        end
    end
    return bestZoneIndex
end

-------------------------------------------------------------------------------
-- Hex grid math from redblobgames
-- https://www.redblobgames.com/grids/hexagons/implementation.html
-- Uses 2D {x,y} points.

function RedBlobHexLib.Hex(q, r, s)
    assert(not (math.floor (0.5 + q + r + s) ~= 0), 'q + r + s must be 0')
    return {q = q, r = r, s = s}
end
function RedBlobHexLib.hexToString(hex)
    return '<' .. hex.q .. ',' .. hex.r .. ',' .. hex.s .. '>'
end
function RedBlobHexLib.hexFromString(str)
    q, r, s = string.match(str, '<(%-?%d+),(%-?%d+),(%-?%d+)>')
    return RedBlobHexLib.Hex(tonumber(q), tonumber(r), tonumber(s))
end
function RedBlobHexLib.Point(x, y)
    return {x = x, y = y}
end
function RedBlobHexLib.Orientation(f0, f1, f2, f3, b0, b1, b2, b3, start_angle)
    return {f0 = f0, f1 = f1, f2 = f2, f3 = f3, b0 = b0, b1 = b1, b2 = b2, b3 = b3, start_angle = start_angle}
end
function RedBlobHexLib.Layout(orientation, size, origin)
    return {orientation = orientation, size = size, origin = origin}
end
function RedBlobHexLib.hex_add (a, b)
    return RedBlobHexLib.Hex(a.q + b.q, a.r + b.r, a.s + b.s)
end
RedBlobHexLib.hex_directions = {
    RedBlobHexLib.Hex(1, 0, -1),
    RedBlobHexLib.Hex(1, -1, 0),
    RedBlobHexLib.Hex(0, -1, 1),
    RedBlobHexLib.Hex(-1, 0, 1),
    RedBlobHexLib.Hex(-1, 1, 0),
    RedBlobHexLib.Hex(0, 1, -1)
}
function RedBlobHexLib.hex_neighbors (hex)
    result = {}
    for _, d in ipairs(RedBlobHexLib.hex_directions) do
        table.insert(result, RedBlobHexLib.hex_add(hex, d))
    end
    return result
end
function RedBlobHexLib.hex_round (h)
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
    return RedBlobHexLib.Hex(qi, ri, si)
end
function RedBlobHexLib.hex_to_pixel (layout, h)
    local M = layout.orientation
    local size = layout.size
    local origin = layout.origin
    local x = (M.f0 * h.q + M.f1 * h.r) * size.x
    local y = (M.f2 * h.q + M.f3 * h.r) * size.y
    return RedBlobHexLib.Point(x + origin.x, y + origin.y)
end
function RedBlobHexLib.pixel_to_hex (layout, p)
    local M = layout.orientation
    local size = layout.size
    local origin = layout.origin
    local pt = RedBlobHexLib.Point((p.x - origin.x) / size.x, (p.y - origin.y) / size.y)
    local q = M.b0 * pt.x + M.b1 * pt.y
    local r = M.b2 * pt.x + M.b3 * pt.y
    return RedBlobHexLib.Hex(q, r, -q - r)
end
function RedBlobHexLib.hex_corner_offset (layout, corner)
    local M = layout.orientation
    local size = layout.size
    local angle = 2.0 * math.pi * (M.start_angle - corner) / 6.0
    return RedBlobHexLib.Point(size.x * math.cos(angle), size.y * math.sin(angle))
end
function RedBlobHexLib.polygon_corners (layout, h)
    local corners = {}
    local center = RedBlobHexLib.hex_to_pixel(layout, h)
    for i = 0, 5 do
        local offset = RedBlobHexLib.hex_corner_offset(layout, i)
        table.insert(corners, RedBlobHexLib.Point(center.x + offset.x, center.y + offset.y))
    end
    return corners
end
RedBlobHexLib.orientation_pointy = RedBlobHexLib.Orientation(math.sqrt(3.0), math.sqrt(3.0) / 2.0, 0.0, 3.0 / 2.0, math.sqrt(3.0) / 3.0, -1.0 / 3.0, 0.0, 2.0 / 3.0, 0.5)
RedBlobHexLib.orientation_flat = RedBlobHexLib.Orientation(3.0 / 2.0, 0.0, math.sqrt(3.0) / 2.0, math.sqrt(3.0), 2.0 / 3.0, 0.0, -1.0 / 3.0, math.sqrt(3.0) / 3.0, 0.0)

-------------------------------------------------------------------------------
-- Hex grid for the TTS TI4 mod.  Uses 3d x,y,z points.  Encode hex as a string
-- for use as table keys.

--- TI4 grid.  It would be nice if TTS exposed grid settings vs hard coding.
TI4Hex.layout = RedBlobHexLib.Layout(RedBlobHexLib.orientation_flat, RedBlobHexLib.Point(3.5, 3.5), RedBlobHexLib.Point(0, 0))

--- Get the hex at the given position.
-- @param position {x, y, z} table.
-- @return string-encoded hex.
function TI4Hex.hex(position)
    local point2d = RedBlobHexLib.Point(position.x, position.z)
    local hex = RedBlobHexLib.pixel_to_hex(TI4Hex.layout, point2d)
    hex = RedBlobHexLib.hex_round(hex)
    return RedBlobHexLib.hexToString(hex)
end

--- Convert hex to 3D position.
-- @param hexString hex.
-- @return table {x, y, z} position.
function TI4Hex.position(hexString)
    local hex = RedBlobHexLib.hexFromString(hexString)
    local point2d = RedBlobHexLib.hex_to_pixel(TI4Hex.layout, hex)
    return { x = point2d.x, y = 1, z = point2d.y }
end

--- Get neighboring hexes.
-- @param hexString hex.
-- @return neighbor hexes list
function TI4Hex.neighbors(hexString)
    local hex = RedBlobHexLib.hexFromString(hexString)
    local neighbors = RedBlobHexLib.hex_neighbors(hex)
    local result = {}
    for _, neighbor in ipairs(neighbors) do
        table.insert(result, RedBlobHexLib.hexToString(neighbor))
    end
    return result
end

--- Generate hex outline suitable for Global.setVectorLines({value}).
-- Useful for verifying hex grid here matches the TTS grid.
-- @param hexString hex.
-- @param overrideValues table of vector line key/values.
-- @return vectors list entry
function TI4Hex.vectorLines(hexString, overrideValues)
    local hex = RedBlobHexLib.hexFromString(hexString)
    local corners = RedBlobHexLib.polygon_corners(TI4Hex.layout, hex)
    local line = {
        points = {},
        color = {1, 1, 1},
        thickness = 0.1,
        rotation = {0, 0, 0},
        loop = true,
        square = false,
    }
    if overrideValues then
        for k, v in pairs(overrideValues) do
            line[k] = v
        end
    end
    y = 1
    for i, point2d in ipairs(corners) do
        table.insert(line.points, {point2d.x, y, point2d.y})
    end
    return line
end

--- If the hex contains a wormhole or the ghost flagship, it is also
-- adjacent to peer wormholes.
-- @param hexString hex.
-- @return list of adjacent-via-wormhole hexes.
function TI4Hex.wormholeNeighborHexes(hexString)
    -- Copy the map of hardcoded wormhole objects, adding the Cruess
    -- flagship (the guid may vary).
    local wormholeObjects = {}
    for k, v in pairs(data.wormholeObjects) do
        wormholeObjects[k] = v
    end

    -- Add any flagship wormholes to the set.
    local flagshipWormholeObjectNames = {}
    for name, flagship in pairs(data.flagships) do
        if flagship.wormhole then
            table.insert(flagshipWormholeObjectNames, name)
        end
    end
    local objectsByName = Util.findObjectsByName(flagshipWormholeObjectNames)
    for name, objects in pairs(objectsByName) do
        local flagship = data.flagships[name]
        for _, obj in ipairs(objects) do
            -- Only consider wormholes in the map/tiles area (Creuss wormhole
            -- tokens might be on the table but not in use, and cannot be
            -- on a home system so the external Creuss map tile is not valid).
            -- It is possible for the Creuss flagship to be off the map (outside
            -- Tiles) if it is on the external Creuss home system to the size, but
            -- that already is a delta wormhole so no special handling needed.
            if TI4Zone.inside(obj.getPosition(), 'Tiles') then
                wormholeObjects[obj.getGUID()] = flagship.wormhole
            end
        end
    end

    -- Get all wormholes in the given hex.
    local wormholesInHex = {}
    for guid, wormhole in pairs(wormholeObjects) do
        local obj = getObjectFromGUID(guid)
        if obj then
            local objHexString = TI4Hex.hex(obj.getPosition())
            if objHexString == hexString then
                wormholesInHex[wormhole] = true
            end
        end
    end

    -- Get hexes with matching wormholes.
    local result = {}
    for guid, wormhole in pairs(wormholeObjects) do
        if wormholesInHex[wormhole] then
            local obj = getObjectFromGUID(guid)
            if obj then
                local objHexString = TI4Hex.hex(obj.getPosition())
                -- With the exception of the Creuss homeworld, require other
                -- wormholes be in the map area.
                local goodPos = (guid == 'f38182') or TI4Zone.inside(obj.getPosition(), 'Tiles')
                if objHexString ~= hexString and goodPos then
                    table.insert(result, objHexString)
                end
            end
        end
    end

    return TI4Hex.getUniqueHexes(result)
end

--- Prune a list of hexes to unique entries.
-- @param hexes list of hexes.
-- @return list of hexes.
function TI4Hex.getUniqueHexes(hexStrings)
    local result = {}
    local seen = {}
    for _, hexString in ipairs(hexStrings) do
        if not seen[hexString] then
            seen[hexString] = true
            table.insert(result, hexString)
        end
    end
    return result
end

--- Get the hex at location, plus all direct and through-wormhole neighbors.
-- If debug visualization is enabled draws vector outlines around the hexes.
-- @param pos {x,y,z} table.
-- @return hex string, list of neighbor hex strings.
function TI4Hex.getHexAndAllNeighborsAndMaybeVisualize(pos)
    local hex = TI4Hex.hex(pos)

    local neighbors = TI4Hex.neighbors(hex)
    local wormholeNeighbors = TI4Hex.wormholeNeighborHexes(hex)

    if data.debugVisualizeEnabled then
        local vectors = {}
        for _, neighbor in ipairs(wormholeNeighbors) do
            table.insert(vectors, TI4Hex.vectorLines(neighbor, {color={0,0,1,0.7},thickness=0.33}))
        end
        for _, neighbor in ipairs(neighbors) do
            table.insert(vectors, TI4Hex.vectorLines(neighbor, {color={0,1,0,0.7},thickness=0.66}))
        end
        table.insert(vectors, TI4Hex.vectorLines(hex, {color={1,0,0,0.7},thickness=1}))
        Global.setVectorLines(vectors)
    end

    -- Merge neighbors into a single list.
    local allNeighbors = Util.joinLists(neighbors, wormholeNeighbors)
    allNeighbors = TI4Hex.getUniqueHexes(allNeighbors)

    return hex, allNeighbors
end

-------------------------------------------------------------------------------
-- Some generic utility functions.

function Util.joinLists(a, b)
    local result = {}
    for _, v in ipairs(a) do
        table.insert(result, v)
    end
    for _, v in ipairs(b) do
        table.insert(result, v)
    end
    return result
end

function Util.listToString(a)
    local result = ''
    for i, v in ipairs(a) do
        if i > 1 then
            result = result .. ', '
        end
        result = result .. tostring(v)
    end
    return result
end

--- Search for a set of objects.
-- Use this when scanning for multiple objects to reduce the number of passes.
-- @param names list of object names.
-- @return table from object name to list of objects with that name.
function Util.findObjectsByName(names)
    local result = {}
    local namesSet = {}
    for _, name in ipairs(names) do
        namesSet[name] = true
    end
    for _, obj in ipairs(getAllObjects()) do
        local name = obj.getName()
        if namesSet[name] then
            local objectsByName = result[name]
            if not objectsByName then
                objectsByName = {}
                result[name] = objectsByName
            end
            table.insert(objectsByName, obj)
        end
    end
    return result
end

--- Does the given player have the card object face up near them?
-- @param cardObject object.
-- @param zoneIndex player TI4Zone zone index.
-- @return boolean true of player has card.
function Util.playerHasCard(cardObject, zoneIndex)
    -- Reject if face down.
    if cardObject.is_face_down then
        return false
    end

    -- Reject if in hand (this is how multiroller does it, is there a better way?)
    if cardObject.getPosition().y >= 2.5 then
        return false
    end

    -- Reject if not in player's zone.
    if not TI4Zone.inside(cardObject.getPosition(), zoneIndex) then
        return false
    end

    return true
end

--- Given a {r,g,b} color from a unit tintColor, return the string color name.
-- These values are hard-coded from tints assigned to ship models.
-- @param color {r,g,b} table.
-- @return string unit color.
function Util.unitColor(color)
    local unitColors = {
        White = { 204/255, 205/255, 204/255 },
        Blue = { 7/255, 178/255, 255/255 },
        Purple = { 118/255, 0, 183/255 },
        Green = { 0, 117/255, 6/255 },
        Red = { 203/255, 0, 0 },
        Yellow = { 165/255, 163/255, 0 },
    }
    local bestColor = nil
    local bestDistanceSq = nil
    for unitColorName, unitColor in pairs(unitColors) do
        local dr = unitColor[1] - (color.r or color[1])
        local dg = unitColor[2] - (color.g or color[2])
        local db = unitColor[3] - (color.b or color[3])
        local distanceSq = (dr * dr) + (dg * dg) + (db * db)
        if not bestDistanceSq or distanceSq < bestDistanceSq then
            bestColor = unitColorName
            bestDistanceSq = distanceSq
        end
    end
    return bestColor
end

-------------------------------------------------------------------------------
-- Parse and manage unit collections.

local Units = {}

--- Get the color and unit name of an object.
-- @param object.
-- @return color string, unit name string (or nil, nil if not a unit).
function Units.parse(obj)
    local name = obj.getName()
    if not name then
        return nil, nil
    end

    -- Flagships do not have the color as a name prefix.  Derive from tint.
    -- (Could also identify the faction based on unique flagship name, then
    -- inspect player sheets to locate seat).
    if data.flagships[name] then
        local color = Util.unitColor(obj.getColorTint())
        return color, 'Flagship'
    end

    -- Split name into "color unitName" values.
    local startPos, endPos = string.find(name, ' ')
    if not startPos then
        return nil, nil
    end
    local unitColor = string.sub(name, 1, startPos - 1)
    local unitName = string.sub(name, endPos + 1)

    if not data.units[unitName] then
        return nil, nil
    end
    return unitColor, unitName
end

--- Get units in a primary hex, as well as in a set of neibhbors.
-- Gather all relevant units in a single pass to reduce all-object scans.
--
-- Returns per-color unit collections e.g.
-- { Yellow = {
--     Infantry = { obj1, obj2, ... objN },
--     ...
--     Flagship = { obj1 }
--   },
--   Green = { .... }
-- }
--
-- @param hexString primary system hex.
-- @param neighborHexStrings adjacent systems.
-- @return table from color to table from unit name to list of unit objects.
function Units.get(hexString, neighborHexStrings)
    local neighborHexStringSet = {}
    if neighborHexStrings then
        for _, v in ipairs(TI4Hex.getUniqueHexes(neighborHexStrings)) do
            neighborHexStringSet[v] = true
        end
    end

    local unitsInHex = {}
    local unitsInNeighbors = {}
    for _, obj in ipairs(getAllObjects()) do
        local unitColor, unitName = Units.parse(obj)
        if unitColor and unitName then
            local unitHexString = TI4Hex.hex(obj.getPosition())

            -- Get the in-hex vs neighbor collection, or none if unit is
            -- not within either.
            local collection = false
            if unitHexString == hexString then
                collection = unitsInHex
            elseif neighborHexStringSet[unitHexString] then
                collection = unitsInNeighbors
            end

            if collection then
                -- Find or create the per-color sub-table.
                local colorCollection = collection[unitColor]
                if not colorCollection then
                    colorCollection = {}
                    collection[unitColor] = colorCollection
                end
                -- Find or create the collection[color][unitName] list.
                local unitList = colorCollection[unitName]
                if not unitList then
                    unitList = {}
                    colorCollection[unitName] = unitList
                end
                table.insert(unitList, obj)
            end
        end
    end
    return unitsInHex, unitsInNeighbors
end

--- Restrict to units of a specific type.
-- @param units map from unit name to list of unit objects.
-- @param want list of strings, any of {pds, ship, ground}
-- @return units map from unit name to list of unit objects.
function Units.filter(units, wantList)
    -- Get relevant flagship attributes.
    local fighersOnGround = false
    local infantryInSpace = false
    local flagshipIsPds = false
    local flagships = units['Flagship'] or {}
    for _, unitObject in ipairs(flagships) do
        local flagship = data.flagships[unitObject.getName()] or {}
        fighersOnGround = fighersOnGround or flagship.fighersOnGround
        infantryInSpace = infantryInSpace or flagship.infantryInSpace
        flagshipIsPds = flagshipIsPds or flagship.spaceCannon
    end

    local result = {}
    for unitName, unitList in pairs(units) do
        local unit = data.units[unitName] or {}

        -- With flagship attributes, a unit can be more than one type.
        local is = {}
        is.pds = unitName == 'PDS' or (flagshipIsPds and unitName == 'Flagship')
        is.ship = unit.ship or (infantryInSpace and unitName == 'Infantry')
        is.ground = (not unit.ship) or (fighersOnGround and unitName == 'Fighter')

        for _, want in ipairs(wantList) do
            if is[want] then
                result[unitName] = unitList
                break
            end
        end
    end
    return result
end

--- Filter, but with a color to units collection.
-- @param colorToUnits map from color to units collection (name to unit objects lists).
-- @return map from color to filtered units collection.
function Units.filterPerColor(colorToUnits, wantList)
    local result = {}
    for color, units in pairs(colorToUnits) do
        result[color] = Units.filter(units, wantList)
    end
    return result
end

-------------------------------------------------------------------------------

--- Get my color from player sheet position, deduce enemy from units in hex.
-- @param selfPosition {x,y,z} table.
-- @param unitsInHex Units.get result, map from color to unit collection.
-- @return self{color, zoneIndex}, enemy{color, zoneIndex} (may be nil).
function getSelfAndEnemyZones(sheetPosition, unitsInHex)
    -- Scans all objects, try not to call more than once!
    colorToZoneIndex, zoneIndexToColor = TI4Zone.all()

    -- Get self color based on owning object location.
    local selfZoneIndex = TI4Zone.closest(sheetPosition)
    local selfZone = {
        color = zoneIndexToColor[selfZoneIndex] or 'Grey',
        zoneIndex = selfZoneIndex
    }

    -- If self is not the color who activated the system (current turn owner)
    -- then enemy is always the activator.
    if selfZone.color ~= Turns.turn_color then
        local enemyZone = {
            color = Turns.turn_color,
            zoneIndex = colorToZoneIndex[Turns.turn_color]
        }
        return selfZone, enemyZone
    end

    -- Otherwise self is the player who activated the system.  The enemy is
    -- first other ships in the activated system, or failing that who has
    -- ground forces.  It is possible for (1) an empty system, or (2) more
    -- than one color of ground forces on idependent planets.  Do not choose
    -- in those cases.
    local nonSelfColorsInHex = {}
    local nonSelfShipColorsInHex = {}
    for color, units in pairs(unitsInHex) do
        if color ~= selfZone.color then
            table.insert(nonSelfColorsInHex, color)
            for unitName, unitObjects in pairs(units) do
                if data.units[unitName].ship then
                    table.insert(nonSelfShipColorsInHex, color)
                    break
                end
            end
        end
    end

    -- If there are non-self ships, always use that as the enemy.
    if #nonSelfShipColorsInHex > 0 then
        if #nonSelfShipColorsInHex == 1 then
            local enemyColor = nonSelfShipColorsInHex[1]
            local enemyZone = {
                color = enemyColor,
                zoneIndex = colorToZoneIndex[enemyColor]
            }
            return selfZone, enemyZone
        else
            -- Cannot have more than one non-self ship color.
            Debug.errorToAll(selfZone.color .. ' space combat sees more than one enemy: ' .. Util.listToString(nonSelfShipColorsInHex))
            return selfZone, nil
        end
    end

    -- Otherwise no ships.  If ground forces use that as enemy.
    if #nonSelfColorsInHex > 0 then
        if #nonSelfColorsInHex == 1 then
            local enemyColor = nonSelfColorsInHex[1]
            local enemyZone = {
                color = enemyColor,
                zoneIndex = colorToZoneIndex[enemyColor]
            }
            return selfZone, enemyZone
        else
            -- If multiple ground force colors do not choose.
            Debug.errorToAll(selfZone.color .. ' invasion sees more than one ground force: ' .. Util.listToString(nonSelfColorsInHex))
            return selfZone, nil
        end
    end

    -- No non-self units, no enemy.
    return selfZone, nil
end

--- Get cards relevant to the given player/enemy pair.
-- E.g., does the player have PDS2, does the enemy have AMD?
-- @param playerZoneIndex zone.
-- @param playerZoneIndex zone.
-- @return table from card name to card object.
function getCombatSheetCards(playerZoneIndex, enemyZoneIndex)
    -- Get all matching cards.
    local objectNames = {}
    for name, attributes in pairs(data.cards) do
        table.insert(objectNames, name)
    end

    local result = {}
    for name, objects in pairs(Util.findObjectsByName(objectNames)) do
        local attributes = data.cards[name]
        local zone = false
        if attributes.owner == 'us' then
            zone = playerZoneIndex
        else
            zone = enemyZoneIndex
        end
        if zone then
            for _, object in ipairs(objects) do
                if TI4Zone.inside(object.getPosition(), zone) then
                    result[name] = object
                end
            end
        end
    end

    return result
end

--- Get the number of units affecting the activated system.
-- @param sheetPosition {x,y,z} table for multi-roller sheet, used to find player.
-- @param activatedHexPosition {x,y,z} table for activated system.
-- @param wantList list of {pds, ship, ground} strings to restrict results.
-- @return table from unit name to quantity, list of relevant cards.
function getCombatSheetValues(sheetPosition, activatedHexPosition, wantList)
    local resultUnits = {}
    local resultCards = {}

    -- Get units in hex and neighbors.
    local hex, neighbors = TI4Hex.getHexAndAllNeighborsAndMaybeVisualize(activatedHexPosition)
    local unitsInHex, unitsInNeighbors = Units.get(hex, neighbors)
    if wantList then
        unitsInHex = Units.filterPerColor(unitsInHex, wantList)
        unitsInNeighbors = Units.filterPerColor(unitsInNeighbors, wantList)
    end

    -- This table can be large, comment out logging it for now.
    --Debug.logTable('unitsInNeighbors', unitsInNeighbors)

    -- Get self color based on sheet position, deduce enemy based on units
    -- in the activated system (may be nil if no enemy units in that system).
    local selfZone, enemyZone = getSelfAndEnemyZones(sheetPosition, unitsInHex)
    local selfColor = selfZone and selfZone.color
    local enemyColor = enemyZone and enemyZone.color
    Debug.printToAll('filling for ' .. (selfColor or '<unknown>') .. ' vs ' .. (enemyColor or '<unknown>'), selfColor)

    -- Look for relevant cards (e.g. PDS2) in the appropriate self/enemy zones.
    resultCards = getCombatSheetCards(selfZone and selfZone.zoneIndex, enemyZone and enemyZone.zoneIndex)
    Debug.logTable('resultCards', resultCards)
    if resultCards['Antimass Deflectors'] then
        Debug.printToAll('enemy has Antimass Deflectors', selfColor)
    end
    if resultCards['Plasma Scoring'] then
        Debug.printToAll(selfColor .. ' has Plasma Scoring, apply it to the appropriate unit for different roll types', selfColor)
    end

    -- Get own units in system.
    local msg = ''
    local myLocalUnits = (selfColor and unitsInHex[selfColor]) or {}
    for unitName, unitObjects in pairs(myLocalUnits) do
        resultUnits[unitName] = #unitObjects
        if msg ~= '' then
            msg = msg .. ', '
        end
        msg = msg .. resultUnits[unitName] .. ' ' .. unitName
    end
    if msg ~= '' then
        Debug.printToAll('in system: ' .. msg, selfColor)
    end

    -- If PDS2, get pds in adjacent systems.
    local myNeighborUnits = (selfColor and unitsInNeighbors[selfColor]) or {}
    if resultCards['PDS II'] and myNeighborUnits['PDS'] then
        local count = #myNeighborUnits['PDS']
        Debug.printToAll('PDS2 with ' .. count .. ' adjacent PDS', selfColor)
        resultUnits['PDS'] = (resultUnits['PDS'] or 0) + count
    end

    local myLocalFlagships = myLocalUnits['Flagship'] or {}
    local myNeighborFlagships = myNeighborUnits['Flagship'] or {}
    local myFlagshipsIncludeNeighbors = Util.joinLists(myLocalFlagships, myNeighborFlagships)

    -- The Xxcha flagship has Space Combat that can shoot adjacent systems.
    -- Do not include this if there is a wantList that does not include PDS!
    local wantPds = not wantList
    for _, want in ipairs(wantList or {}) do
        if want == 'pds' then
            wantPds = true
        end
    end
    if wantPds and not resultUnits['Flagship'] then
        for _, obj in ipairs(myFlagshipsIncludeNeighbors) do
            local name = obj.getName()
            local flagship = data.flagships[name]
            if flagship and flagship.spaceCannon then
                Debug.printToAll(name .. ' has space cannon', selfColor)
                resultUnits['Flagship'] = (resultUnits['Flagship'] or 0) + 1
            end
        end
    end

    -- The Winnu flagship uses the number of non-fighter ships for value.
    for _, obj in ipairs(myLocalFlagships) do
        local name = obj.getName()
        local flagship = data.flagships[name]
        if flagship and flagship.nonFighterDice then
            local count = 0
            local enemyLocalUnits = (enemyColor and unitsInHex[enemyColor]) or {}
            for unitName, unitObjects in pairs(enemyLocalUnits) do
                local unitAttributes = data.units[unitName]
                if data.units[unitName].ship and unitName ~= 'Fighter' then
                    count = count + #unitObjects
                end
            end
            Debug.printToAll(name .. ' with ' .. count .. ' dice', selfColor)
            resultUnits['Flagship'] = count
        end
    end

    Debug.logTable('resultUnits', resultUnits)
    return selfColor, resultUnits, resultCards
end

--- Inject values into the multiroller.
-- I hate to abuse another object's methods especially since this functionality
-- requires the method names and side effects keep working in future versions
-- of that independent object.  This would be MUCH better with either a stable
-- method for injecting values, or by incorporating directly into that object.
function fillMultiRoller(multiRoller, selfColor, units, cards)
    if not multiRoller then
        Debug.log('no MultiRoller')
        return
    end
    Debug.log('MultiRoller guid ' .. multiRoller.getGUID())

    Debug.log('MultiRoller.resetCounters')
    multiRoller.call('resetCounters')

    local inputs = multiRoller.getInputs()
    if units then
        for unitName, quantity in pairs(units) do
            local inputLabel = 'UNIT:' .. unitName
            local found = false
            for _, input in ipairs(inputs) do
                if input.label == inputLabel then
                    found = true
                    multiRoller.editInput({ index = input.index, value = quantity })
                    break
                end
            end
            if not found then
                print('Warning: no input ' .. inputLabel)
            end
        end
    end

    if cards['Antimass Deflectors'] then
        Debug.log('MultiRoller.clickAMD')
        multiRoller.call('clickAMD')
    end

    -- Click the "update button" by calling the associated downstream function.
    -- Technically calling "shipPlus" above also does this, but do it again in
    -- case that changes in the future.
    Debug.log('MultiRoller.detectCards ' .. tostring(selfColor or 'none'))
    multiRoller.call('detectCards', selfColor)
end

-------------------------------------------------------------------------------

function autoFill(autoFillPanel, altClick, wantList)
    local pos = data.lastActivatedPosition
    if not pos then
        print(self.getName() .. ': no activated system, aborting')
        return
    end

    -- Right-click buttons to print messages to all rather than just self.
    data.altClick = altClick or false

    -- Make pos the center of the hex.
    pos = TI4Hex.position(TI4Hex.hex(pos))

    -- Get the values.
    local multiRoller = data.autoFillPanelToMultiRoller[autoFillPanel]
    local sheetPosition = multiRoller.getPosition()
    local color, units, cards = getCombatSheetValues(sheetPosition, pos, wantList)

    -- If doing print-to-all, also show the ping arrow over the activated hex.
    if data.altClick then
        Player[color].pingTable(pos)
    end

    fillMultiRoller(multiRoller, color, units, cards)

    data.altClick = false
end

function onClickAutoFillPds(autoFillPanel, playerClickColor, altClick)
    autoFill(autoFillPanel, altClick, {'pds'})
end

function onClickAutoFillShip(autoFillPanel, playerClickColor, altClick)
    autoFill(autoFillPanel, altClick, {'ship'})
end

function onClickAutoFillGround(autoFillPanel, playerClickColor, altClick)
    autoFill(autoFillPanel, altClick, {'ground'})
end

-------------------------------------------------------------------------------

function spawnAutoFillPanelForMultiRoller(obj)
    -- Create a new panel for the buttons.
    -- Position takes into account the roller orientation.
    local panelPos = obj.positionToWorld({
        x = 0,
        y = 0.1,
        z = 1.15
    })
    Debug.logTable('pos', obj.getPosition())
    Debug.logTable('panelPos', panelPos)
    local panel = spawnObject({
        type = 'Card',
        --position = panelPos,
        scale = {
            x = 9.28,
            y = 1,
            z = 0.7
        },
        rotation = obj.getRotation(),
        snap_to_grid = false,
        sound = false,
    })
    panel.setName(self.getName() .. ' Panel')
    panel.use_grid = false
    panel.use_snap_points = false
    panel.use_gravity = false
    panel.interactable = false
    panel.setPosition(panelPos)
    panel.setLock(true)

    -- Connect this panel to the MultiRoller.
    data.autoFillPanelToMultiRoller[panel] = obj

    local fontSize = 300
    local width = 2800
    local height = 600
    local x0 = -0.7
    local dx = 0.7
    local y = 0.5
    local z0 = 0
    local dz = 0

    local invScale = panel.getScale()
    local buttonScale = { x = 1.0 / invScale.x, y = 1.0 / invScale.y, z = 1.0 / invScale.z }

    -- Note: the function_owner is used to locate the function, and must be
    -- "self".  When the function gets called, the first parameter "obj"
    -- will be the object the button is connected to via createButton.

    panel.createButton({
        click_function = 'onClickAutoFillPds',
        function_owner = self,
        label = 'AUTO-FILL PDS',
        font_size = fontSize,
        width = width,
        height = height,
        position = { x = x0 + dx * 0, y = y, z = z0 + dz * 0 },
        scale = buttonScale,
    })
    panel.createButton({
        click_function = 'onClickAutoFillShip',
        function_owner = self,
        label = 'AUTO-FILL SHIPS',
        font_size = fontSize,
        width = width,
        height = height,
        position = { x = x0 + dx * 1, y = y, z = z0 + dz * 1 },
        scale = buttonScale,
    })
    panel.createButton({
        click_function = 'onClickAutoFillGround',
        function_owner = self,
        label = 'AUTO-FILL GROUND',
        font_size = fontSize,
        width = width,
        height = height,
        position = { x = x0 + dx * 2, y = y, z = z0 + dz * 2 },
        scale = buttonScale,
    })
end

function getAutoFillPanels()
    local result = {}
    local name = self.getName() .. ' Panel'
    for _, obj in ipairs(getAllObjects()) do
        if obj.getName() == name then
            table.insert(result, obj)
        end
    end
    return (#result > 0 and result) or nil
end

function addAutoFillButtonsToMultiRollers()
    local existing = getAutoFillPanels()
    if existing then
        print('already have auto-fill buttons')
        return
    end
    local count = 0
    for _, obj in ipairs(getAllObjects()) do
        local startPos, endPos = string.find(obj.getName(), 'TI4 MultiRoller')
        if startPos == 1 then
            spawnAutoFillPanelForMultiRoller(obj)
            count = count + 1
        end
    end
    print('added auto-fill buttons to ' .. count .. ' MultiRollers')
end

function removeAutoFillButtonsFromMultiRollers()
    local existing = getAutoFillPanels()
    if not existing then
        print('no auto-fill buttons to remove')
        return
    end

    data.autoFillPanelToMultiRoller = {}

    local count = #existing
    for _, obj in ipairs(existing) do
        obj.destruct()
    end
    print('removed auto-fill buttons from ' .. count .. ' MultiRollers')
end

-------------------------------------------------------------------------------

function onLoad(save_state)
    -- Scale the block and attach a button with reversed scale.
    local scale = { x = 3, y = 0.1, z = 1 }
    local buttonScale = { x = 1.0 / scale.x, y = 1.0 / scale.y, z = 1.0 / scale.z }
    self.setScale(scale)
    self.createButton({
        click_function = 'addAutoFillButtonsToMultiRollers',
        function_owner = self,
        label = 'ADD AUTO-FILL\nMULTIROLLER BUTTONS',
        font_size = 100,
        width = 1200,
        height = 290,
        position = { x = 0, y = 0.5, z = -0.15 },
        scale = buttonScale,
    })
    self.createButton({
        click_function = 'removeAutoFillButtonsFromMultiRollers',
        function_owner = self,
        label = 'REMOVE',
        font_size = 100,
        width = 1200,
        height = 150,
        position = { x = 0, y = 0.5, z = 0.3 },
        scale = buttonScale,
    })
    self.interactable = true
end

function onObjectDrop(playerColor, droppedObject)
    if playerColor == Turns.turn_color and string.find(droppedObject.getName(), ' Command Token') and TI4Zone.inside(droppedObject.getPosition(), 'Tiles') then
        Debug.log('onObjectDrop: activated by ' .. playerColor)
        data.lastActivatedPosition = droppedObject.getPosition()
    end
end
