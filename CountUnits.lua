--- Unit counter, fill in battle sheets.
-- @author bonkersbgg at boardgamegeek.com

local data = {
    debugVisualize = true,
    debugLogEnabled = false,
    maybePrintToTable = true,

    -- Map from hex id (tostring(hex)) to set of guids (map from guid to true).
    -- e.g. { '<0,0,0>' = { 'guid1' = true, 'guid2' = true }}.
    unitsInHex = {},

    -- The last hex where the active player dropped a command token.
    lastActivatedHex = nil,
    lastActivatedPlayerColor = nil,

    unitNames = {
        ['Infantry'] = true,
        ['Fighter'] = true,
        ['Cruiser'] = true,
        ['Destroyer'] = true,
        ['Carrier'] = true,
        ['Space Dock'] = true,
        ['PDS'] = true,
        ['Dreadnought'] = true,
        ['War Sun'] = true,
        ['Flagship'] = true,

        -- If per-faction unit name overrides are in place,
        -- here's a mapping back to the standard unit names.
        --[[
        ['Letani Warrior'] = 'Infantry',
        ['Floating Factory'] = 'Space Dock',
        ['Prototype War Sun'] = 'War Sun',
        ['Spec Ops'] = 'Infantry',
        ['Super-Dreadnought'] = 'Dreadnought',
        ['Hybrid Crystal Fighter'] = 'Fighter',
        ['Exotrireme'] = 'Dreatnought',
        --]]
    },

    unitNamesNonFighters = {
        ['Cruiser'] = true,
        ['Destroyer'] = true,
        ['Carrier'] = true,
        ['Dreadnought'] = true,
        ['War Sun'] = true,
        ['Flagship'] = true,
    },

    flagshipNames = {
        ['Duha Menaimon'] = true,
        ['Arc Secundus'] = true,
        ['Son of Ragh'] = true,
        ['The Inferno'] = true,
        ['Wrath of Kenara'] = true,
        ['Genesis'] = true,
        ['Hil Colish'] = true,
        ['[0.0.1]'] = true,
        ['Fourth Moon'] = true,
        ['Matriarch'] = true,
        ['The Alastor'] = true,
        ["C'morran N'orr"] = true,
        ['J.N.S. Hylarim'] = true,
        ['Salai Sai Corian'] = true,
        ['Loncara Ssodu'] = true,
        ['Van Hauge'] = true,
        ["Y'sia Y'ssrila"] = true,

        -- Name reserved for testing.
        ['MyTestHexThingy'] = true,
    },

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

    -- Ghosts flagship contains a delta wormhole.
    wormholeFlagship = { name = 'Hil Colish', wormhole = 'delta' },

    -- Xxcha flagship can fire space cannon into adjacent systems.
    pdsFlagship = { name = 'Loncara Ssodu', pdsCount = 3 },

    winnuFlagship = { name = 'Salai Sai Corian' },

    pds2Card = { name = 'PDS II' },
    antimassDeflectorCard = { name = 'Antimass Deflector' },
    plasmaScoringCard = { name = 'Plasma Scoring' },

    -- Map from player color name to value.
    playerColors = {
        White = {1, 1, 1},
        Brown = {0.443, 0.231, 0.09},
        Red = {0.856, 0.1, 0.094},
        Orange = {0.956, 0.392, 0.113},
        Yellow = {0.905, 0.898, 0.172},
        Green = {0.192, 0.701, 0.168},
        Teal = {0.129, 0.694, 0.607},
        Blue = {0.118, 0.53, 1},
        Purple = {0.627, 0.125, 0.941},
        Pink = {0.96, 0.439, 0.807},
        Grey = {0.5, 0.5, 0.5},
        Black = {0.25, 0.25, 0.25}
    },

}

-- Function collections.
local HexGrid = {}
local Util = {}

-------------------------------------------------------------------------------
-- Hex grid math from redblobgames
-- https://www.redblobgames.com/grids/hexagons/implementation.html

