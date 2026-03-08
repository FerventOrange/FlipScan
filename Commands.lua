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

--- Print current status summary.
function FlipScan.Commands:PrintStatus()
    FlipScan:Print("v" .. FlipScan.version .. " Status:")
    FlipScan:Print("  Enabled: " .. tostring(FlipScan.Config:Get("enabled")))
    FlipScan:Print("  Min Margin: " .. FlipScan.Config:Get("minMarginPercent") .. "%")
    FlipScan:Print("  Tooltip Detail: " .. tostring(FlipScan.Config:Get("showTooltipDetail")))
    FlipScan:Print("  Debug Mode: " .. tostring(FlipScan.debugMode))
    FlipScan:Print("  Active Overlays: " .. (FlipScan.Overlay.GetActiveCount and FlipScan.Overlay:GetActiveCount() or 0))
    FlipScan:Print("Type /flipscan help for commands.")
end

--- Print available commands.
function FlipScan.Commands:PrintUsage()
    FlipScan:Print("Commands:")
    FlipScan:Print("  /flipscan          - Show status")
    FlipScan:Print("  /flipscan on       - Enable FlipScan")
    FlipScan:Print("  /flipscan off      - Disable FlipScan")
    FlipScan:Print("  /flipscan margin # - Set min profit margin %")
    FlipScan:Print("  /flipscan tooltip  - Toggle tooltip detail")
    FlipScan:Print("  /flipscan reset    - Reset all settings")
    FlipScan:Print("  /flipscan debug    - Toggle debug output")
end
