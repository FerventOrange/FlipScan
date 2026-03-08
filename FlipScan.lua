-- FlipScan: AH Flip Profitability Scanner
-- Highlights profitable flip opportunities on AH listings.
-- Works with Auctionator or standalone (vendor prices only).

-- Global addon namespace
FlipScan = FlipScan or {}
FlipScan.version = "0.3.0"

-- Sub-namespaces for each module
FlipScan.Config = {}
FlipScan.Calculator = {}
FlipScan.Overlay = {}
FlipScan.Hooks = {}
FlipScan.Commands = {}
FlipScan.Tooltip = {}
FlipScan.SettingsPanel = {}

-- Debug state (toggled at runtime, not persisted)
FlipScan.debugMode = false

-- Track whether Auctionator is present
FlipScan.hasAuctionator = false

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

--- Safely call a function, catching any errors. Logs failures in debug mode.
-- @param description (string) Human-readable label for what we're initializing.
-- @param func        (function) The function to call.
-- @return success    (boolean)
local function SafeInit(description, func)
    local ok, err = pcall(func)
    if not ok then
        FlipScan:Print("Warning: " .. description .. " failed to initialize.")
        FlipScan:Debug(description .. " error: " .. tostring(err))
    end
    return ok
end

--- Called once when FlipScan finishes loading.
function FlipScan:OnAddonLoaded()
    -- Detect Auctionator
    self.hasAuctionator = (Auctionator ~= nil)

    -- Initialize SavedVariables / config
    SafeInit("Config", function()
        if self.Config.Init then self.Config:Init() end
    end)

    -- Register slash commands
    SafeInit("Commands", function()
        if self.Commands.Init then self.Commands:Init() end
    end)

    -- Register settings panel
    SafeInit("SettingsPanel", function()
        if self.SettingsPanel and self.SettingsPanel.Init then
            self.SettingsPanel:Init()
        end
    end)

    -- Hook into Auctioneer or Blizzard AH
    SafeInit("Hooks", function()
        if self.Hooks.Init then self.Hooks:Init() end
    end)

    -- Initialize overlay system
    SafeInit("Overlay", function()
        if self.Overlay.Init then self.Overlay:Init() end
    end)

    -- Initialize tooltip injection
    SafeInit("Tooltip", function()
        if self.Tooltip and self.Tooltip.Init then self.Tooltip:Init() end
    end)

    -- Report load status
    if self.hasAuctionator then
        self:Print("v" .. self.version .. " loaded. Price source: Auctionator")
    else
        self:Print("v" .. self.version .. " loaded (standalone mode — vendor prices only).")
    end
end

--- Print a message to chat prefixed with the addon name.
function FlipScan:Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00CCFF[FlipScan]|r " .. tostring(msg))
    end
end

--- Print a debug message (only when debug mode is on).
function FlipScan:Debug(msg)
    if self.debugMode and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF888888[FlipScan Debug]|r " .. tostring(msg))
    end
end
