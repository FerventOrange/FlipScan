-- FlipScan: Slash Command Interface
-- /flipscan command handler for runtime control.

local FlipScan = FlipScan

--- Initialize slash command registration.
function FlipScan.Commands:Init()
    SLASH_FLIPSCAN1 = "/flipscan"  -- Must be global for WoW slash command registration
    SLASH_FLIPSCAN2 = "/fs"       -- Must be global for WoW slash command registration
    SlashCmdList["FLIPSCAN"] = function(msg)
        FlipScan.Commands:Handle(msg)
    end
    FlipScan:Debug("Slash commands registered: /flipscan, /fs")
end

--- Extract an item link from a raw message string.
-- Item links contain pipe characters and mixed case, so they must be
-- extracted from the original (non-lowercased) message.
-- @param msg (string) The raw slash command message.
-- @return (string|nil) The item link, or nil.
local function ExtractItemLinkFromMsg(msg)
    if not msg then return nil end
    return msg:match("|c%x+|Hitem:.-|h%[.-%]|h|r")
end

--- Extract an item ID from an item link string.
-- @param itemLink (string) A WoW item link.
-- @return (number|nil) The item ID.
local function ExtractItemIDFromLink(itemLink)
    if not itemLink then return nil end
    local id = itemLink:match("item:(%d+)")
    return id and tonumber(id) or nil
end

--- Extract the item name from an item link string.
-- @param itemLink (string) A WoW item link.
-- @return (string|nil) The item name.
local function ExtractItemNameFromLink(itemLink)
    if not itemLink then return nil end
    return itemLink:match("%[(.-)%]")
end

