-- FlipScan: Settings UI Panel
-- Registers a panel under Interface > AddOns using the retail 10.x+ Settings API.

local FlipScan = FlipScan

function FlipScan.SettingsPanel:Init()
    -- The Settings API was introduced in Dragonflight (10.0). Guard against
    -- older clients or private servers that lack it.
    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        FlipScan:Debug("Settings API not available — skipping panel registration.")
        return
    end

    local panel = self:CreatePanel()
    if panel then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "FlipScan")
        category.ID = "FlipScan"
        Settings.RegisterAddOnCategory(category)
        FlipScan:Debug("Settings panel registered.")
    end
end

--- Build the options panel frame and its controls.
function FlipScan.SettingsPanel:CreatePanel()
    local panel = CreateFrame("Frame", "FlipScanSettingsPanel")
    panel.name = "FlipScan"

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("FlipScan v" .. FlipScan.version)

    -- Subtitle
    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Auction House flip profitability scanner. Auctioneer companion.")

    local yOffset = -70  -- Running vertical offset for controls

    ---------------------------------------------------------------
    -- Checkbox: Enable FlipScan
    ---------------------------------------------------------------
    local enableCB = self:CreateCheckbox(
        panel, "Enable FlipScan", yOffset,
        function() return FlipScan.Config:Get("enabled") end,
        function(value)
            FlipScan.Config:Set("enabled", value)
            if not value and FlipScan.Overlay and FlipScan.Overlay.HideAll then
                FlipScan.Overlay:HideAll()
            end
        end
    )
    yOffset = yOffset - 30

    ---------------------------------------------------------------
    -- Checkbox: Show tooltip detail
    ---------------------------------------------------------------
    local tooltipCB = self:CreateCheckbox(
        panel, "Show tooltip detail", yOffset,
        function() return FlipScan.Config:Get("showTooltipDetail") end,
        function(value) FlipScan.Config:Set("showTooltipDetail", value) end
    )
    yOffset = yOffset - 40

    ---------------------------------------------------------------
    -- Slider: Minimum margin %
    ---------------------------------------------------------------
    local marginSlider = self:CreateSlider(
        panel, "Minimum Profit Margin (%)", yOffset,
        0, 50, 1,
        function() return FlipScan.Config:Get("minMarginPercent") end,
        function(value) FlipScan.Config:Set("minMarginPercent", value) end
    )
    yOffset = yOffset - 60

    ---------------------------------------------------------------
    -- Reset to Defaults button
    ---------------------------------------------------------------
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 24)
    resetBtn:SetPoint("TOPLEFT", 16, yOffset)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetScript("OnClick", function()
        FlipScan.Config:ResetToDefaults()
        -- Refresh controls to show default values
        enableCB:SetChecked(FlipScan.Config:Get("enabled"))
        tooltipCB:SetChecked(FlipScan.Config:Get("showTooltipDetail"))
        marginSlider:SetValue(FlipScan.Config:Get("minMarginPercent"))
    end)

    -- Refresh controls when the panel is shown
    panel:SetScript("OnShow", function()
        enableCB:SetChecked(FlipScan.Config:Get("enabled"))
        tooltipCB:SetChecked(FlipScan.Config:Get("showTooltipDetail"))
        marginSlider:SetValue(FlipScan.Config:Get("minMarginPercent"))
    end)

    return panel
end

-----------------------------------------------------------------------
-- Widget helpers
-----------------------------------------------------------------------

--- Create a labeled checkbox.
function FlipScan.SettingsPanel:CreateCheckbox(parent, label, yOffset, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, yOffset)
    cb.Text:SetText(label)
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(widget)
        setter(widget:GetChecked())
    end)
    return cb
end

--- Create a labeled slider with value display.
function FlipScan.SettingsPanel:CreateSlider(parent, label, yOffset, minVal, maxVal, step, getter, setter)
    local slider = CreateFrame("Slider", "FlipScanMarginSlider", parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 20, yOffset)
    slider:SetSize(200, 17)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(getter())

    slider.Text:SetText(label)
    slider.Low:SetText(minVal .. "%")
    slider.High:SetText(maxVal .. "%")

    -- Value label next to the slider
    local valueText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valueText:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    valueText:SetText(getter() .. "%")

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)  -- Round to integer
        setter(value)
        valueText:SetText(value .. "%")
    end)

    return slider
end