HexGrid.hex_metatable = {
    __tostring = function(hex)
        return '<' .. hex.q .. ',' .. hex.r .. ',' .. hex.s .. '>'
    end,
    __eq = function(a, b)
        return a.q == b.q and a.r == b.r and a.s == b.s
    end,
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
    local point2d = HexGrid.Point(position.x, position.z)
    local hex = HexGrid.pixel_to_hex(ti4HexGridLayout, point2d)
    hex = HexGrid.hex_round(hex)
    return hex
end

function getHexPosition(hex)
    local point2d = HexGrid.hex_to_pixel(ti4HexGridLayout, hex)
    return { x = point2d.x, y = 1, z = point2d.y }
end

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
function getHexVectorLines(hex, overrideValues)
    local corners = HexGrid.polygon_corners(ti4HexGridLayout, hex)
    local line = {
        points = {},
        color = (overrideValues and overrideValues.color) or {1, 1, 1},
        thickness = (overrideValues and overrideValues.thickness) or 0.1,
        rotation = {0, 0, 0},
        loop = true,
        square = false,
    }
    y = 1
    for i, point2d in ipairs(corners) do
        table.insert(line.points, {point2d.x, y, point2d.y})
    end
    return line
end

--- If the hex contains a wormhole or the ghost flagship, it is also
-- adjacent to peer wormholes.
-- @param hex
-- @return list of adjacent-via-wormhole hexes.
function getWormholeNeighborHexes(hex)
    -- Build a map from objects to wormholes in them.
    local wormholeObjects = {}
    for k, v in pairs(data.wormholeObjects) do
        wormholeObjects[k] = v
    end
    for _, obj in ipairs(getAllObjects()) do
        if obj.getName() == data.wormholeFlagship.name and Util.isInTilesZone(obj.getPosition()) then
            obj.highlightOn({0,1,0}, 10)
            wormholeObjects[obj.getGUID()] = data.wormholeFlagship.wormhole
            break
        end
    end

    -- Get all wormholes in the given hex.
    local wormholesInHex = {}
    for guid, wormhole in pairs(wormholeObjects) do
        local obj = getObjectFromGUID(guid)
        local objHex = obj and getHex(obj.getPosition())
        if objHex == hex then
            wormholesInHex[wormhole] = true
        end
    end

    -- Get hexes with matching wormholes.
    local result = {}
    for guid, wormhole in pairs(wormholeObjects) do
        if wormholesInHex[wormhole] then
            local obj = getObjectFromGUID(guid)
            local objHex = obj and getHex(obj.getPosition())
            if objHex ~= hex then
                table.insert(result, objHex)
            end
        end
    end

    result = getUniqueHexes(result)
    Util.debugLog('getWormholeNeighborHexes: |result|=' .. tostring(#result))
    return result
end

--- Prune a list of hexes to unique entries.
-- @param hexes list of hexes.
-- @return list of hexes.
function getUniqueHexes(hexes)
    local result = {}
    local seen = {}
    for _, hex in ipairs(hexes) do
        local hexString = tostring(hex)
        if not seen[hexString] then
            seen[hexString] = true
            table.insert(result, hex)
        end
    end
    return result
end

-------------------------------------------------------------------------------

function Util.debugLog(message)
    if data.debugLogEnabled then
        print(message)
    end
end

function Util.debugLogTable(name, table, indent)
    if not data.debugLogEnabled then
        return
    end
    if not indent then
        indent = ''
    end
    print(indent .. name .. ' = {')
    if table then
        for k, v in pairs(table) do
            if type(v) ~= 'table' then
                print(indent .. tostring(k) .. ' = ' .. tostring(v))
            else
                Util.debugLogTable(tostring(k), v, '  ' .. indent)
            end
        end
    end
    print(indent .. '}')
end

--- Find the seated player closest to the given position.
-- @param position table with {x, y, z} keys.
-- @return Player.
function Util.getClosestPlayer(position)
    local bestPlayer = nil
    local bestDistanceSq = nil
    for _, playerColor in ipairs(getSeatedPlayers()) do
        local player = Player[playerColor]
        if player.getHandCount() > 0 then
            -- consider only the first hand location
            local handPosition = player.getHandTransform(1).position
            local dx = position.x - handPosition.x
            local dy = position.y - handPosition.y
            local dz = position.z - handPosition.z
            local distanceSq = (dx * dx) + (dy * dy) + (dz * dz)
            if not bestDistanceSq or distanceSq < bestDistanceSq then
                bestPlayer = player
                bestDistanceSq = distanceSq
            end
        end
    end
    return bestPlayer
end

--- Given a color, return the nearest PlayerColor.
-- @param color table with r, g, b values.
-- @return string PlayerColor.
function Util.colorToPlayerColor(color)
    local bestColor = nil
    local bestDistanceSq = nil
    for playerColorName, playerColor in pairs(data.playerColors) do
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

--- Is this position in the map area?
-- @return boolean true if in map area.
function Util.isInTilesZone(position)
    return position.x >= -28 and position.x <= 28 and position.z >= -28 and position.z <= 28
end

--- Does the given player have the card object face up near them?
-- @param playerColor string.
-- @param cardObject object.
-- @return boolean true of player has card.
function Util.playerHasCard(playerColor, cardObject)
    -- Reject if face down.
    if cardObject.is_face_down then
        return false
    end

    -- Reject if in hand (this is how multiroller does it, is there a better way?)
    if cardObject.getPosition().y >= 2.5 then
        return false
    end

    -- Reject if closer to another player.
    if not Util.getClosestPlayer(cardObject.getPosition()).color then
        return false
    end

    return true
end

function Util.maybePrintToTable(message, color)
    if data.maybePrintToTable then
        printToAll('Combat Sheet Filler: ' .. message, color)
    end
end

-------------------------------------------------------------------------------

--- Get the color and unit name of an object.
-- @param object.
-- @return color string, unit name string (or nil, nil if not a unit).
function parseUnit(object)
    local name = object.getName()
    if not name then
        return nil, nil
    end

    if data.flagshipNames[name] then
        -- Flagships do not have the color as a name prefix.  Derive from tint.
        -- (Could also identify the faction based on unique flagship name, then
        -- inspect player sheets to locate seat).
        local color = Util.colorToPlayerColor(object.getColorTint())
        return color, 'Flagship'
    end

    -- Split name into "color unitName" values.
    local startPos, endPos = string.find(name, ' ')
    if not startPos then
        return nil, nil
    end
    local unitColor = string.sub(name, 1, startPos - 1)
    local unitName = string.sub(name, endPos + 1)

    -- Abort if not a player color.
    if not data.playerColors[unitColor] then
        return nil, nil
    end

    -- Abort if not a unit name.
    if not data.unitNames[unitName] then
        return nil, nil
    end

    return unitColor, unitName
end

--- Keep track of this object hex?
function isTracked(object)
    local unitColor, unitName = parseUnit(object)
    if unitColor and unitName then
        return true
    end

    -- Do we want to track any objects other than units?
    return false
end

--- Get the set of player colors with units in a hex.
-- @param hex.
-- @return list of player color strings.
function getUnitColorsInHex(hex)
    local hexString = tostring(hex)
    local result = {}
    local seen = {}
    local unitsSet = data.unitsInHex[hexString] or {}

    for guid, _ in pairs(unitsSet) do
        local object = getObjectFromGUID(guid)
        if object then
            local unitColor, unitName = parseUnit(object)
            local unitHex = getHex(object.getPosition())

            -- Verify still there!
            if unitHex == hex and not seen[unitColor] then
                seen[unitColor] = true
                table.insert(result, unitColor)
            end
        end
    end
    return result
end

--- Get units from a hex.
-- Return the unit objects themselves rather than simple quantities in case
-- further inspection is necessary.
-- @param playerColor string.
-- @param hex.
-- @return table from unit name to list of unit objects.
function getUnitsInHex(playerColor, hex)
    local result = {}
    local hexString = tostring(hex)
    local unitsSet = data.unitsInHex[hexString] or {}

    for guid, _ in pairs(unitsSet) do
        local object = getObjectFromGUID(guid)
        if object then
            local unitColor, unitName = parseUnit(object)
            local unitHex = getHex(object.getPosition())

            -- Select objects with correct color (and verify still there!).
            if unitColor == playerColor and unitHex == hex then
                local unitList = result[unitName]
                if not unitList then
                    unitList = {}
                    result[unitName] = unitList
                end
                table.insert(unitList, object)
            end
        end
    end
    return result
end

--- Get units from a list of hexes.
-- @param playerColor string.
-- @param hexes list of hex objects.
-- @return table from unit name to list of unit objects.
function getUnitsInHexes(playerColor, hexes)
    result = {}
    for _, hex in ipairs(getUniqueHexes(hexes)) do
        for unitName, objects in pairs(getUnitsInHex(playerColor, hex)) do
            local unitList = result[unitName]
            if not unitList then
                unitList = {}
                result[unitName] = unitList
            end
            for _, object in ipairs(objects) do
                table.insert(unitList, object)
            end
        end
    end
    return result
end

--- Who is attacking the last activated system?
-- @return string player color.
function attacker()
    local result = data.lastActivatedPlayerColor
    Util.debugLog('attacker -> ' .. tostring(result))
    return result
end

--- Who is defending the last activated system?
-- @return string player color, or nil if no explicit defender.
function defender()
    local result = nil

    if not data.lastActivatedHex then
        Util.debugLog('defender -> nil (no last activated hex)')
        return
    end

    -- There cannot be more than 2 unit colors in a space, if that happens
    -- do not attempt to deduce the defener.  If there are exactly two,
    -- make sure one is the attacker and return the other one.  If only one,
    -- it is the defender if not the attacker (e.g., activate a system to fire
    -- PDS2 from an adjacent system).
    local unitColors = getUnitColorsInHex(data.lastActivatedHex)
    local attackerColor = attacker()
    local sawAttacker = false
    if #unitColors <= 2 then
        for _, unitColor in ipairs(unitColors) do
            if unitColor == attackerColor then
                sawAttacker = true
            else
                result = unitColor
            end
        end
    end
    if #unitColors == 2 and not sawAttacker then
        Util.debugLog('defender -> nil (two colors, but neither is attacker)')
        return
    end

    Util.debugLog('defender -> ' .. tostring(result))
    return result
end

-------------------------------------------------------------------------------

--- From the given player's perspective, who is the enemy?
-- @param playerColor string.
-- @return enemyColor string, or nil if no explicit enemy.
function getEnemyColor(playerColor)
    -- There should always be an attacker, the player who activated the system.
    local attackerColor = attacker()
    if not attackerColor then
        Util.debugLog('getEnemyColor: no attacker, aborting')
        return
    end

    -- There is not necessarily a defender if no other players in system.
    local defenderColor = defender(hex)
    Util.debugLog('attacker ' .. tostring(attackerColor) .. ', defender ' .. tostring(defenderColor))

    -- The enemy color is the defender if we are the attacker, or the attacker
    -- if we are not the attacker (remember there may not be a defender).
    if playerColor == attackerColor then
        -- May be nil!
        return defenderColor
    else
        return attackerColor
    end
end

--- Get cards relevant to the given player/enemy pair.
-- E.g., does the player have PDS2, does the enemy have AMD?
-- @param playerColor string.
-- @param enemyColor string.
-- @return table from card name to card object.
function getCombatSheetCards(playerColor, enemyColor)
    local result = {}
    local objects = Util.findObjectsByName({
        data.antimassDeflectorCard.name,
        data.pds2Card.name,
        data.plasmaScoringCard.name,
    })

    local amdCards = objects[data.antimassDeflectorCard.name]
    if amdCards then
        for _, obj in ipairs(amdCards) do
            if Util.playerHasCard(enemyColor, obj) then
                result[data.antimassDeflectorCard.name] = obj
                break
            end
        end
    end

    local pds2Cards = objects[data.pds2Card.name]
    if pds2Cards then
        for _, obj in ipairs(pds2Cards) do
            if Util.playerHasCard(playerColor, obj) then
                result[data.pds2Card.name] = obj
                break
            end
        end
    end

    local plasmaScoringCards = objects[data.plasmaScoringCard.name]
    if plasmaScoringCards then
        for _, obj in ipairs(plasmaScoringCards) do
            if Util.playerHasCard(playerColor, obj) then
                result[data.plasmaScoringCard.name] = obj
                break
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
function getCombatSheetValues(playerColor, enemyColor, cards)
    hex = data.lastActivatedHex
    if not hex then
        Util.debugLog('getCombatSheetValues: no hex, aborting')
        return
    end

    Util.maybePrintToTable('filling for ' .. (playerColor or '?') .. ' attacking ' .. (enemyColor or '?'), playerColor)
    if data.maybePrintToTable then
        local pos = getHexPosition(hex)
        Player[playerColor].pingTable(pos)
    end

    local neighbors = getNeighborHexes(hex)
    local wormholeNeighbors = getWormholeNeighborHexes(hex)
    local allNeighbors = {}

    -- Optionally show the activated system in red, local neighbors green,
    -- and wormhole-adjacent in blue.
    if data.debugVisualize then
        local vectors = {}
        for _, neighbor in ipairs(wormholeNeighbors) do
            table.insert(vectors, getHexVectorLines(neighbor, {color={0,0,1,0.7},thickness=0.33}))
        end
        for _, neighbor in ipairs(neighbors) do
            table.insert(vectors, getHexVectorLines(neighbor, {color={0,1,0,0.7},thickness=0.66}))
        end
        table.insert(vectors, getHexVectorLines(hex, {color={1,0,0,0.7},thickness=1}))
        Global.setVectorLines(vectors)
    end

    for _, neighborHex in ipairs(neighbors) do
        table.insert(allNeighbors, neighborHex)
    end
    for _, neighborHex in ipairs(wormholeNeighbors) do
        table.insert(allNeighbors, neighborHex)
    end
    allNeighbors = getUniqueHexes(allNeighbors)

    local myLocalUnits = getUnitsInHex(playerColor, hex)
    local myNeighborUnits = getUnitsInHexes(playerColor, allNeighbors)

    -- Get units in system.
    local result = {}
    local msg = ''
    for unitName, unitObjects in pairs(myLocalUnits) do
        result[unitName] = #unitObjects
        if msg ~= '' then
            msg = msg .. ', '
        end
        msg = msg .. result[unitName] .. ' ' .. unitName
    end
    if msg ~= '' then
        Util.maybePrintToTable('I see ' .. msg, playerColor)
    end

    -- If PDS2, get pds in adjacent systems.
    Util.debugLogTable('neighbor units', myNeighborUnits)
    if cards[data.pds2Card.name] and myNeighborUnits['PDS'] then
        local count = #myNeighborUnits['PDS']
        Util.maybePrintToTable('I see PDS2 with ' .. count .. ' adjacent PDS', playerColor)
        result['PDS'] = (result['PDS'] or 0) + count
    end

    -- If Xxcha flagship, count as extra pds.
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
        if obj.getName() == data.pdsFlagship.name then
            Util.maybePrintToTable('I see ' .. obj.getName() .. ' for ' .. data.pdsFlagship.pdsCount .. ' extra PDS', playerColor)
            result['PDS'] = (result['PDS'] or 0) + data.pdsFlagship.pdsCount
        end
    end

    -- If Winnu flagship, value is number of non-fighter enemies.
    local winnuFlagship = false
    if myLocalFlagships then
        for _, obj in ipairs(myLocalFlagships) do
            if obj.getName() == data.winnuFlagship.name then
                winnuFlagship = true
                break
            end
        end
    end
    if winnuFlagship then
        local enemyLocalUnits = getUnitsInHex(enemyColor, hex)
        local count = 0
        for unitName, unitObjects in pairs(enemyLocalUnits) do
            if data.unitNamesNonFighters[unitName] then
                count = count + #unitObjects
            end
        end
        Util.maybePrintToTable('I see ' .. data.winnuFlagship.name .. ' with ' .. count .. ' dice', playerColor)
        result['Flagship'] = count
    end

    return result
end

function fillMultiRoller(playerColor, cards, units)
    local multiRoller = nil
    for _, obj in ipairs(getAllObjects()) do
        if string.find(obj.getName(), 'TI4 MultiRoller') and Util.getClosestPlayer(obj).color == playerColor then
            multiRoller = obj
            break
        end
    end
    if not multiRoller then
        Util.debugLog('no multiroller')
        return
    end

    multiRoller.call('resetCounters')

    for unitName, quantity in pairs(units) do
        local inputLabel = 'UNIT:' .. unitName
        local found = false
        for _, input in ipairs(multiRoller.getInputs()) do
            if input.label == inputLabel then
                multiRoller.editInput({ index = input.index, value = quantity })
                found = true
                break
            end
        end
        if not found then
            print('Warning: no input ' .. inputLabel)
        end
    end

    if cards[data.antimassDeflectorCard.name] then
        multiRoller.call('clickAMD')
    end

    multiRoller.call('updateButton', { multiRoller, playerColor })
end

function fillMultiRollerForClosestPlayer(obj, playerClickerColor, altClick)
    local playerColor = Util.getClosestPlayer(obj.getPosition()).color
    local enemyColor = getEnemyColor(playerColor, hex)
    Util.debugLog('playerColor=' .. playerColor .. ' enemyColor=' .. tostring(enemyColor or false))
    local cards = getCombatSheetCards(playerColor, enemyColor)
    Util.debugLogTable('cards', cards)
    local units = getCombatSheetValues(playerColor, enemyColor, cards)
    Util.debugLogTable('units', units)
    fillMultiRoller(playerColor, cards, units)
end

-------------------------------------------------------------------------------

function onLoad(save_state)
    print('onLoad')
    self.createButton({
        click_function = 'fillMultiRollerForPlayer',
        function_owner = self,
        label = 'XXX',
        width = 600,
        height = 400,
    })
    self.interactable = true
end

function onObjectPickUp(playerColor, pickedUpObject)
    if not isTracked(pickedUpObject) then
        return
    end
    local guid = pickedUpObject.getGUID()
    local hexString = tostring(getHex(pickedUpObject.getPosition()))
    local unitsSet = data.unitsInHex[hexString]
    if unitsSet then
        unitsSet[guid] = nil
    end
    Util.debugLog('onObjectPickUp: removed ' .. tostring(guid) .. ' from ' .. tostring(hexString))
end

function onObjectDrop(playerColor, droppedObject)
    if playerColor == Turns.turn_color and string.find(droppedObject.getName(), ' Command Token') and Util.isInTilesZone(droppedObject.getPosition()) then
        Util.debugLog('onObjectDrop: activated by ' .. playerColor)
        data.lastActivatedHex = getHex(droppedObject.getPosition())
        data.lastActivatedPlayerColor = playerColor
    end

    if not isTracked(droppedObject) then
        return
    end
    local guid = droppedObject.getGUID()
    local hex = getHex(droppedObject.getPosition())
    local hexString = tostring(hex)
    local unitsSet = data.unitsInHex[hexString]
    if not unitsSet then
        unitsSet = {}
        data.unitsInHex[hexString] = unitsSet
    end
    unitsSet[guid] = true
    Util.debugLog('onObjectDrop: added ' .. tostring(guid) .. ' to ' .. tostring(hexString))
end

function onPickUp(playerColor)
    -- body...
end

function onDrop(playerColor)
    print 'xxx'
    fillMultiRollerForClosestPlayer(self, playerColor, false)
end
