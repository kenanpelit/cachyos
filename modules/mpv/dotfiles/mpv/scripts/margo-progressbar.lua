-- margo-progressbar.lua
-- The thin line at the bottom of the window that shows where the playing file is, on its own: it no longer
-- lives inside margo-osc (persistentprogress), so it stays when the OSC is turned off (visibility=never, Delete).
-- It steps aside while margo-osc's controls are on screen (user-data/osc/visible), where the seekbar shows the
-- same thing. Settings: script-opts/margo-progressbar.conf. Binding: script-binding margo_progressbar/toggle.

local assdraw = require "mp.assdraw"
local options = require "mp.options"

local o = {
    enabled = true,
    height = 3,                 -- in a 720-high canvas, as margo-osc's persistentprogressheight was (3 = 3 px at 720p)
    color = "#886AD3",          -- the played part
    markers = true,             -- chapter notches
    marker_color = "#2D2D2D",
    buffer = false,             -- the cached ranges of a stream, behind the played part
    buffer_color = "#886AD3",
    buffer_alpha = 160,         -- 0 opaque … 255 invisible
    hide_with_osc = true,       -- step aside while margo-osc's controls are visible
}
options.read_options(o, "margo-progressbar")

local overlay = mp.create_osd_overlay("ass-events")
local osc_visible = false
local pending = false

-- "#RRGGBB" → ASS "BBGGRR".
local function ass_color(hex)
    local r, g, b = hex:match("^#?(%x%x)(%x%x)(%x%x)$")
    if not r then return "D36A88" end
    return (b .. g .. r):upper()
end

local function clear()
    if overlay.data ~= "" then
        overlay.data = ""
        overlay:update()
    end
end

local function render()
    pending = false
    local duration = mp.get_property_number("duration")
    local pos = mp.get_property_number("time-pos")
    if not o.enabled or (o.hide_with_osc and osc_visible) or not duration or duration <= 0 or not pos
        or mp.get_property_bool("idle-active") then
        return clear()
    end
    local w, h, aspect = mp.get_osd_size()
    if not w or w <= 0 or not h or h <= 0 then return clear() end
    aspect = (aspect and aspect > 0) and aspect or (w / h)
    local res_y = 720
    local res_x = math.floor(res_y * aspect + 0.5)
    local top = res_y - o.height
    local x_of = function(seconds) return math.max(0, math.min(res_x, seconds / duration * res_x)) end
    if mp.get_property_bool("eof-reached") then pos = duration end

    local ass = assdraw.ass_new()
    local function rects(color, alpha, list)
        if #list == 0 then return end
        ass:new_event()
        ass:append(string.format("{\\an7\\pos(0,0)\\bord0\\shad0\\blur0\\1c&H%s&\\1a&H%02X&}", ass_color(color), alpha))
        ass:draw_start()
        for _, r in ipairs(list) do ass:rect_cw(r[1], top, r[2], res_y) end
        ass:draw_stop()
    end

    if o.buffer then
        local cache = mp.get_property_native("demuxer-cache-state")
        local ranges = {}
        for _, range in ipairs(cache and cache["seekable-ranges"] or {}) do
            ranges[#ranges + 1] = { x_of(range.start), x_of(range["end"]) }
        end
        rects(o.buffer_color, o.buffer_alpha, ranges)
    end
    rects(o.color, 0, { { 0, x_of(pos) } })
    if o.markers then
        local notches = {}
        for _, chapter in ipairs(mp.get_property_native("chapter-list") or {}) do
            local x = x_of(chapter.time)
            if x > 1 and x < res_x - 1 then notches[#notches + 1] = { x - 1, x + 1 } end
        end
        rects(o.marker_color, 0, notches)
    end

    overlay.res_x, overlay.res_y, overlay.z = res_x, res_y, -10 -- under margo-osc's own drawing
    if overlay.data ~= ass.text then
        overlay.data = ass.text
        overlay:update()
    end
end

-- time-pos changes every frame: the redraws are gathered into one per 1/20 s.
local function request()
    if pending then return end
    pending = true
    mp.add_timeout(0.05, render)
end

for _, property in ipairs({ "time-pos", "duration", "chapter-list", "osd-dimensions", "idle-active", "eof-reached" }) do
    mp.observe_property(property, "native", request)
end
mp.observe_property("demuxer-cache-state", "native", function() if o.buffer then request() end end)
mp.observe_property("user-data/osc/visible", "native", function(_, visible)
    osc_visible = visible == true
    request()
end)

mp.add_key_binding(nil, "toggle", function()
    o.enabled = not o.enabled
    mp.osd_message("Progress bar: " .. (o.enabled and "on" or "off"))
    request()
end)
