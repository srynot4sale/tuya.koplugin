local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local CloseButton = require("ui/widget/closebutton")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FFIUtil = require("ffi/util")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local JSON = require("rapidjson")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Math = require("optmath")
local Notification = require("ui/widget/notification")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local Input = Device.input
local Screen = Device.screen
local _ = require("gettext")
local T = FFIUtil.template

local pycommand

local function getSourceDir()
    local callerSource = debug.getinfo(2, "S").source
    if callerSource:find("^@") then
        return callerSource:gsub("^@(.*)/[^/]*", "%1")
    end
end

local TuyaTitle = VerticalGroup:new{
    tuya_view = nil,
}

function TuyaTitle:init()
    self.close_button = CloseButton:new{ window = self }
    local btn_width = self.close_button:getSize().w
    self.text_w = CenterContainer:new{
        dimen = { w = self.width },
        ignore_if_over = height,
        TextWidget:new{
            text = "Tuya Devices",
            max_width = self.width - btn_width,
            face = Font:getFace("tfont"),
        },
    }
    table.insert(self, OverlapGroup:new{
        dimen = { w = self.width - btn_width},
        self.text_w,
        self.close_button,
    })
    table.insert(self, OverlapGroup:new{
        dimen = { w = self.width, h = Size.line.thick },
        LineWidget:new{
            dimen = Geom:new{ w = self.width, h = Size.line.thick },
            background = Blitbuffer.COLOR_BLACK,
            style = "solid",
        },
    })
end

function TuyaTitle:onClose()
    self.tuya_view:onClose()
    return true
end

local ShortcutBox = InputContainer:new{
    filler = false,
    width = nil,
    height = nil,
    border = 0,
    is_offline = false,
    font_face = "xx_smallinfofont",
    font_size = nil,
    sc = nil,
    device = nil,
}

function ShortcutBox:init()
    self.dimen = Geom:new{w = self.width, h = self.height}
    if self.filler then
        return
    end
    if Device:isTouchDevice() then
        self.ges_events.Tap = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        }
        self.ges_events.Hold = {
            GestureRange:new{
                ges = "hold",
                range = self.dimen,
            }
        }
    end

    local inner_w = self.width - 2*self.border
    local inner_h = self.height - 2*self.border
    local hg = HorizontalGroup:new{dimen = Geom:new{w = inner_w, h = inner_h},}

    if self.sc.bright then
        local bt = TextWidget:new{
            text = "B",
            face = Font:getFace(self.font_face, self.font_size),
            fgcolor = self.is_offline and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK,
        }
        local bv = TextWidget:new{
            text = tostring(self.sc.bright),
            face = Font:getFace(self.font_face, self.font_size),
            fgcolor = self.is_offline and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK,
        }

        table.insert(hg, VerticalGroup:new{
            dimen = Geom:new{w = bv:getWidth(), h = inner_h},
            bt,
            bv,
        })
    end
    table.insert(hg, HorizontalSpan:new{ width = Size.span.horizontal_default, })
    if self.sc.temp then
        table.insert(hg, VerticalGroup:new{
            dimen = Geom:new{w = inner_w, h = inner_h},
            TextWidget:new{
                text = "T",
                face = Font:getFace(self.font_face, self.font_size),
                fgcolor = self.is_offline and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK,
            },
            TextWidget:new{
                text = tostring(self.sc.temp),
                face = Font:getFace(self.font_face, self.font_size),
                fgcolor = self.is_offline and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK,
            },
        })
    end

    local bright_temp_w = CenterContainer:new{
        dimen = Geom:new{w = inner_w, h = inner_h},
        hg,
    }
    self[1] = FrameContainer:new{
        padding = 0,
        color = self.is_offline and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK,
        bordersize = self.border,
        width = self.width,
        height = self.height,
        bright_temp_w,
    }
end

function ShortcutBox:onTap()
    local wait_msg = InfoMessage:new{
        text = _("Executing…"),
    }
    UIManager:show(wait_msg)
    local command =  pycommand .. " " .. self.device.idx .. " " .. self.idx .. " 2>&1 ; echo" -- ensure we get stderr and output something
    local completed, result_str = Trapper:dismissablePopen(command, wait_msg)
require("logger").warn("@@@", command, result_str)
    UIManager:close(wait_msg)
    return true
end

function ShortcutBox:onHold()
    return self:onTap()
end


local TuyaDevice = InputContainer:new{
    device = nil,
    width = nil,
    height = nil,
    sc_width = 0,
    sc_padding = 0,
    sc_border = 0,
    font_size = 0,
    font_face = "xx_smallinfofont",
    is_offline = false,
}

function TuyaDevice:init()
    self.dimen = Geom:new{w = self.width, h = self.height}
    self.title = VerticalGroup:new{
        width = self.width,
        height = Size.item.height_default,
    }

    self.text_w = UnderlineContainer:new{
        color = Blitbuffer.COLOR_BLACK,
        padding = 0,
        TextWidget:new{
            text = self.device.name,
            max_width = self.width, --status width
            face = Font:getFace(self.font_face, self.font_size),
        },
    }
    table.insert(self.title, CenterContainer:new{
        dimen = { w = self.width },
        self.text_w,
        --self.close_button,
    })

    self.shortcut_container = HorizontalGroup:new{
        dimen = Geom:new{w = self.width, h = self.height - self.title.height}
    }

    --local manual = 
    --table.insert(self.shortcut_container, manual)
    --table.insert(self.shortcut_container, HorizontalSpan:new{ width = self.sc_padding, })
    
    for num, v in ipairs(self.device.shortcuts) do
        local SB = ShortcutBox:new{
            width = self.sc_width,
            height = self.height - self.title.height,
            border = self.sc_border,
            is_offline = self.is_offline,
            font_face = self.fontface,
            font_size = self.fontsize,
            sc = v,
            device = self.device,
            idx = num-1, -- Python indexes from 0
        }
        table.insert(self.shortcut_container, SB)
        if num < #self.device.shortcuts then
            table.insert(self.shortcut_container, HorizontalSpan:new{ width = self.sc_padding, })
        end
    end

    local overlaps = VerticalGroup:new{
        self.title,
        VerticalSpan:new{ width = Size.span.vertical_default },
        self.shortcut_container,
    }

    self[1] = LeftContainer:new{
        dimen = self.dimen:copy(),
        overlaps,
    }