--- Parse and dispatch a slash command.
-- @param msg (string) Everything after "/flipscan ", e.g. "margin 10"
function FlipScan.Commands:Handle(msg)
    local args = {}
    for word in (msg or ""):gmatch("%S+") do
        args[#args + 1] = word:lower()
    end

    local cmd = args[1]

    if not cmd or cmd == "" then
        self:PrintStatus()

    elseif cmd == "on" then
        FlipScan.Config:Set("enabled", true)
        FlipScan:Print("Enabled.")

    elseif cmd == "off" then
        FlipScan.Config:Set("enabled", false)
        FlipScan:Print("Disabled.")
        if FlipScan.Overlay and FlipScan.Overlay.HideAll then
            FlipScan.Overlay:HideAll()
        end

    elseif cmd == "margin" then
        local value = tonumber(args[2])
        if not value then
            FlipScan:Print("Usage: /flipscan margin <number>  (e.g. /flipscan margin 10)")
            FlipScan:Print("Current minimum margin: " .. FlipScan.Config:Get("minMarginPercent") .. "%")
            return
        end
        if value < 0 or value > 100 then
            FlipScan:Print("Margin must be between 0 and 100.")
            return
        end
        FlipScan.Config:Set("minMarginPercent", value)
        FlipScan:Print("Minimum margin set to " .. value .. "%.")

    elseif cmd == "tooltip" then
        local current = FlipScan.Config:Get("showTooltipDetail")
        FlipScan.Config:Set("showTooltipDetail", not current)
        if not current then
            FlipScan:Print("Tooltip detail enabled.")
        else
            FlipScan:Print("Tooltip detail disabled.")
        end

    elseif cmd == "ignore" then
        self:HandleIgnore(msg)

    elseif cmd == "unignore" then
        self:HandleUnignore(msg)

    elseif cmd == "ignorelist" then
        self:HandleIgnoreList()

    elseif cmd == "reset" then
        FlipScan.Config:ResetToDefaults()

    elseif cmd == "help" then
        self:PrintUsage()

    elseif cmd == "debug" then
        FlipScan.debugMode = not FlipScan.debugMode
        if FlipScan.debugMode then
            FlipScan:Print("Debug mode ON.")
        else
            FlipScan:Print("Debug mode OFF.")
        end

    else
        FlipScan:Print("Unknown command: " .. tostring(cmd))
        self:PrintUsage()
    end
end

--- Add an item to the ignore list.
-- @param msg (string) Raw slash command message containing an item link.
function FlipScan.Commands:HandleIgnore(msg)
    local itemLink = ExtractItemLinkFromMsg(msg)
    if not itemLink then
        FlipScan:Print("Usage: /flipscan ignore [Item Link]  (shift-click an item)")
        return
    end

    local itemID = ExtractItemIDFromLink(itemLink)
    if not itemID then
        FlipScan:Print("Could not extract item ID from link.")
        return
    end

    local itemName = ExtractItemNameFromLink(itemLink) or tostring(itemID)
    local ignoredItems = FlipScan.Config:Get("ignoredItems") or {}
    ignoredItems[itemID] = itemName
    FlipScan.Config:Set("ignoredItems", ignoredItems)
    FlipScan:Print("Ignoring " .. itemLink .. ".")
end

--- Remove an item from the ignore list.
-- @param msg (string) Raw slash command message containing an item link.
function FlipScan.Commands:HandleUnignore(msg)
    local itemLink = ExtractItemLinkFromMsg(msg)
    if not itemLink then
        FlipScan:Print("Usage: /flipscan unignore [Item Link]  (shift-click an item)")
        return
    end

    local itemID = ExtractItemIDFromLink(itemLink)
    if not itemID then
        FlipScan:Print("Could not extract item ID from link.")
        return
    end

    local ignoredItems = FlipScan.Config:Get("ignoredItems") or {}
    if not ignoredItems[itemID] then
        FlipScan:Print(itemLink .. " is not on the ignore list.")
        return
    end

    ignoredItems[itemID] = nil
    FlipScan.Config:Set("ignoredItems", ignoredItems)
    FlipScan:Print("No longer ignoring " .. itemLink .. ".")
end

--- Print all items on the ignore list.
function FlipScan.Commands:HandleIgnoreList()
    local ignoredItems = FlipScan.Config:Get("ignoredItems") or {}
    local count = 0
    for _ in pairs(ignoredItems) do count = count + 1 end

    if count == 0 then
        FlipScan:Print("Ignore list is empty.")
        return
    end

    FlipScan:Print("Ignored items (" .. count .. "):")
    for itemID, itemName in pairs(ignoredItems) do
        FlipScan:Print("  " .. itemName .. " (ID: " .. itemID .. ")")
    end
end

--- Print current status summary.
function FlipScan.Commands:PrintStatus()
    local ignoredItems = FlipScan.Config:Get("ignoredItems") or {}
    local ignoreCount = 0
    for _ in pairs(ignoredItems) do ignoreCount = ignoreCount + 1 end

    FlipScan:Print("v" .. FlipScan.version .. " Status:")
    FlipScan:Print("  Enabled: " .. tostring(FlipScan.Config:Get("enabled")))
    FlipScan:Print("  Min Margin: " .. FlipScan.Config:Get("minMarginPercent") .. "%")
    FlipScan:Print("  Marginal Margin: " .. FlipScan.Config:Get("marginalMarginPercent") .. "%")
    FlipScan:Print("  Tooltip Detail: " .. tostring(FlipScan.Config:Get("showTooltipDetail")))
    FlipScan:Print("  Ignored Items: " .. ignoreCount)
    FlipScan:Print("  Debug Mode: " .. tostring(FlipScan.debugMode))
    FlipScan:Print("  Active Overlays: " .. (FlipScan.Overlay.GetActiveCount and FlipScan.Overlay:GetActiveCount() or 0))
    FlipScan:Print("Type /flipscan help for commands.")
end

--- Print available commands.
function FlipScan.Commands:PrintUsage()
    FlipScan:Print("Commands:")
    FlipScan:Print("  /flipscan              - Show status")
    FlipScan:Print("  /flipscan on           - Enable FlipScan")
    FlipScan:Print("  /flipscan off          - Disable FlipScan")
    FlipScan:Print("  /flipscan margin #     - Set min profit margin %")
    FlipScan:Print("  /flipscan tooltip      - Toggle tooltip detail")
    FlipScan:Print("  /flipscan ignore [Link]   - Ignore an item (shift-click)")
    FlipScan:Print("  /flipscan unignore [Link] - Stop ignoring an item")
    FlipScan:Print("  /flipscan ignorelist   - List ignored items")
    FlipScan:Print("  /flipscan reset        - Reset all settings")
    FlipScan:Print("  /flipscan debug        - Toggle debug output")
end
