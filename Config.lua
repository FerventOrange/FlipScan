-- FlipScan: Configuration & SavedVariables
-- Manages persistent settings with defaults merging on load.

local FlipScan = FlipScan

-- Default database values. Any key missing from the player's SavedVariables
-- will be filled in from this table on load.
local defaults = {
    minMarginPercent = 2.5,         -- Min net profit % after AH cut to flag as flippable
    minProfitGold = 0,              -- Min absolute profit in gold (0 = disabled)
    highlightColor = { r = 0, g = 1, b = 0, a = 0.4 },   -- Green tint for profitable flips
    noFlipColor    = { r = 1, g = 0, b = 0, a = 0.4 },    -- Red tint for money-losing flips
    showTooltipDetail = true,       -- Inject net profit breakdown into item tooltips
    enabled = true,                 -- Master on/off toggle
    maxPriceTiers = 50,             -- Cap price tiers to exclude outlier joke listings
    wallFractionPercent = 40,       -- A tier holding >X% of total supply in range is a wall
}

--- Deep-copy a table (one level deep; sufficient for our flat+color-table schema).
local function DeepCopyDefaults(src)
    local copy = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            copy[k] = {}
            for k2, v2 in pairs(v) do
                copy[k][k2] = v2
            end
        else
            copy[k] = v
        end
    end
    return copy
end

--- Merge defaults into an existing saved table. Adds any missing keys
--- without overwriting the player's existing values.
local function MergeDefaults(saved, defs)
    for k, v in pairs(defs) do
        if saved[k] == nil then
            -- Key is entirely missing — copy the default
            if type(v) == "table" then
                saved[k] = {}
                for k2, v2 in pairs(v) do
                    saved[k][k2] = v2
                end
            else
                saved[k] = v
            end
        elseif type(v) == "table" and type(saved[k]) == "table" then
            -- Sub-table exists — fill in any missing sub-keys (e.g. new color fields)
            for k2, v2 in pairs(v) do
                if saved[k][k2] == nil then
                    saved[k][k2] = v2
                end
            end
        end
    end
end

--- Initialize the config system. Called from FlipScan:OnAddonLoaded().
function FlipScan.Config:Init()
    -- FlipScanDB is the global SavedVariables table declared in the TOC.
    if type(FlipScanDB) ~= "table" then
        FlipScanDB = DeepCopyDefaults(defaults)
    else
        MergeDefaults(FlipScanDB, defaults)
    end

    FlipScan:Debug("Config initialized. minMarginPercent=" .. FlipScanDB.minMarginPercent)
end

--- Get a config value.
function FlipScan.Config:Get(key)
    if FlipScanDB then
        return FlipScanDB[key]
    end
    return defaults[key]
end

--- Set a config value and persist it.
function FlipScan.Config:Set(key, value)
    if not FlipScanDB then
        FlipScanDB = DeepCopyDefaults(defaults)
    end
    FlipScanDB[key] = value
end

--- Reset all settings to defaults.
function FlipScan.Config:ResetToDefaults()
    FlipScanDB = DeepCopyDefaults(defaults)
    FlipScan:Print("All settings reset to defaults.")
end

--- Return a copy of the defaults table (for display / comparison).
function FlipScan.Config:GetDefaults()
    return DeepCopyDefaults(defaults)
end
