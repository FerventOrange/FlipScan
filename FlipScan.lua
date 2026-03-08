-- FlipScan: AH Flip Profitability Scanner
-- Companion addon for Auctioneer that highlights profitable flip opportunities.

-- Global addon namespace
FlipScan = FlipScan or {}
FlipScan.version = "0.1.0"

-- Sub-namespaces for each module
FlipScan.Config = {}
FlipScan.Calculator = {}
FlipScan.Overlay = {}
FlipScan.Hooks = {}
FlipScan.Commands = {}

-- Debug state (toggled at runtime, not persisted)
FlipScan.debugMode = false

-- Addon event frame
local eventFrame = CreateFrame("Frame", "FlipScanEventFrame")
FlipScan.eventFrame = eventFrame

eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "FlipScan" then
            FlipScan:OnAddonLoaded()
            self:UnregisterEvent("ADDON_LOADED")
        end
    end
end)

--- Called once when FlipScan finishes loading.
function FlipScan:OnAddonLoaded()
    -- Initialize SavedVariables / config (Goal 2)
    if self.Config.Init then
        self.Config:Init()
    end

    -- Register slash commands (Goal 7)
    if self.Commands.Init then
        self.Commands:Init()
    end

    -- Register settings panel (Goal 8)
    if self.SettingsPanel and self.SettingsPanel.Init then
        self.SettingsPanel:Init()
    end

    -- Hook into Auctioneer (Goal 4)
    if self.Hooks.Init then
        self.Hooks:Init()
    end

    -- Initialize overlay system (Goal 5)
    if self.Overlay.Init then
        self.Overlay:Init()
    end

    -- Initialize tooltip injection (Goal 6)
    if self.Tooltip and self.Tooltip.Init then
        self.Tooltip:Init()
    end

    self:Print("v" .. self.version .. " loaded.")
end

--- Print a message to chat prefixed with the addon name.
function FlipScan:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00CCFF[FlipScan]|r " .. tostring(msg))
end

--- Print a debug message (only when debug mode is on).
function FlipScan:Debug(msg)
    if self.debugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF888888[FlipScan Debug]|r " .. tostring(msg))
    end
end
