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
-- When turns get re-enabled, each token flips back to "active".

local data = {
    -- Verbose logging (boolean).
    enableDebugLogging = true,

    -- This token belongs to which seated player (string).
    ownerPlayerColor = nil,

    -- Reset when turns get enabled again?
    needsReset = false,
}

-------------------------------------------------------------------------------

-------------------------------------------------------------------------------

--- Is this token showing "active"?
-- @return boolean
function isActive()
    return not self.is_face_down
end

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

--- Mark this object as needing to be reset when turns get enabled.
function setNeedsReset()
    data.needsReset = true
end

-------------------------------------------------------------------------------

function onLoad()
    debugLog('onLoad')
    resetTokenForNewOwner()
end

function onDrop(player_color)
    debugLog('onObjectDrop ' .. player_color)
    resetTokenForNewOwner()
end

--[[
function onPlayerChangeColor(player_color)
    debugLog('onPlayerChangeColor ' .. player_color)
    resetTokenForNewOwner()
end
--]]

-------------------------------------------------------------------------------

function onPlayerTurnStart(player_color_start, player_color_previous)
    debugLog('onPlayerTurnStart ' .. player_color_start .. ' prev=' .. player_color_previous)

    if not data.ownerPlayerColor then
        debugLog('onPlayerTurnStart: no owner player color, aborting')
        return
    end
    if not Turns.enable then
        debugLog('onPlayerTurnStart: turns not enabled, aborting')
        return
    end

    -- If this token needs reset, flip it back to active.  This happens
    -- the first time a turn starts after have been previously disabled.
    -- Do this immediately regardless of which turn this is.
    local active = isActive()
    if data.needsReset then
        data.needsReset = false
        if not active then
            self.flip()
            active = true
        end
    end

    -- At this point only act on behalf of the player who owns this token.
    -- Abort if the new turn is for some other player.
    if player_color_start ~= data.ownerPlayerColor then
        debugLog('onPlayerTurnStart: not owner color (' .. data.ownerPlayerColor .. '), aborting')
        return
    end

    -- Abort if still active; play and end the turn normally!
    if active then
        debugLog('onPlayerTurnStart: still active, aborting')
        return
    end

    -- This object is owned by the current player, and is flipped to pass.
    -- Tell the table we're passing
    local player = Player[data.ownerPlayerColor]
    broadcastToAll('Player ' .. player.steam_name .. ' passed.', data.ownerPlayerColor)

    -- If at least one player is still active, move on to the next turn.
    -- If all players have passed, disable turns.
    local peersIncludingSelf = getPeers(true)
    local anyActive = active
    for _, peer in ipairs(peersIncludingSelf) do
        if peer.call('isActive') then
            anyActive = true
            break
        end
    end

    if anyActive then
        -- Wait to change turns so the current change finishes first.
        Wait.frames(advanceToNextTurn, 2)
    else
        broadcastToAll('All players have passed.', data.ownerPlayerColor)
        Turns.enable = false
        for _, peer in ipairs(peersIncludingSelf) do
            peer.call('setNeedsReset')
        end
    end
end

function advanceToNextTurn()
    Turns.turn_color = Turns.getNextTurnColor()
end

-------------------------------------------------------------------------------

--- Assign this to the closest seated player.
-- Also tints the side of the token for a visual confirmation.
function resetTokenForNewOwner()
    data.ownerPlayerColor = getClosestPlayerColor(self.getPosition())
    debugLog('resetTokenForNewOwner ' .. tostring(data.ownerPlayerColor))

    if data.ownerPlayerColor then
        -- Color the sides of the token to match the owner.
        self.setColorTint(data.ownerPlayerColor)
        rotateToMatchPlayerHand(self, data.ownerPlayerColor)
    end
end

-------------------------------------------------------------------------------
-- UTILITY METHODS.  Functions below this line should not reference self.

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
-- @return string player color.
function getClosestPlayerColor(position)
    local bestPlayerColor = nil
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
                bestPlayerColor = player.color
                bestDistanceSq = distanceSq
            end
        end
    end
    return bestPlayerColor
end

--- Rotate so token text aligns with the owning player's hand.
-- Signals if token is not assigned to the expected player.
-- @param object to rotate
-- @param string playerColor to align with hand
function rotateToMatchPlayerHand(object, playerColor)
    -- Only rotate y, preserve flipped state.
    local rotation = Player[playerColor].getHandTransform(1).rotation
    rotation.x = object.getRotation().x
    rotation.y = (rotation.y + 180) % 360
    rotation.z = object.getRotation().z
    object.setRotationSmooth(rotation, false, false)
end