end

-- Set of { Font color, background color }
local SPAN_COLORS = {
    { Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE },
    { Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_GRAY_E },
    { Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_LIGHT_GRAY },
    { Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_GRAY },
    { Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_WEB_GRAY },
    { Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_DARK_GRAY },
    { Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_DIM_GRAY },
    { Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_BLACK },
}

function TuyaDevice:update()
end

local TuyaView = InputContainer:new{
    devices = nil,
    nb_book_spans = 3,
    font_face = "xx_smallinfofont",
    title = "",
    width = nil,
    height = nil,
    covers_fullscreen = true, -- hint for UIManager:_repaint()
}

function TuyaView:init()
    local wDir = getSourceDir()
    local deviceJson = wDir .. "/tuya_devices.json"
    parsed, err = JSON.load(deviceJson)
    if parsed then
        self.devices = parsed
    else
    	return self:onClose()
	end
	pycommand = wDir .."/tu.py"
    
    self.dimen = Geom:new{
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }

    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close page" },
        }
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            }
        }
    end

    self.outer_padding = Size.padding.large
    self.inner_padding = Size.padding.small

    -- 7 scs in a week
    self.sc_width = math.floor((self.dimen.w - 2*self.outer_padding - 6*self.inner_padding) / 7)
    -- Put back the possible 7px lost in rounding into outer_padding
    self.outer_padding = math.floor((self.dimen.w - 7*self.sc_width - 6*self.inner_padding) / 2)

    self.inner_dimen = Geom:new{
        w = self.dimen.w - 2*self.outer_padding,
        h = self.dimen.h - 2*self.outer_padding,
    }
    self.content_width = self.inner_dimen.w

    self.title_bar = TuyaTitle:new{
        width = self.content_width,
        height = Size.item.height_default,
        tuya_view = self,
    }

    -- week scs names header
    self.sc_names = HorizontalGroup:new{}

    -- At most 6 devices in a month
    local available_height = self.inner_dimen.h - self.title_bar:getSize().h
                            - self.sc_names:getSize().h
    self.week_height = math.floor((available_height - 7*self.inner_padding) / 6)
    self.sc_border = Size.border.default

    -- sc num + nb_book_span: floor() to get some room for bottom padding
    self.span_height = math.floor((self.week_height - 2*self.sc_border) / (self.nb_book_spans+1))

    -- Limit font size to 1/3 of available height, and so that
    -- the sc number and the +nb-not-shown do not overlap
    local text_height = math.min(self.span_height, self.week_height/3)
    self.span_font_size = TextBoxWidget:getFontSizeToFitHeight(text_height, 1, 0.3)
    local sc_inner_width = self.sc_width - 2*self.sc_border -2*self.inner_padding
    while true do
        local test_w = TextWidget:new{
            text = " 30 + 99 ", -- we want this to be displayed in the available width
            face = Font:getFace(self.font_face, self.span_font_size),
            bold = true,
        }
        if test_w:getWidth() <= sc_inner_width then
            test_w:free()
            break
        end
        self.span_font_size = self.span_font_size - 1
        test_w:free()
    end

    self.main_content = VerticalGroup:new{}
    self:_populateItems()

    local content = OverlapGroup:new{
        dimen = Geom:new{
            w = self.inner_dimen.w,
            h = self.inner_dimen.h,
        },
        allow_mirroring = false,
        VerticalGroup:new{
            self.title_bar,
            self.sc_names,
            self.main_content,
        },
    }
    -- assemble page
    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        padding = self.outer_padding,
        padding_bottom = 0,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content
    }
end

function TuyaView:_populateItems()
    self.main_content:clear()

    for k, v in ipairs(self.devices) do
        v.idx = k-1, -- Python indexes from 0
        table.insert(self.main_content, VerticalSpan:new{ width = Size.span.vertical_default })
        device = TuyaDevice:new{
            device = v,
            height = self.week_height,
            width = self.content_width,
            sc_width = self.sc_width,
            sc_padding = self.inner_padding,
            sc_border = self.sc_border,
            font_face = self.font_face,
            font_size = self.span_font_size,
            show_parent = self,
        }
        table.insert(self.main_content, device)
    end

    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function TuyaView:onSwipe(arg, ges_ev)
    local direction = BD.flipDirectionIfMirroredUILayout(ges_ev.direction)
    if direction == "west" or direction == "east" then
        return true
    elseif direction == "south" then
        -- Allow easier closing with swipe down
        self:onClose()
    elseif direction == "north" then
        -- no use for now
        do end -- luacheck: ignore 541
    else -- diagonal swipe
        -- trigger full refresh
        UIManager:setDirty(nil, "full")
        -- a long diagonal swipe may also be used for taking a screenshot,
        -- so let it propagate
        return false
    end
end

function TuyaView:onClose()
    UIManager:close(self)
    return true
end

return TuyaView
