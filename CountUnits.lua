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
mobile delta wormhole.  The Winnu flagship sets it count to the number of
non-fighter opponents.

The Xxcha flagship acts like an adjacent-reaching PDS x3 (even when the player
has not researched PDS2), which is not quite right as the flagship Space Cannon
hits on a 5 rather that the PDS1's 6.

Creuss players might want to enable "grid" on their homeworld so it aligns well
with the table grid, making sure units on the planet are counted.

This requires Turns be enabed to prevent in order to ignore when a non-active
player touches a command token.  Turns are automatically enabled via the "place
trade goods and set turns" button.  For a hot-seat like environment, a player
must change color to the current active turn recognize system activation.

--]]

local data = {
    -- Draw colors about activated, neighbor, and through-wormhole hexes.
    debugVisualizeEnabled = true,

    -- Verbose logging, not recommended for normal use.
    debugLogEnabled = true,

    -- Send light information to all players, suitable for normal use.
    debugPrintToAllEnabled = true,

    printToTablePrefix = 'Auto-fill MultiRoller: ',

    -- The last hex where the active player dropped a command token.
    lastActivatedHex = nil,

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
        ['Matriarch'] = { faction = 'The Naalu Collective' },
        ['The Alastor'] = { faction = 'The Nekro Virus' },
        ["C'morran N'orr"] = { faction = "The Sardakk N'orr" },
        ['J.N.S. Hylarim'] = { faction = 'The Universities of Jol-Nar' },
        ['Salai Sai Corian'] = { faction = 'The Winnu', nonFighterDice = true },
        ['Loncara Ssodu'] = { faction = 'The Xxcha Kingdom', pds2Count = 3 },
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
                Debug.logTable(tostring(k), v, '  ' .. indent)
            end
        end
    end
    print(indent .. '}')
end

function Debug.printToAll(message, color)
    if data.debugPrintToAllEnabled then
        printToAll(self.getName() .. ': ' .. message, color)
    end
end

-------------------------------------------------------------------------------
-- TI4 zone locations, borrowed from the TI4 mod Global.Lua
-- Could achieve something similar using seated players' hand locations,
-- but this is more flexible for handling things when a player is absent.

--- Get all zones in a single pass of getAllObjects.
-- @return table mapping from player color to zone index.
function TI4Zone.all()
    local result = {}
    for _, obj in ipairs(getAllObjects()) do
        local name = obj.getName()
        local pos = obj.getPosition()
        local checkName = string.find(name, "Command Sheet")
        if checkName ~= nil then
            local cmdSheetColor = string.sub(name, 16, -2)
            for zone = 1, 6 do
                if TI4Zone.inside(pos, zone) then
                    result[cmdSheetColor] = zone
                    break
                end
            end
        end
    end
    return result
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

function TI4Zone.closest(pos)
    
end

-------------------------------------------------------------------------------
-- Hex grid math from redblobgames
-- https://www.redblobgames.com/grids/hexagons/implementation.html
-- Uses 2D {x,y} points.

function RedBlobHexLib.Hex(q, r, s)
    assert(not (math.floor (0.5 + q + r + s) ~= 0), "q + r + s must be 0")
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
function TI4Hex.getWormholeNeighborHexes(hexString)
    -- Copy the map of hardcoded wormhole objects, adding the Cruess
    -- flagship (the guid may vary).
    local wormholeObjects = {}
    for k, v in pairs(data.wormholeObjects) do
        wormholeObjects[k] = v
    end

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
            -- It is possible for the Creuss flagship to be off the map (outside
            -- Tiles) if it is on the external Creuss home system to the size, but
            -- that already as a delta wormhole so no special handling needed.
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

-------------------------------------------------------------------------------
-- Some generic utility functions.

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

--- Given a {r,g,b} color from a unit tintColor, return the string player color.
-- @param color {r,g,b} table.
-- @return string player color.
function Util.playerColor(color)
    local playerColors = {
        White = { 204/255, 205/255, 204/255 },
        Blue = { 7/255, 178/255, 255/255 },
        Purple = { 118/255, 0, 183/255 },
        Green = { 0, 117/255, 6/255 },
        Red = { 203/255, 0, 0 },
        Yellow = { 165/255, 163/255, 0 },
    }
    local bestColor = nil
    local bestDistanceSq = nil
    for playerColorName, playerColor in pairs(playerColors) do
        local dr = playerColor[1] - (color.r or color[1])
        local dg = playerColor[2] - (color.g or color[2])
        local db = playerColor[3] - (color.b or color[3])
        local distanceSq = (dr * dr) + (dg * dg) + (db * db)
        if not bestDistanceSq or distanceSq < bestDistanceSq then
            bestColor = playerColorName
            bestDistanceSq = distanceSq
        end
    end
    return bestColor
end

function Util.getSelfAndEnemyColors(owningObj, unitsInHex)
    -- Scans all objects, try not to call more than once!
    local allZones = TI4Zone.all()
    Debug.logTable('allZones', allZones)

    -- Get self color based on owning object location.
    local selfColor = false
    for color, zoneIndex in pairs(allZones) do
        if TI4Zone.inside(owningObj.getPosition(), zoneIndex) then
            selfColor = {
                color = color,
                zoneIndex = zoneIndex
            }
            break
        end
    end
    Debug.logTable('selfColor', selfColor)

    -- Get enemy color as the non-self units in the hex.  It is possible
    -- the activated hex has no non-self units, in which case enemy is nil.
    local enemyColor = false
    local sawSelf = false
    for color, units in pairs(unitsInHex) do
        if selfColor and color == selfColor.color then
            sawSelf = true
        elseif enemyColor then
            Debug.log('already have an enemy color .. too many colors in hex?')
            printToAll(self.getName() .. ': error, more than two colors in system', selfColor.color)
        else
            enemyColor = {
                color = color,
                zoneIndex = allZones[color]
            }
        end
    end

    return selfColor, enemyColor
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
        local color = Util.playerColor(obj.getColorTint())
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

-------------------------------------------------------------------------------

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
-- @param playerColor string.
-- @param enemyColor string (relevant to Winnu flagship).
-- @param cards map of relevant card names to card objects.
-- @return table from unit name to quantity.
function getCombatSheetValues(selfColor, enemyColor, unitsInHex, unitsInNeighbors, cards)
    -- Get own units in system.
    local result = {}
    local msg = ''
    local myLocalUnits = (selfColor and unitsInHex[selfColor]) or {}
    for unitName, unitObjects in pairs(myLocalUnits) do
        result[unitName] = #unitObjects
        if msg ~= '' then
            msg = msg .. ', '
        end
        msg = msg .. result[unitName] .. ' ' .. unitName
    end
    if msg ~= '' then
        Debug.printToTable('in system: ' .. msg, selfColor)
    end

    -- If PDS2, get pds in adjacent systems.
    local myNeighborUnits = (selfColor and unitsInNeighbors[selfColor]) or {}
    if cards['PDS II'] and myNeighborUnits['PDS'] then
        local count = #myNeighborUnits['PDS']
        Debug.printToTable('PDS2 with ' .. count .. ' adjacent PDS', selfColor)
        result['PDS'] = (result['PDS'] or 0) + count
    end

    local myLocalFlagships = myLocalUnits['Flagship']
    local myNeighborFlagships = myNeighborUnits['Flagship']
    local allFlagships = {}
    if myLocalFlagships then
        for _, obj in ipairs(myLocalFlagships) do
            table.insert(allFlagships, obj)
        end
    end
    if myNeighborFlagships then
        for _, obj in ipairs(myNeighborFlagships) do
            table.insert(allFlagships, obj)
        end
    end
    for _, obj in ipairs(allFlagships) do
        local name = obj.getName()
        local flagship = data.flagships[name]

        -- If Xxcha flagship, count as extra pds.
        if flagship and flagship.pdsCount then
            Debug.printToTable(name .. ' for ' .. flagship.pdsCount .. ' extra PDS', selfColor)
            result['PDS'] = (result['PDS'] or 0) + flagship.pdsCount
        end

        -- If Winnu flagship, value is number of non-fighter enemies.
        if flagship and flagship.nonFighterDice then
            local count = 0
            local enemyLocalUnits = (enemyColor and unitsInHex[enemyColor]) or {}
            for unitName, unitObjects in ipairs(enemyLocalUnits) do
                if data.units[unitName].ship and unitName != 'Fighter' then
                    count = count + #unitObjects
                end
            end
            Debug.printToTable(name .. ' with ' .. count .. ' dice', playerColor)
            result['Flagship'] = count
        end
    end

    if cards['Antimass Deflectors'] then
        Debug.printToAll('enemy has Antimass Deflectors')
    end
    if cards['Plasma Scoring'] then
        Debug.printToAll(playerColor .. ' has Plasma Scoring, apply it to the appropriate unit for different roll types')
    end

    return result
end

--- Inject values into the multiroller.
-- I hate to abuse another object's methods especially since this functionality
-- requires the method names and side effects keep working in future versions
-- of that independent object.  This would be MUCH better with either a stable
-- method for injecting values, or by incorporating directly into that object.
function fillMultiRoller(multiRoller, cards, units)
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
    Debug.log('MultiRoller.detectCards')
    multiRoller.call('detectCards', playerColor)
end

function autofillMultiRoller(owningObject, playerClickColor, altClick)
    local hex = data.lastActivatedHex
    if not hex then
        print(self.getName() .. ': no activated system, aborting')
        return
    end
    if data.printToAllEnabled then
        local pos = TI4Hex.position(hex)
        Player[playerColor].pingTable(pos)
    end

    -- Get activated hex and neighbors.
    local neighbors = TI4Hex.neighbors(hex)
    local wormholeNeighbors = TI4Hex.getWormholeNeighborHexes(hex)
    local allNeighbors = {}
    for _, hex in ipairs(neighbors) do
        table.insert(allNeighbors, hex)
    end
    for _, hex in ipairs(wormholeNeighbors) do
        table.insert(allNeighbors, hex)
    end
    allNeighbors = TI4Hex.getUniqueHexes(allNeighbors)
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

    -- Get units.
    local unitsInHex, unitsInNeighbors = Units.get(hex, allNeighbors)
    Debug.logTable('unitsInHex', unitsInHex)
    Debug.logTable('unitsInNeighbors', unitsInNeighbors)

    -- Get colors.
    local selfColor, enemyColor = Util.getSelfAndEnemyColors(owningObject, unitsInHex)
    Debug.logTable('selfColor', selfColor)
    Debug.logTable('enemyColor', enemyColor)
    Debug.printToAll('filling for ' .. (selfColor and selfColor.color or '<unknown>') .. ' vs ' .. (enemyColor and enemyColor.color or '<unknown>'), playerColor)

    -- Get cards.
    local cards = getCombatSheetCards(selfColor and selfColor.zoneIndex, enemyColor and enemyColor.zoneIndex)
    Debug.logTable('cards', cards)

    local values = getCombatSheetValues(selfColor and selfColor.color, enemyColor and enemyColor.color, unitsInHex, unitsInNeighbors, cards)

    -- TODO merge units, flagships, cards.
    fillMultiRoller(owningObject, cards, selfColor and unitsInHex[selfColor.color])
end

-------------------------------------------------------------------------------

function getAutoFillButton(obj)
    local buttons = obj.getButtons()
    for _, button in ipairs(buttons) do
        if button.label == 'AUTO-FILL\nMULTIROLLER' then
            return button
        end
    end
end

function addAutoFillButtonsToMultiRollers()
    for _, obj in ipairs(getAllObjects()) do
        local startPos, endPos = string.find(obj.getName(), 'TI4 MultiRoller')
        if startPos == 1 then
            if not getAutoFillButton(obj) then
                print('adding button to ' .. obj.getName())
                obj.createButton({
                    click_function = 'autofillMultiRoller',
                    function_owner = self,
                    label = 'AUTO-FILL\nMULTIROLLER',
                    font_size = 40,
                    width = 300,
                    height = 50,
                    position = { x = 0.7, y = 0.2, z = 0 },
                })
            end
        end
    end
end

function removeAutoFillButtonsFromMultiRollers()
    for _, obj in ipairs(getAllObjects()) do
        local startPos, endPos = string.find(obj.getName(), 'TI4 MultiRoller')
        if startPos == 1 then
            local button = getAutoFillButton(obj)
            if button then
                print('removing button from ' .. obj.getName())
                obj.removeButton(button.index)
            end
        end
    end
end

-------------------------------------------------------------------------------

function onLoad(save_state)
    print('onLoad')

    -- Scale the block and attach a button with reversed scale.
    local scale = { x = 3, y = 0.01, z = 1 }
    self.setScale(scale)
    self.createButton({
        click_function = 'addAutoFillButtonsToMultiRollers',
        function_owner = self,
        label = 'ADD AUTO-FILL\nMULTIROLLER BUTTONS',
        font_size = 100,
        width = 1200,
        height = 290,
        position = { x = 0, y = 0.2, z = -0.15 },
        scale = { x = 1.0 / scale.x, y = 1.0 / scale.y, z = 1.0 / scale.z },
    })
    self.createButton({
        click_function = 'removeAutoFillButtonsFromMultiRollers',
        function_owner = self,
        label = 'REMOVE',
        font_size = 100,
        width = 1200,
        height = 150,
        position = { x = 0, y = 0.2, z = 0.3 },
        scale = { x = 1.0 / scale.x, y = 1.0 / scale.y, z = 1.0 / scale.z },
    })
    self.interactable = true
end

function onObjectDrop(playerColor, droppedObject)
    if playerColor == Turns.turn_color and string.find(droppedObject.getName(), ' Command Token') and TI4Zone.inside(droppedObject.getPosition(), 'Tiles') then
        Debug.log('onObjectDrop: activated by ' .. playerColor)
        data.lastActivatedHex = TI4Hex.hex(droppedObject.getPosition())
    end
end
