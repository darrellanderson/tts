--- Active/passed token.
-- @author bonkersbgg at boardgamegeek.com
--
-- Place one token near each player, each token assigns itself to the closest
-- seated player.
--
-- When flipped to "passed" the token will automatically skip that player's
-- turn, broadcasting to all players that player has passed.
--
-- Once all players have passed, the token disables turns (via Turns.enable).
-- When turns get re-enabled, tokens flip back to "active" (if not already).

local data = {
    -- Verbose logging (boolean).
    enableDebugLogging = false,

    -- This token belongs to which seated player (string).
    ownerPlayerColor = nil,

    -- Reset when turns get enabled again (boolean).
    needsReset = false,
}

-------------------------------------------------------------------------------
-- OBJECT EVENT METHODS

function onLoad()
    debugLog('onLoad')
    resetTokenForNewOwner()
end

function onDrop(player_color)
    resetTokenForNewOwner()
end

function onPlayerChangeColor(player_color)
    resetTokenForNewOwner()
end

function onPlayerTurnStart(player_color_start, player_color_previous)
    debugLog('onPlayerTurnStart ' .. player_color_start)

    -- Reset to active when starting a new turn after all players have passed.
    if maybeReset() then
        -- We reset ourselves to active, proceed with the current turn.
        -- (NB: this also avoids a race with self.is_face_down being false
        -- while object flip is in progress.)
        return
    end

    -- Do not manipulate any Turns state now, let all objects process the
    -- same turn start values and maybe pass the turn after a few frames.
    if isMyTurn() then
        Wait.frames(maybePassTurn, 2)
    end
end

-------------------------------------------------------------------------------

--- Get all Active/Passed tokens on the board.
-- @param includeSelf boolean include this object too?
-- @return table list of objects
function getPeers(includeSelf)
    local script = self.getLuaScript()
    local result = {}
    for _, object in ipairs(getAllObjects()) do
        if object.getLuaScript() == script and (object ~= self or includeSelf) then
            result[#result + 1] = object
        end
    end
    debugLog('getPeers: found ' .. #result .. ' peers')
    return result
end

--- Make sure each player is in the list without repeats.
-- @return boolean true if all players have one token.
function sanityCheckPeersWithIncludeSelf(peers)
    local result = true
    local colorCount = {}
    for _, peer in ipairs(peers) do
        local color = peer.call('getOwnerPlayerColor')
        colorCount[color] = (colorCount[color] or 0) + 1
    end
    for color, count in pairs(colorCount) do
        if count > 1 then
            result = false
            local player = Player[color]
            local name = (player and player.steam_name) or color
            broadcastToAll('Warning: player ' .. name .. ' has multiple active/passed tokens', color)
        end
    end
    for _, color in ipairs(getSeatedPlayers()) do
        if not colorCount[color] then
            result = false
            local player = Player[color]
            local name = (player and player.steam_name) or color
            broadcastToAll('Warning: player ' .. name .. ' does not have an active/passed token', color)
        end
    end
    return result
end

--- Player associated with this token.
function getOwnerPlayerColor()
    return data.ownerPlayerColor
end

--- Is this token showing "active"?
-- @return boolean true if active.
function isActive()
    local result = not self.is_face_down
    debugLog('isActive -> ' .. tostring(result))
    return result
end

--- Is any active/passed token still active?
-- @param peers list of active/passed token objects.
-- @return boolean true if any is active.
function anyPeerIsActive(peers)
    local result = false
    for _, peer in ipairs(peers) do
        if peer.call('isActive') then
            result = true
            break
        end
    end
    debugLog('anyPeerActive -> ' .. tostring(result))
    return result
end

--- Mark this object as needing to be reset when turns get enabled.
function setNeedsReset()
    data.needsReset = true
end

-- Mark peers as needing to be reset when turns get enabled.
-- @param peers list of active/passed token objects.
function setPeersNeedsReset(peers)
    for _, peer in ipairs(peers) do
        peer.call('setNeedsReset')
    end
end

--- Is the current turn the player who owns this token?
-- @return boolean true if my turn.
function isMyTurn()
    local result = Turns.enable and Turns.turn_color == data.ownerPlayerColor
    debugLog('isMyTurn -> ' .. tostring(result))
    return result
end

-------------------------------------------------------------------------------

--- Assign this to the closest seated player.
-- Also tints the side of the token for a visual confirmation.
function resetTokenForNewOwner()
    local player = getClosestPlayer(self.getPosition())
    local newOwnerPlayerColor = player and player.color
    if newOwnerPlayerColor == data.ownerPlayerColor then
        return
    end

    debugLog('resetTokenForNewOwner ' .. tostring(newOwnerPlayerColor))
    data.ownerPlayerColor = newOwnerPlayerColor
    if data.ownerPlayerColor then
        self.setColorTint(data.ownerPlayerColor)
    end
end

--- Reset to active if needs reset when starting a new turn.
-- @return boolean true if reset happened.
function maybeReset()
    if not Turns.enable or not data.needsReset then
        return false
    end

    data.needsReset = false
    if self.is_face_down then
        self.flip()
    end
    return true
end

--- Pass turn if this token is set to "passed".  If all tokens are set to
-- "passed" then disable turns altogether, requiring turns be re-enabled
-- via some external means to proceed.
-- @return boolean true if passed turn.
function maybePassTurn()
    -- Out of paranoia make sure it is still this token owner's turn.
    -- It is possible some other script changed turns while this function
    -- was waiting to be called, or in some cases such as hot-seat games
    -- it appears TTS calls onPlayerTurnStart twice each turn.
    if not isMyTurn() then
        debugLog('maybePassTurn: not my turn, aborting')
        return false
    end

    -- Make sure everyone has exactly one active/passed token.
    local peers = getPeers(true)
    local sanityCheck = sanityCheckPeersWithIncludeSelf(peers)

    -- Do nothing if still active (play normally).
    if isActive() then
        debugLog('maybePassTurn: still active, aborting')
        return false
    end

    -- At this point we know it is "my" turn and the token is set to "passed".
    -- Pass this turn, or if all players have passed disable turns altogether.
    -- (Requires external event to re-enable turns.)
    -- Note: if the sanity check failed then there is not one token per player.
    -- In that case, continue to pass turns but do not consider "all" passed.
    if anyPeerIsActive(peers) or not sanityCheck then
        debugLog('maybePassTurn: at least one active peer, passing turn')
        local player = Player[data.ownerPlayerColor]f
        local name = (player and player.steam_name) or data.ownerPlayerColor
        broadcastToAll('Player ' .. name .. ' passed.', data.ownerPlayerColor)
        Turns.turn_color = Turns.getNextTurnColor()
    else
        debugLog('maybePassTurn: no active peers, disabling turns')
        broadcastToAll('All players have passed.', data.ownerPlayerColor)
        setPeersNeedsReset(peers)
        Turns.enable = false
    end
    return true
end

-------------------------------------------------------------------------------
-- GENERIC UTILITY FUNCTIONS

--- Print a statement to the console, with an on/off setting.
-- @param string debug message.
function debugLog(string)
    if not data.enableDebugLogging then
        return
    end
    print(string)
end

--- Find the seated player closest to the given position.
-- @param position table with {x, y, z} keys.
-- @return Player.
function getClosestPlayer(position)
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
