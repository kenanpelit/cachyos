package.preload["helpers"] = function()
local utils    = require "mp.utils"
local this     = {}
local assStart = mp.get_property_osd("osd-ass-cc/0")
local assStop  = mp.get_property_osd("osd-ass-cc/1")

local function commandExists(command)

    local result = mp.command_native({

        name           = 'subprocess',
        playback_only  = false,
        capture_stdout = true,
        capture_stderr = true,
        args           = {"sh", "-c", 'command -v "$1" >/dev/null 2>&1', "sh", command}
    })

    return result.status == 0
end

local function runCommandWithInput(args, input)

    local command = {"sh", "-c", 'printf "%s" "$1" | shift; "$@"', "sh", input}

    for _, arg in ipairs(args) do

        table.insert(command, arg)
    end

    return this.runCommand(command)
end

function this.log(str)

    if type(str) == "table" then

        print(utils.format_json(str))
    else

        print(str)
    end
end

function this.log2(t, indent)

    indent    = indent or 0
    local tab = string.rep("  ", indent)

    for k, v in pairs(t) do

        if type(v) == "table" then

            print(tab..tostring(k)..":")

            this.log2(v, indent + 1)
        else

            print(tab..tostring(k).." = "..tostring(v))
        end
    end
end

function this.notify(msg,errType,level,duration,silent)

    duration = duration or 5

    mp.msg[level](msg)

    local colors = {

        error = "&H3300AA&",
        warn  = "&H0077CC&"
    }

    local headers = {

        error = "Error",
        warn  = "Warning"
    }

    if not silent then

        local output = ""
        output       = output..string.format("{%s\\b1}", colors[level] and "\\c"..colors[level] or "")
        output       = output..string.format("[dualsubtitles:%s]{\\b0} ", errType)
        output       = output..(headers[level] and string.format("%s! ", headers[level]) or "")
        output       = output..msg

        mp.osd_message(assStart..output..assStop, duration)
    end
end

function this.splitString(str, splitter)

    splitter = splitter or ","

    local list = {}

    for val in str:gmatch("([^"..splitter.."]+)") do

        table.insert(list, val)
    end

    return list
end

function this.hasItem(items, value)

    for _, item in ipairs(items) do

        if item == value then return true end
    end

    return false
end

function this.searchStrings(value, items)

    for _, item in ipairs(items) do

        if string.find(value, item, 1, true) then return true end
    end

    return false
end

function this.runCommandAsync(args, handleSuccess, handleFail, runAlways)

    return mp.command_native_async({

        name           = 'subprocess',
        playback_only  = false,
        capture_stdout = true,
        capture_stderr = true,
        args           = args
    },

    function(_, result, _)

        if runAlways then runAlways() end

        if result.killed_by_us then return end

        if result.status == 0 then

            handleSuccess(result)
        else

            this.log(args)
            this.log(result)

            handleFail(result.stderr, result.status)
        end
    end)
end

function this.runCommand(args)

    local result = mp.command_native({

        name           = 'subprocess',
        playback_only  = false,
        capture_stdout = true,
        capture_stderr = true,
        args           = args
    })

    if result.status ~= 0 then

        this.log(args)
        this.log(result)
    end

    return result
end

function this.hash(str)

    local h1, h2, h3 = 0, 0, 0

    for i = 1, #str do

        local b = str:byte(i)

        h1 = (h1 * 31 + b) % 2^32
        h2 = (h2 * 37 + b) % 2^32
        h3 = (h3 * 41 + b) % 2^32
    end

    return string.format("%08x%08x%08x", h1, h2, h3)
end

function this.setClipboard(str)

    local clipboardCommands = {}

    if os.getenv("WAYLAND_DISPLAY") or os.getenv("WAYLAND_SOCKET") then

        table.insert(clipboardCommands, {"wl-copy"})
    end

    table.insert(clipboardCommands, {"xclip", "-selection", "clipboard"})
    table.insert(clipboardCommands, {"xsel", "--clipboard", "--input"})

    for _, args in ipairs(clipboardCommands) do

        if commandExists(args[1]) then

            local result = runCommandWithInput(args, str)

            if result.status == 0 then return true end
        end
    end

    this.notify("No Linux clipboard tool found. Install wl-copy, xclip, or xsel.", "clipboard", "warn")

    return false
end

--https://ssojet.com/escaping/regex-escaping-in-lua/
function this.escape(str)

    return str:gsub("[%.%+%-%*%?%^%$%(%)%[%]]", "%%%1")
end

function this.removeItems(t, cond, keepMatching)

    local itemsToDelete = {}

    for index, item in ipairs(t) do

        if cond(index, item) then

            itemsToDelete[index] = true
        end
    end

    if next(itemsToDelete) ~= nil then

        for i = #t, 1, -1 do

            if keepMatching and not itemsToDelete[i] or not keepMatching and itemsToDelete[i] then table.remove(t, i) end
        end
    end
end

function this.isEmpty(str)

    return str:gsub("%s+", "") == ""
end

function this.clearTable(t)

    for k in pairs(t) do t[k] = nil end
end

return this
end

package.preload["path"] = function()
local mp        = require "mp"
local utils     = require "mp.utils"
local this      = {}
local cacheRoot = os.getenv("XDG_CACHE_HOME") or utils.join_path(os.getenv("HOME") or "/tmp", ".cache")
local variables = {

    temp    = cacheRoot,
    config  = mp.command_native({"expand-path", "~~/"}),
    scripts = mp.command_native({"expand-path", "~~/scripts"}),
    options = mp.command_native({"expand-path", "~~/script-opts"})
}

local function runCommand(args)

    return mp.command_native({

        name           = 'subprocess',
        playback_only  = false,
        capture_stdout = true,
        capture_stderr = true,
        args           = args
    })
end

function this.join(parts)
    local resolved

    for index, part in ipairs(parts) do

        part = string.gsub(part, "%%(.+)", function(vName)

            if variables[vName] then return variables[vName] end

            return ""
        end)

        if index == 1 then

            resolved = part
        else

            resolved = utils.join_path(resolved, part)
        end
    end

    return resolved
end

function this.checkPath(path)

    return utils.file_info(path) ~= nil
end

function this.removeFile(path)

    os.remove(path)
end

function this.removeDir(path)

    runCommand({"rm", "-rf", "--", path})
end

function this.createDir(path)

    runCommand({"mkdir", "-p", path})
end

function this.readFile(path)

    local h = io.open(path, "r")

    if not h then return nil end

    local content = h:read("*all")

    h:close()

    return content
end

function this.createFile(path, content)

    local h = io.open(path, "w")

    if not h then return false end

    h:write(content)
    h:close()

    return true
end

return this
end

package.preload["subtitle"] = function()
local utils    = require "mp.utils"
local subtitle = {}
local supportedLanguages = {

    en      = "en",
    eng     = "en",
    english = "en",
    tr      = "tr",
    tur     = "tr",
    turkish = "tr"
}

subtitle.__index = subtitle

local function isTextBased(track)

    return track.codec and (track.codec == "subrip" or track.codec == "ass")
end

local function isForced(track)

    if track.forced                                       then return true end
    if track.title and track.title:lower():find("forced") then return true end

    return false
end

local function isHearingImpaired(track)

    if track.hearing_impaired then return true  end
    if not track.title        then return false end

    local sTitle = track.title:lower()

    if sTitle:find("sdh") or sTitle:find("cc") then return true end

    return false
end

local function getExt(track)

    if not track.codec then return nil end

    local extensionList = {

        subrip            = ".srt",
        ass               = ".ass",
        hdmv_pgs_subtitle = ".sup"
    }

    return extensionList[track.codec]
end

local function normalizeLanguage(value)

    if not value then return nil end

    local token = value:lower():gsub("_", "-"):match("^([a-z]+)")

    if token then return supportedLanguages[token] end

    return nil
end

local function detectLanguageFromPath(filename)

    local basename = filename and filename:match("([^/\\]+)$") or nil

    if not basename then return nil end

    local token = basename:match("^([a-zA-Z]+)%.[^.]+$")

    if not token then

        token = basename:match("[%.%-%s]([a-zA-Z]+)%.[^.]+$")
    end

    return normalizeLanguage(token)
end

local function detectSubtitleInfo(track)

    local lang      = detectLanguageFromPath(track["external-filename"]) or detectLanguageFromPath(track.title)
    local eSubtitle = utils.file_info(track["external-filename"])
    local bytes     = eSubtitle and eSubtitle.size or 0

    return lang, bytes
end

function subtitle:new(track)

    local obj           = {}
    obj.id              = track.id
    obj.title           = track.title
    obj.ext             = getExt(track)
    obj.textbased       = isTextBased(track)
    obj.external        = track.external
    obj.lang            = normalizeLanguage(track.lang)
    obj.size            = track.metadata and track.metadata.NUMBER_OF_BYTES or 0
    obj.default         = track.default
    obj.forced          = isForced(track)
    obj.hearingimpaired = isHearingImpaired(track)
    obj.visualimpaired  = track["visual-impaired"]
    obj.path            = track["external-filename"]

    if obj.external then

        local lang, bytes = detectSubtitleInfo(track)
        obj.lang          = obj.lang or lang
        obj.size          = bytes
    end

    setmetatable(obj, self)

    return obj
end

function subtitle:__tostring()

    local dst = ""

    if self.title then

        dst = dst..string.format("'%s' ", self.title)
    end

    dst = dst.."("

    if self.lang then

        dst = dst..string.format("%s ", self.lang)
    end

    local codec

    if     self.ext == ".srt" then codec = "subrip [Advanced Sub Station Alpha]"
    elseif self.ext == ".ass" then codec = "ass"
    elseif self.ext == ".sup" then codec = "hdmv_pgs_subtitle"
    else                           codec = "<unknown>" end

    dst = dst..codec
    dst = dst..")"

    local flags = {}

    if self.default         then table.insert(flags, "default")          end
    if self.forced          then table.insert(flags, "forced")           end
    if self.visualimpaired  then table.insert(flags, "visual-impaired")  end
    if self.hearingimpaired then table.insert(flags, "hearing-impaired") end
    if self.external        then table.insert(flags, "external")         end

    if #flags > 0 then

        dst = dst.." ["..table.concat(flags, " ").."]"
    end

    dst = "("..self.id..") "..dst

    return dst
end

return subtitle
end

package.preload["assline"] = function()
--v1.3
local ass = {}

ass.__index = ass

local function newTime(str)

    return setmetatable({original=str}, {

        __index = {

            ms = function(self)

                local h, m, s, ms = self.original:match("^(%d?%d):(%d%d):(%d%d)%.(%d%d%d?)$")

                if not h then return 0 end

                if #self.original == 10 then ms = ms.."0" end

                return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + tonumber(ms) / 1000
            end,

            fromMS = function(self, secs)

                if secs == 0 then self.original = "0:00:00.00" return end

                local h  = math.floor(secs / 3600)
                local m  = math.floor((secs % 3600) / 60)
                local s  = secs % 60
                local ms = math.floor((secs - math.floor(secs)) * 1000)

                self.original = string.format("%d:%02d:%02d.%02d", h, m, s, ms)
            end
        },

        __tostring = function(self) return self.original end
    })
end

local function newText(str)

    return setmetatable({original=str}, {

        __index = {

            stripped = function(self)

                text = self.original
                :gsub("%{[^%}]*%}", "")
                :gsub("\\[nNh]", " ")
                :gsub("%s+", " ")

                return text
            end,

            noTags = function(self)

                text = self.original
                :gsub("%{[^%}]*%}", "")
                :gsub("%s+", " ")

                return text
            end,

            isSign = function(self)

                return (self.original:find("\\pos%([%d%s%.,]+%)") or self.original:find("\\move%([%d%s%.,]+%)")) and true or false
            end,

            isShape = function(self)

                return self.original:find("%}%s*m%s+%d+%s+%d+") and true or false
            end,
        },

        __tostring = function(self) return self.original end
    })
end

local patterns = {

    Styles = "\n(Style):%s([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^\n]+)",
    Lines  = "\n(Dialogue):%s([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^\n]+)"
}

local parseMap = {

    Style = function(t)

        return {

            Class           = t[1],
            Name            = t[2],
            Fontname        = t[3],
            Fontsize        = tonumber(t[4]),
            PrimaryColour   = t[5],
            SecondaryColour = t[6],
            OutlineColour   = t[7],
            BackColour      = t[8],
            Bold            = t[9]  == "-1" and true or false,
            Italic          = t[10] == "-1" and true or false,
            Underline       = t[11] == "-1" and true or false,
            StrikeOut       = t[12] == "-1" and true or false,
            ScaleX          = tonumber(t[13]),
            ScaleY          = tonumber(t[14]),
            Spacing         = tonumber(t[15]),
            Angle           = tonumber(t[16]),
            BorderStyle     = tonumber(t[17]),
            Outline         = tonumber(t[18]),
            Shadow          = tonumber(t[19]),
            Alignment       = tonumber(t[20]),
            MarginL         = tonumber(t[21]),
            MarginR         = tonumber(t[22]),
            MarginV         = tonumber(t[23]),
            Encoding        = tonumber(t[24])
        }
    end,

    Dialogue = function(t)

        return {

            Class   = t[1],
            Layer   = tonumber(t[2]),
            Start   = newTime(t[3]),
            End     = newTime(t[4]),
            Style   = t[5],
            Actor   = t[6],
            MarginL = tonumber(t[7]),
            MarginR = tonumber(t[8]),
            MarginV = tonumber(t[9]),
            Effect  = t[10],
            Text    = newText(t[11])
        }
    end
}

local serializeMap = {

    Style = function(self)

        return string.format("Style: %s,%s,%d,%s,%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d",

            self.Name,
            self.Fontname,
            self.Fontsize,
            self.PrimaryColour,
            self.SecondaryColour,
            self.OutlineColour,
            self.BackColour,
            (self.Bold      and -1 or 0),
            (self.Italic    and -1 or 0),
            (self.Underline and -1 or 0),
            (self.StrikeOut and -1 or 0),
            self.ScaleX,
            self.ScaleY,
            self.Spacing,
            self.Angle,
            self.BorderStyle,
            self.Outline,
            self.Shadow,
            self.Alignment,
            self.MarginL,
            self.MarginR,
            self.MarginV,
            self.Encoding
        )
    end,

    Dialogue = function(self)

       return string.format("Dialogue: %d,%s,%s,%s,%s,%d,%d,%d,%s,%s",

            self.Layer,
            self.Start,
            self.End,
            self.Style,
            self.Actor,
            self.MarginL,
            self.MarginR,
            self.MarginV,
            self.Effect,
            self.Text
        )
    end
}

function ass:new(t)

    local obj = parseMap[t[1]](t)

    return setmetatable(obj, self)
end

function ass:raw()

    return serializeMap[self.Class](self)
end

function ass:resolution(content)

    return tonumber(content:match("PlayResX: (%d+)") or 0), tonumber(content:match("PlayResY: (%d+)") or 0)
end

function ass:styles(content)

    local iter = content:gmatch(patterns.Styles)

    return function()

        local line = {iter()}

        if not line[1] then return nil end

        return self:new(line)
    end
end

function ass:lines(content)

    local iter = content:gmatch(patterns.Lines)

    return function()

        local line = {iter()}

        if not line[1] then return nil end

        return self:new(line)
    end
end

return ass
end

package.preload["resampler"] = function()
--[[

Resolution resampling logic inspired by Aegisub
https://github.com/Aegisub/Aegisub
Original BSD licensed code by Thomas Goyne

]]

local this         = {}

local rx, ry       = 0, 0
local shapeLetters = {"m", "n", "l", "b", "s", "p", "c"}

local function hasValue(items, value)

    local result = false

    for _, item in ipairs(items) do

        if value:find(item) then

            result = true
            break
        end
    end

    return result
end

local function split(str)

    local list = {}

    for s in str:gmatch("[^,]+") do

        local number = tonumber(s)

        if number then table.insert(list, number) end
    end

    return list
end

local function toFloat(n, decimals)

    n = string.format("%."..decimals.."f", n)
    n = n:gsub("0+$", ""):gsub("%.$", "")

    return n
end

function this.setResolutions(sourceX, sourceY, destX, destY)

    rx = destX / sourceX
    ry = destY / sourceY
end

function this.resampleStyle(style)

    style.Fontsize = math.floor(style.Fontsize * ry + 0.5)
    style.Outline  = style.Outline * ry
    style.Shadow   = style.Shadow * ry
    style.Spacing  = style.Spacing * ry
    style.MarginL  = math.floor(style.MarginL * rx + 0.5)
    style.MarginR  = math.floor(style.MarginR * rx + 0.5)
    style.MarginV  = math.floor(style.MarginV * ry + 0.5)
end

local tagMap = {

    bord = function(p)

        if #p ~= 1 then return nil end

        return string.format("bord%s", toFloat(p[1] * ry, 1))
    end,

    xbord = function(p)

        if #p ~= 1 then return nil end

        return string.format("xbord%s", toFloat(p[1] * rx, 1))
    end,

    ybord = function(p)

        if #p ~= 1 then return nil end

        return string.format("ybord%s", toFloat(p[1] * ry, 1))
    end,

    shad = function(p)

        if #p ~= 1 then return nil end

        return string.format("shad%s", toFloat(p[1] * ry, 1))
    end,

    xshad = function(p)

        if #p ~= 1 then return nil end

        return string.format("xshad%s", toFloat(p[1] * rx, 1))
    end,

    yshad = function(p)

        if #p ~= 1 then return nil end

        return string.format("yshad%s", toFloat(p[1] * ry, 1))
    end,

    be = function(p)

        if #p ~= 1 then return nil end

        return string.format("be%d", p[1] * ry)
    end,

    blur = function(p)

        if #p ~= 1 then return nil end

        return string.format("blur%s", toFloat(p[1] * ry, 1))
    end,

    fs = function(p)

        if #p ~= 1 then return nil end

        return string.format("fs%d", p[1] * ry + 0.5)
    end,

    fsp = function(p)

        if #p ~= 1 then return nil end

        return string.format("fsp%d", p[1] * rx)
    end,

    pos = function(p)

        if #p ~= 2 then return nil end

        return string.format("pos(%s,%s)", toFloat(p[1] * rx, 3), toFloat(p[2] * ry, 3))
    end,

    move = function(p)

        if not (#p == 4 or #p == 6) then return nil end

        if #p == 4 then

            return string.format("move(%s,%s,%s,%s)",       toFloat(p[1] * rx, 3), toFloat(p[2] * ry, 3), toFloat(p[3] * rx, 3), toFloat(p[4] * ry, 3))
        elseif #p == 6 then

            return string.format("move(%s,%s,%s,%s,%d,%d)", toFloat(p[1] * rx, 3), toFloat(p[2] * ry, 3), toFloat(p[3] * rx, 3), toFloat(p[4] * ry, 3), p[5], p[6])
        else

            return nil
        end
    end,

    org = function(p)

        if #p ~= 2 then return nil end

        return string.format("org(%s,%s)", math.floor(p[1] * rx, 3), math.floor(p[2] * ry), 3)
    end,

    clip = function(p)

        if #p == 4 then

            return string.format("clip(%s,%s,%s,%s)", math.floor(p[1] * rx, 3), math.floor(p[2] * ry, 3), math.floor(p[3] * rx, 3), math.floor(p[4] * ry, 3))
        end

        return nil
    end,

    iclip = function(p)

        if #p == 4 then

            return string.format("clip(%s,%s,%s,%s)", math.floor(p[1] * rx, 3), math.floor(p[2] * ry, 3), math.floor(p[3] * rx, 3), math.floor(p[4] * ry, 3))
        end

        return nil
    end,
}

function this.resampleTag(name, params)

    params   = split(params:gsub("[%(%)%s]+", ""))
    local fn = tagMap[name]

    if fn then return fn(params) end

    return nil
end

function this.resampleDrawing(drawing)

    local isX   = true
    local parts = {}

    for cur in drawing:gmatch("%S+") do

        local num = tonumber(cur)

        if num then

            num = isX and num * rx or num * ry

            table.insert(parts, math.floor(num + 0.5))

            isX = not isX
        else

            local c = string.lower(cur)

            if hasValue(shapeLetters, c) then

                isX = true

                table.insert(parts, c)
            end
        end
    end

    return table.concat(parts, " ")
end

function this.resampleDialogue(line)

    if line.MarginL > 0 then line.MarginL = math.floor(line.MarginL * rx + 0.5) end
    if line.MarginR > 0 then line.MarginR = math.floor(line.MarginR * rx + 0.5) end
    if line.MarginV > 0 then line.MarginV = math.floor(line.MarginV * ry + 0.5) end

    line.Text = line.Text:gsub("\\([a-zx]+)([^\\%}]+)", function(name, params)

        local result = this.resampleTag(name, params)

        return "\\"..(result or name..params)
    end)

    line.Text = line.Text:gsub("([%}%(])%s*(m%s+[%d%-%.]+%s+[%d%-%.]+[%s%d%-%."..table.concat(shapeLetters, "").."]+)", function(p, drawing)

        return string.format("%s%s", p, this.resampleDrawing(drawing))
    end)
end

return this
end

local mp        = require "mp"
local options   = require "mp.options"
local utils     = require "mp.utils"
local assdraw   = require "mp.assdraw"
local h         = require "helpers"
local subtitle  = require "subtitle"
local resampler = require "resampler"
local assline   = require "assline"
local path      = require "path"
local this      = {

    subtitles      = {},
    prevTrackCount = 0,
    bottom         = nil,
    top            = nil,
    merged         = nil,
    hash           = nil,
    hashPath       = nil,
    tempDir        = "mpvdualsubtitles"
}
local supportedLanguages = {

    en = true,
    tr = true
}

local overlay   = mp.create_osd_overlay("ass-events")
local merge     = {
    current             = nil,
    progress            = {},
    progressHandler     = nil,
    progressTimer       = nil,
    progressBase        = 0,
    active              = nil,
    total               = 0,
    start               = 0,
    data                = {},
    defaultErrorMessage = "See the console for details.",
    flags               = {

        COPY               = 1,
        GETDURATION        = 2,
        EXTRACT            = 3,
        CONVERT_TEXTBASED  = 4,
        CONVERT_IMAGEBASED = 5,
        MERGE              = 6
    }
}

local function filter(subtitle, wordsToFilter)

    if subtitle.forced                                                           then return false end
    if subtitle.title and h.searchStrings(subtitle.title:lower(), wordsToFilter) then return false end

    return true
end

local function hasItalic(text)

    --SDH
    text = text:gsub("^%s*%[.-%]", "")
    text = text:gsub("^%s*\\N", "")

    text = "{}"..text
    text = text:gsub("}%s*{", "")
    text = text:match("^[^%}]+")

    if text and text:find("\\i1") then return true end

    return false
end

local function sdhKiller(text)

    local count
    local speakerDash       = "%s*%-%s*"
    local soundDescriptions = "[%[%(][^%]%)]-[%]%)]"

    --sound descriptions with speaker dash (two lines)
    _, count = text:gsub("^"..speakerDash..soundDescriptions.."%s*\\N"..speakerDash..soundDescriptions.."%s*$", "")

    if count > 0 then return "" end

    --sound descriptions with speaker dash (first line)
    text = text:gsub("^"..speakerDash..soundDescriptions.."%s*\\N"..speakerDash, "")

    --sound descriptions with speaker dash (second line)
    text, count = text:gsub(speakerDash..soundDescriptions.."%s*$", "")

    if count > 0 then text = text:gsub("^"..speakerDash, "") end

    --sound descriptions
    text = text:gsub("%s*"..soundDescriptions.."%s*", " ")

    --speaker names
    text = text:gsub("\\N"..speakerDash.."[^:]*:%s*", "\\N- ")
    text = text:gsub("^"..speakerDash.."[^:]*:%s*", "- ")

    --fixes
    text = text:gsub("^[^:]*:%s*", "")
    text = text:gsub("^%s*\\N%s*", "")
    text = text:gsub("%s*\\N%s*$", "")
    text = text:gsub("^"..speakerDash.."$", "")

    --trim
    text = text:match("^%s*(.-)%s*$")

    return text
end

local function getSubtitleList()

    local list   = {}
    local tracks = mp.get_property_native('track-list') or {}

    for _, value in ipairs(tracks) do

        if value.type == "sub" then table.insert(list, subtitle:new(value)) end
    end

    this.prevTrackCount = #tracks

    return list
end

local function copyCommand(s, t)

    return {"cp", "-f", "--", s, t}
end

local function shellCommand(command, ...)

    local args = {"sh", "-c", command, "sh"}

    for _, value in ipairs({...}) do

        table.insert(args, value)
    end

    return args
end

local function isSupportedLanguage(lang)

    return lang and supportedLanguages[lang] or false
end

local function getConfiguredLanguages(configLangKey)

    local languageList = {}
    local previousLangs = {}

    for _, val in ipairs(h.splitString(config[configLangKey])) do

        local lang = val:match("^([a-z][a-z])")

        if isSupportedLanguage(lang) and not previousLangs[lang] then

            table.insert(languageList, lang)
            previousLangs[lang] = true
        end
    end

    h.log(utils.format_json({[configLangKey] = languageList}))

    return languageList
end

local function getSupportedSubtitleIds(excludedSid)

    local subtitleIds = {0}

    for _, currentSubtitle in ipairs(this.subtitles) do

        if currentSubtitle.id ~= excludedSid and isSupportedLanguage(currentSubtitle.lang) then

            table.insert(subtitleIds, currentSubtitle.id)
        end
    end

    return subtitleIds
end

local function getNextIndex(items, currentIndex, step)

    return ((currentIndex - 1 + step) % #items) + 1
end

local function getSidByLanguage(configLangKey)

    local languageCodes     = getConfiguredLanguages(configLangKey)
    local undesiredWords    = h.splitString(config.rejected_words)
    local selectedSubtitles = nil
    local missingMetadata   = false

    for _, lang in ipairs(languageCodes) do

        local currentSelection      = {}
        local currentMissingMetadata = false

        for _, currentSubtitle in ipairs(this.subtitles) do

            if currentSubtitle.lang == lang and filter(currentSubtitle, undesiredWords) then

                table.insert(currentSelection, currentSubtitle)

                if currentSubtitle.size == 0 then currentMissingMetadata = true end
            end
        end

        if #currentSelection > 0 then

            selectedSubtitles = currentSelection
            missingMetadata   = currentMissingMetadata

            break
        end
    end

    if not selectedSubtitles then

        return 0
    end

    if #selectedSubtitles > 1 then

        if missingMetadata then h.notify("There are subtitles with missing metadata. Sorting may not work correctly.", "findsubtitle", "warn", nil, true) end

        --filter by preferred words

        if config.preferred_words ~= "" then

            local desiredWords = h.splitString(config.preferred_words)

            if next(desiredWords) ~= nil then

                h.removeItems(selectedSubtitles, function(_, val)

                    if val.title and h.searchStrings(val.title:lower(), desiredWords) then return true end

                    return false
                end, true)
            end

            if #selectedSubtitles == 1 then return selectedSubtitles[1].id end
        end

        --sort subtitles by size

        table.sort(selectedSubtitles, function(a, b)

            return tonumber(a.size) > tonumber(b.size)
        end)

        --get first text-based subtitle that is not SDH

        for _, subtitle in ipairs(selectedSubtitles) do

            if not subtitle.hearingimpaired and subtitle.textbased then

                return subtitle.id
            end
        end

        --get first subtitle that is not SDH

        for _, subtitle in ipairs(selectedSubtitles) do

            if not subtitle.hearingimpaired then

                return subtitle.id
            end
        end
    end

    --get first subtitle if nothing was found

    return selectedSubtitles[1] and selectedSubtitles[1].id or 0
end

local function updateOverlay(content, x, y)

    if overlay.data == content and overlay.res_x == 1280 and overlay.res_y == 720 then return end

    overlay.data  = content
    overlay.res_x = (x and x > 0) and x or 1280
    overlay.res_y = (y and y > 0) and y or 720
    overlay.z     = 2000

    overlay:update()
end

function merge.closeGui()

    updateOverlay("", 0, 0)

    merge.active = false

    mp.remove_key_binding("dualsubtitles_closegui")
end

function merge.statusGui()

    local ass  = assdraw.ass_new()
    local posX = merge.data.marginX
    local posY = merge.data.marginY

    local header = function (title)

        ass:new_event()
        ass:an(7)
        ass:pos(posX, posY)
        ass:append(string.format("{\\bord%s\\fs%s\\b1}%s", merge.data.borderSize, merge.data.fontSize, title))

        posY = posY + merge.data.fontSize
    end

    local steps = function (titles)

        for i, z in ipairs(titles) do

            ass:new_event()
            ass:an(7)
            ass:pos(posX, posY)

            if merge.progress[i] then

                if merge.progress[i] == 100 then

                    ass:append(string.format("{\\bord%s\\fs%s}%s", merge.data.borderSize, merge.data.fontSize, merge.data.tab..merge.data.completedSymbol.." "..z))
                else

                    ass:append(string.format("{\\bord%s\\fs%s}%s... (%s%%)", merge.data.borderSize, merge.data.fontSize, merge.data.tab..z, merge.progress[i]))
                end
            else

                ass:append(string.format("{\\bord%s\\fs%s\\alpha&H%x&}%s", merge.data.borderSize, merge.data.fontSize, merge.data.alpha, merge.data.tab..z))
            end

            posY = posY + merge.data.fontSize
        end
    end

    header("Merging Subtitles")
    steps({"Extracting or copying", "Converting", "Finishing up"})

    if not merge.active then

        posY          = posY + merge.data.fontSize
        local elapsed = mp.get_time() - merge.start

        ass:new_event()
        ass:an(7)
        ass:pos(posX, posY)
        ass:append(string.format("{\\bord%s\\fs%s}%s", merge.data.borderSize, merge.data.fontSize, string.format("Took {\\b1}%d{\\b0} seconds. Press <ESC> to exit.", elapsed)))
    end

    updateOverlay(ass.text)
end

function merge.updateProgress(step, percent)

    if merge.progress[step] == nil then merge.progressBase = 0 end

    local p          = percent
    local twoActions = false

    if this.top then

        twoActions = true

        if merge.current == merge.flags.EXTRACT and not (this.bottom.external and this.top.external) then twoActions = false end
    end

    if twoActions then p = p / 2 end

    merge.progress[step] = merge.progressBase + math.floor(p)

    if twoActions and percent == 100 then

        merge.progressBase = 50
    end

    merge.statusGui()
end

function merge.process()

    local data = {

        {style = "Primary",   subType = "bottom", ready = false},
        {style = "Secondary", subType = "top",    ready = false}
    }
    local styles = {}
    local lines  = {}

    for _, v in ipairs(data) do

        local sPath   = this.getPath("cache/"..v.subType.."file"):gsub("<ext>", ".ass")
        local content = path.readFile(sPath)

        if content then

            local shouldResample
            local italicStyles = {}

            if config.keep_ts == v.subType then

                local playResX, playResY = assline:resolution(content)

                shouldResample = (playResX == 1920 and playResY == 1080) and false or true

                if shouldResample then resampler.setResolutions(playResX, playResY, 1920, 1080) end

                for style in assline:styles(content) do

                    if config.detect_italics and style.Italic then table.insert(italicStyles, style.Name) end

                    style.Name = v.style..style.Name

                    if shouldResample then resampler.resampleStyle(style) end

                    table.insert(styles, style:raw())
                end
            end

            local makeItalic, seen = false, {}

            for line in assline:lines(content) do

                local prevStyle

                if not v.ready then v.ready = true end

                local deleteThis = false

                if config.keep_ts == v.subType and line:isSign() then

                    line.Style = v.style..line.Style

                    if shouldResample then resampler.resampleDialogue(line) end
                elseif not line.Text:isShape() then

                    local text = line.Text:noTags()

                    if config.remove_repeating_lines then

                        local sKey = tostring(line.Start)..tostring(line.End)

                        if seen[sKey] and seen[sKey] == text then

                            deleteThis = true
                        else

                            seen[sKey] = text
                        end
                    end

                    if not deleteThis and config.detect_italics then

                        if prevStyle ~= line.Style and h.hasItem(italicStyles, line.Style) then

                            makeItalic = true
                        else

                            makeItalic = false
                        end

                        makeItalic = makeItalic or hasItalic(line.Text.original)
                    end

                    if not deleteThis and config.remove_sdh_entries then

                        text = sdhKiller(text)

                        if text == "" then

                            deleteThis = true
                        end
                    end

                    if not deleteThis and config[v.subType.."_tags"] ~= "" then

                        text = string.format("{%s}%s", config[v.subType.."_tags"], text)
                    end

                    if not deleteThis and makeItalic then

                        text = string.format("{%s}%s", "\\i1", text):gsub("}{", "")
                    end

                    --for copy
                    text = string.format("{*%s}%s", v.style:sub(1,1), text):gsub("}{", "")

                    line.Layer = 0
                    line.Style = v.style
                    line.Text  = text
                end

                if not deleteThis then table.insert(lines, line:raw()) end

                prevStyle = line.Style
            end

            merge.updateProgress(3, 100)

            path.removeFile(sPath)
        end
    end

    if not data[1].ready and not data[2].ready then error("There is a missing or corrupted subtitle.") end

    local header = [[
[Script Info]
; Script generated by mpvdualsubtitles
ScriptType: v4.00+
WrapStyle: 0
PlayResX: 1920
PlayResY: 1080
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
<bottomstyle>
<topstyle>
<extrastyles>

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

]]

    header = header:gsub("<bottomstyle>", "Style: Primary,"..config.bottom_style:gsub("[^,]*:", ""))
    header = header:gsub("<topstyle>",    "Style: Secondary,"..config.top_style:gsub("[^,]*:", ""))

    if next(styles) ~= nil then

        header = header:gsub("<extrastyles>", table.concat(styles, "\n"))
    else

        header = header:gsub("\n<extrastyles>", "")
    end

    path.createFile(this.getPath("cache/mergedfile"), header..table.concat(lines, "\n"))
end

function merge.reset()

    merge.start   = 0
    merge.current = merge.flags.COPY
    merge.total   = 0

    h.clearTable(merge.progress)
    h.clearTable(merge.data)
end

function merge.preapare()

    path.createDir(this.getPath("cache/merge"))

    merge.active = true
    merge.start  = mp.get_time()
end

function merge.fillData()

    merge.data.borderSize      = mp.get_property_number("osd-border-size")
    merge.data.fontSize        = mp.get_property_number("osd-font-size")
    merge.data.marginX         = mp.get_property_number("osd-margin-x")
    merge.data.marginY         = mp.get_property_number("osd-margin-y")
    merge.data.tab             = string.rep("\\h", 4)
    merge.data.alpha           = 150
    merge.data.completedSymbol = "✓"
end

function merge.try()

    local ok, err = pcall(merge.process)

    if ok then

        this.set(0, 0)
        this.display()

        mp.commandv("sub-add", this.getPath("cache/mergedfile"))
        this.updateList(0)

        this.merged = this.subtitles[mp.get_property_number("sid")]

        mp.add_forced_key_binding("esc", "dualsubtitles_closegui", function()

            merge.closeGui()
        end)
    else

        merge.closeGui()

        h.notify(err, "mergesubtitles", "error")
        h.notify(merge.defaultErrorMessage, "mergesubtitles", "error")
    end
end

function merge.runNext()

    if merge.current == merge.flags.COPY then

        merge.preapare()
        merge.updateProgress(1, 0)

        local shouldExtract = false

        for _, k in ipairs({"bottom", "top"}) do

            local subtitle = this[k]

            if subtitle then

                if subtitle.external then

                    local sourceFile = subtitle.path
                    local targetFile = this.getPath(string.format("cache/%sfile", k)):gsub("<ext>", subtitle.ext)
                    local result     = h.runCommand(copyCommand(sourceFile, targetFile))

                    if result.status == 0 then

                        merge.updateProgress(1, 100)
                    else

                        merge.closeGui()

                        h.notify(merge.defaultErrorMessage, "commandfailed", "error")

                        return
                    end
                else

                    shouldExtract = true
                end
            end
        end

        merge.current = shouldExtract and merge.flags.GETDURATION or merge.flags.CONVERT_TEXTBASED

        merge.runNext()
    elseif merge.current == merge.flags.GETDURATION then

        local args = {}

        table.insert(args, "ffprobe")
        table.insert(args, "-v")
        table.insert(args, "error")
        table.insert(args, "-show_entries")
        table.insert(args, "format=duration")
        table.insert(args, "-of")
        table.insert(args, "default=noprint_wrappers=1:nokey=1")
        table.insert(args, this.getPath("videofile"))

        h.runCommandAsync(args,

            function(result)

                merge.total   = tonumber(result.stdout)
                merge.current = merge.flags.EXTRACT

                merge.runNext()
            end,

            function(result, status, default)

                merge.closeGui()

                if status == -3 then

                    h.notify("FFmpeg is not installed. Please install it first.", "missingdependencies", "error")
                else

                    h.notify(merge.defaultErrorMessage, "ffmpeg", "error")
                end
            end
        )
    elseif merge.current == merge.flags.EXTRACT then

        local args = {}
        local progressFile = this.getPath("cache/progressfile")

        table.insert(args, "ffmpeg")
        table.insert(args, "-nostdin")
        table.insert(args, "-i")
        table.insert(args, this.getPath("videofile"))

        if this.bottom and not this.bottom.external then

            local bottomFile = this.getPath("cache/bottomfile"):gsub("<ext>", this.bottom.ext)

            table.insert(args, "-map")
            table.insert(args, string.format("0:s:%s", this.bottom.id - 1))
            table.insert(args, "-c")
            table.insert(args, "copy")
            table.insert(args, bottomFile)
        end

        if this.top and not this.top.external then

            local topFile = this.getPath("cache/topfile"):gsub("<ext>", this.top.ext)

            table.insert(args, "-map")
            table.insert(args, string.format("0:s:%s", this.top.id - 1))
            table.insert(args, "-c")
            table.insert(args, "copy")
            table.insert(args, topFile)
        end

        table.insert(args, "-vn")
        table.insert(args, "-an")
        table.insert(args, "-dn")
        table.insert(args, "-y")
        table.insert(args, "-progress")
        table.insert(args, progressFile)

        local lastPos = 0

        merge.progressTimer = mp.add_periodic_timer(0.5, function()

            if merge.progressHandler then

                merge.progressHandler:seek("set", lastPos)

                local newContent = merge.progressHandler:read("*all")
                lastPos          = merge.progressHandler:seek()
                local ms         = newContent:match("out_time_ms=(%d+)")

                if ms then

                    ms            = ms / 1000000
                    local percent = (ms / merge.total) * 100

                    merge.updateProgress(1, percent)
                end
            else

                merge.progressHandler = io.open(progressFile, "r")
            end
        end)

        h.runCommandAsync(args,

            function()

                merge.updateProgress(1, 100)

                merge.current = merge.flags.CONVERT_TEXTBASED

                merge.runNext()
            end,

            function(result, status, default)

                merge.closeGui()

                if string.find(result, "No such file or directory") then

                    h.notify("No such file or directory.", "ffmpeg", "error")
                elseif string.find(result, "Failed to set value") then

                    h.notify("Wrong subtitle id.", "ffmpeg", "error")
                else

                    h.notify(merge.defaultErrorMessage, "ffmpeg", "error")
                end
            end,

            function()

                path.removeFile(progressFile)

                if merge.progressTimer   then merge.progressTimer:kill()                                end
                if merge.progressHandler then merge.progressHandler:close() merge.progressHandler = nil end
            end
        )
    elseif merge.current == merge.flags.CONVERT_TEXTBASED then

        merge.updateProgress(2, 0)

        for _, k in ipairs({"bottom", "top"}) do

            local subtitle = this[k]

            if subtitle then

                if subtitle.ext == ".srt" then

                    local args       = {}
                    local sourceFile = this.getPath(string.format("cache/%sfile", k)):gsub("<ext>", this[k].ext)
                    local targetFile = this.getPath(string.format("cache/%sfile", k)):gsub("<ext>", ".ass")

                    table.insert(args, "ffmpeg")
                    table.insert(args, "-i")
                    table.insert(args, sourceFile)
                    table.insert(args, targetFile)

                    local result = h.runCommand(args)

                    if result.status ~= 0 then

                        merge.closeGui()

                        h.notify(merge.defaultErrorMessage, "ffmpeg", "error")

                        return
                    end

                    path.removeFile(sourceFile)

                    merge.updateProgress(2, 100)
                elseif subtitle.ext == ".ass" then

                    merge.updateProgress(2, 100)
                end
            end
        end

        merge.current = merge.flags.CONVERT_IMAGEBASED

        merge.runNext()
    elseif merge.current == merge.flags.CONVERT_IMAGEBASED then

        local convertProcess = function(key, success)

            if not this[key] or this[key].ext ~= ".sup" then success() return end

            local sourceFile = this.getPath(string.format("cache/%sfile", key)):gsub("<ext>", this[key].ext)
            local progressFile = this.getPath("cache/progressfile")
            local args         = shellCommand('subtitleedit /convert "$1" AdvancedSubStationAlpha > "$2"', sourceFile, progressFile)

            local lastPos = 0

            merge.progressTimer = mp.add_periodic_timer(0.5, function()

                if merge.progressHandler then

                    merge.progressHandler:seek("set", lastPos)

                    local newContent = merge.progressHandler:read("*all")
                    lastPos          = merge.progressHandler:seek()
                    local percent    = newContent:match("(%d+)%%")

                    if percent then merge.updateProgress(2, percent) end
                else

                    merge.progressHandler = io.open(progressFile, "r")
                end
            end)

            h.runCommandAsync(args,

                function()

                    merge.updateProgress(2, 100)

                    success()
                end,

                function(result, status, default)

                    merge.closeGui()

                    if status == -3 or status == 127 or string.find(result, "subtitleedit") and string.find(result, "not found") then

                        h.notify("Subtitle Edit is not installed. Please install it first.", "missingdependencies", "error")
                    else

                        h.notify(merge.defaultErrorMessage, "mergesubtitles", "error")
                    end
                end,

            function()

                    path.removeFile(progressFile)
                    path.removeFile(sourceFile)

                    if merge.progressTimer   then merge.progressTimer:kill()                                end
                    if merge.progressHandler then merge.progressHandler:close() merge.progressHandler = nil end
                end
            )
        end

        convertProcess("bottom", function()

            convertProcess("top", function()

                merge.current = merge.flags.MERGE

                merge.runNext()
            end)
        end)
    elseif merge.current == merge.flags.MERGE then

        merge.active = false

        merge.updateProgress(3, 0)
        merge.try()
        merge.reset()
    end
end

function this.merge()

    if this.merged then

        merge.closeGui()

        h.notify("Merged subtitle already exists.", "mergesubtitles", "error")

        return
    end

    if merge.active then return end

    if not this.bottom then

        h.notify("Bottom subtitle is required.", "mergesubtitles", "error")

        return
    end

    for _, k in ipairs({"bottom", "top"}) do

        local allowedExtensions = {".srt", ".ass", ".sup"}

        if this[k] and (not this[k].ext or not h.hasItem(allowedExtensions, this[k].ext)) then

            h.notify(string.format("The %s subtitle isn’t in the correct format (srt, ass, sup).", k), "mergesubtitles", "error")

            return
        end
    end

    merge.reset()
    merge.fillData()
    merge.runNext()
end

function this.deleteMerged()

    if not this.merged then return false end

    mp.commandv("sub-remove", this.merged.id)

    path.removeDir(this.getPath("cache/merge"))

    this.merged = nil

    return true
end

function this.isMergedSelected()

    local currentSid = mp.get_property_number("sid", 0)

    return this.merged and currentSid == this.merged.id
end

function this.getPath(key)

    local currentPath = mp.get_property("path") or ""

    if this.hashPath ~= currentPath then

        this.hash     = h.hash(currentPath)
        this.hashPath = currentPath
    end

    if key == "videofile" then

        return mp.get_property("path")
    elseif key == "cache" then

        return path.join({"%temp", this.tempDir})
    elseif key == "cache/merge" then

        return path.join({"%temp", this.tempDir, this.hash})
    elseif key == "cache/bottomfile" then

        return path.join({"%temp", this.tempDir, this.hash, "primary<ext>"})
    elseif key == "cache/topfile" then

        return path.join({"%temp", this.tempDir, this.hash, "secondary<ext>"})
    elseif key == "cache/mergedfile" then

        return path.join({"%temp", this.tempDir, this.hash, "merged.ass"})
    elseif key == "cache/progressfile" then

        return path.join({"%temp", this.tempDir, this.hash, "progress.txt"})
    end

    return nil
end

function this.updateList(currentTrackCount)

    if currentTrackCount ~= this.prevTrackCount or next(this.subtitles) == nil then

        this.subtitles = getSubtitleList()
    end
end

function this.addStyleOverride(overrides, style, property, value)

    overrides = overrides:gsub(",?"..h.escape(string.format("%s.%s", style, property)).."=[^,]*", "")

    if value then

        overrides = overrides ~= "" and overrides.."," or overrides
        overrides = overrides..string.format("%s.%s=%s", style, property, value)
    end

    return overrides
end

function this.load()

    local tracks = mp.get_property_native("track-list") or {}

    this.updateList(#tracks)

    local bottomSid = getSidByLanguage("bottom_languages")
    local topSid    = getSidByLanguage("top_languages")

    if bottomSid > 0 and bottomSid == topSid then

        h.notify("The IDs of the top and bottom subtitles are the same.", "sameinput", "error")

        return false
    end

    this.set(bottomSid, topSid)

    return this.bottom or this.top
end

function this.loadDefaults()

    local tracks = mp.get_property_native("track-list") or {}
    local bottomSid = mp.get_property_number("sid",           0)
    local topSid    = mp.get_property_number("secondary-sid", 0)

    this.updateList(#tracks)
    this.set(bottomSid, topSid)

    return this.bottom or this.top
end

function this.loadMerged()

    if path.checkPath(this.getPath("cache/mergedfile")) then

        mp.commandv("sub-add", this.getPath("cache/mergedfile"))

        local loaded = mp.get_property_native("current-tracks/sub")
        this.merged  = subtitle:new(loaded)

        return true
    end

    this.merged = nil

    return false
end

function this.cycleTop(step)

    local tracks        = mp.get_property_native("track-list") or {}
    local bottomSid     = mp.get_property_number("sid", 0)
    local currentTopSid = mp.get_property_number("secondary-sid", 0)

    this.updateList(#tracks)

    local subtitleIds = getSupportedSubtitleIds(bottomSid)

    if #subtitleIds == 1 then

        h.notify("No English or Turkish secondary subtitles found.", "findsubtitle", "warn")

        return 0
    end

    local currentIndex = 1

    for index, sid in ipairs(subtitleIds) do

        if sid == currentTopSid then

            currentIndex = index

            break
        end
    end

    local nextSid = subtitleIds[getNextIndex(subtitleIds, currentIndex, step)]

    this.set(bottomSid, nextSid)
    this.display()

    if config.secondary_on_hover and bottomSid > 0 and nextSid > 0 then

        this.toggle(1, 0)
    end

    if nextSid == 0 then

        mp.osd_message("Secondary subtitle disabled")
    else

        mp.osd_message(string.format("Secondary: %s", tostring(this.top)))
    end

    return nextSid
end

function this.toggle(bottom, top)

    if this.isMergedSelected() then

        local overrideMode = mp.get_property("sub-ass-override", "")

        if not (overrideMode == "yes" or overrideMode == "scale") then h.notify("Style override functionality only works with \"--sub-ass-override=yes\" or \"--sub-ass-override=scale\".", "styleoverride", "warn", nil, true) end

        local overrides = mp.get_property("sub-ass-style-overrides", "")

        if bottom == 1 then

            overrides = this.addStyleOverride(overrides, "Primary", "AlphaLevel", nil)
        else

            overrides = this.addStyleOverride(overrides, "Primary", "AlphaLevel", "255")
        end

        if top == 1 then

            overrides = this.addStyleOverride(overrides, "Secondary", "AlphaLevel", nil)
        else

            overrides = this.addStyleOverride(overrides, "Secondary", "AlphaLevel", "255")
        end

        mp.set_property("sub-ass-style-overrides", overrides)
    else

        mp.set_property_native("sub-visibility",           bottom == 1 and "yes" or "no")
        mp.set_property_native("secondary-sub-visibility", top == 1    and "yes" or "no")
    end
end

function this.set(bottomSid, topSid)

    this.bottom = bottomSid > 0 and this.subtitles[bottomSid] or nil
    this.top    = topSid > 0    and this.subtitles[topSid]    or nil
end

function this.display()

    mp.set_property_native("sid",           this.bottom and this.bottom.id or 0)
    mp.set_property_native("secondary-sid", this.top    and this.top.id    or 0)
end

function this.setup()

    if this.isSetup then return end

    this.isSetup = true

    local dual = this

    config = {

        --auto select
        top_languages          = "tr",
        bottom_languages       = "en",
        preferred_words        = "",
        rejected_words         = "sign,song",
        use_top_as_bottom      = true,

        --hover for secondary
        secondary_on_hover     = false,
        hover_height_percent   = 50,

        --key bindings
        secondary_forward_key       = "Alt+k",
        secondary_backward_key      = "Alt+K",
        secondary_position_down_key = "Ctrl+Alt+DOWN",
        secondary_position_up_key   = "Ctrl+Alt+UP",
        visibility_key              = "v",
        swap_key                    = "u",
        merge_key                   = "Alt+m",
        delete_merged_key           = "Alt+M",
        copy_key                    = "Alt+c",

        --merged subtitle
        top_style              = "fn:Noto Sans,fs:65,1c:&H0000DEFF,2c:&H000000FF,3c:&H00000000,4c:&H00000000,b:1,i:0,u:0,s:0,sx:100,sy:100,fsp:0,frz:0,bs:1,bord:4,shad:0,an:8,ml:0,mr:0,mv:40,enc:1",
        bottom_style           = "fn:Noto Sans,fs:65,1c:&H00FFFFFF,2c:&H000000FF,3c:&H00000000,4c:&H00000000,b:0,i:0,u:0,s:0,sx:100,sy:100,fsp:0,frz:0,bs:1,bord:1.5,shad:0,an:2,ml:0,mr:0,mv:40,enc:1",
        top_tags               = "",
        bottom_tags            = "\\blur4",
        detect_italics         = true,
        keep_ts                = "none", --bottom, top, none
        remove_sdh_entries     = false,
        remove_repeating_lines = false,

        --misc
        expand_subtitle_search = false,
        copy_format            = "(%s) %s"
    }

    options.read_options(config)

    local function getFallbackLanguage(otherLanguage)

        return otherLanguage == "en" and "tr" or "en"
    end

    local function normalizeLanguageSetting(value, fallback, otherLanguage)

        value = value and value:lower():gsub("_", "-") or ""

        for _, raw in ipairs(h.splitString(value)) do

            local lang = raw:match("^([a-z][a-z])")

            if supportedLanguages[lang] and lang ~= otherLanguage then

                return lang
            end
        end

        if fallback ~= otherLanguage then return fallback end

        return getFallbackLanguage(otherLanguage)
    end

    config.bottom_languages = normalizeLanguageSetting(config.bottom_languages, "en")
    config.top_languages    = normalizeLanguageSetting(config.top_languages, "tr", config.bottom_languages)

    local hideMode = 0
    local cSubs    = {bottom = {}, top = {}}
    local timer

    local function setSubtitles()

        local ok

        ok = dual.loadMerged()

        if ok then return end

        ok = dual.load()

        if not ok then return end

        if config.use_top_as_bottom and not dual.bottom and dual.top then

            dual.set(dual.top.id, 0)
        end

        if config.secondary_on_hover and dual.bottom and dual.top then

            dual.toggle(1, 0)
        end

        dual.display()

        h.log(string.format("bottom %s, top %s", dual.bottom and dual.bottom.id or "not set", dual.top and dual.top.id or "not set"))
    end

    local function mergeSubtitles()

        dual.loadDefaults()
        dual.merge()
    end

    local function deleteMergedFile()

        local ok

        ok = dual.deleteMerged()

        if ok then

            h.notify("File deleted!", "deletemergedfile", "info")
        else

            h.notify("File not found!", "deletemergedfile", "error")
        end
    end

    local function swapSubtitles()

        if dual.isMergedSelected() then

            local overrideMode = mp.get_property("sub-ass-override", "")

            if not (overrideMode == "yes" or overrideMode == "scale") then h.notify("Style override functionality only works with \"--sub-ass-override=yes\" or \"--sub-ass-override=scale\".", "styleoverride", "warn", nil, true) end

            local overrides  = mp.get_property("sub-ass-style-overrides", "")
            local alignments = {

                ["2"] = "2",
                ["8"] = "6"
            }

            if not string.find(overrides, "Primary.Alignment=", 1, true) then

                overrides = dual.addStyleOverride(overrides, "Primary",   "Alignment", alignments["8"])
                overrides = dual.addStyleOverride(overrides, "Secondary", "Alignment", alignments["2"])
            else

                overrides = dual.addStyleOverride(overrides, "Primary",   "Alignment", nil)
                overrides = dual.addStyleOverride(overrides, "Secondary", "Alignment", nil)
            end

            mp.set_property("sub-ass-style-overrides", overrides)

            return
        end

        dual.loadDefaults()

        if dual.bottom and dual.top then

            local tempBottomSid = dual.bottom.id
            local tempTopSid    = dual.top.id

            dual.set(0, 0)
            dual.display()

            dual.set(tempTopSid, tempBottomSid)
            dual.display()

            mp.osd_message(string.format("Top: %s\nBottom: %s", tostring(dual.top), tostring(dual.bottom)))
        else

            mp.osd_message("Subtitles not swapped")
        end
    end

    local function hideSubtitles()

        if hideMode == 0 then

            hideMode = hideMode + 1

            dual.toggle(1,0)

            mp.osd_message("Only the bottom subtitle visible")
        elseif hideMode == 1 then

            hideMode = hideMode + 1

            dual.toggle(0,0)

            mp.osd_message("Subtitles hidden")
        elseif hideMode == 2 then

            hideMode = 0

            dual.toggle(1,1)

            mp.osd_message("Subtitles visible")
        end
    end

    local function copySubtitlesOnPress()

        mp.set_property_bool("pause", false)
        mp.osd_message("▶ Collecting subtitles...", 9999)

        local merged = dual.isMergedSelected()

        local parseMerged = function (text)

            local text1 = ""

            for line in text:gmatch("%{%*P[^%}]*%}([^\n]+)") do

                text1 = text1..line:gsub("%s*\\N%s*", " ").." "
            end

            local text2 = ""

            for line in text:gmatch("%{%*S[^%}]*%}([^\n]+)") do

                text2 = text2..line:gsub("%s*\\N%s*", " ").." "
            end

            text1 = text1:gsub("%s+$", "")
            text2 = text2:gsub("%s+$", "")

            return text1, text2
        end

        local visible1 = mp.get_property_bool("sub-visibility")
        local visible2 = mp.get_property_bool("secondary-sub-visibility")

        timer = mp.add_periodic_timer(0.1, function()

            local bottomText, topText

            if merged and visible1 then

                bottomText, topText = parseMerged(mp.get_property("sub-text/ass"))
            else

                bottomText = visible1 and mp.get_property("sub-text", "")           or ""
                topText    = visible2 and mp.get_property("secondary-sub-text", "") or ""
            end

            if bottomText ~= "" then

                if #cSubs.bottom == 0 or cSubs.bottom[#cSubs.bottom] ~= bottomText then

                    table.insert(cSubs.bottom, bottomText)
                end
            end

            if topText ~= "" then

                if #cSubs.top == 0 or cSubs.top[#cSubs.top] ~= topText then

                    table.insert(cSubs.top, topText)
                end
            end
        end)
    end

    local function copySubtitlesOnUp()

        if timer then timer:kill() timer = nil end

        mp.set_property_bool("pause", true)
        mp.osd_message("", 0)

        if #cSubs.bottom > 0 or #cSubs.top > 0 then

            dual.loadDefaults()

            local sanitize = function (text)

                text = text:gsub("\n", " ")
                text = text:gsub("%s+", " ")

                return text
            end

            for i, v in ipairs(cSubs.bottom) do cSubs.bottom[i] = sanitize(v) end
            for i, v in ipairs(cSubs.top)    do cSubs.top[i]    = sanitize(v) end

            local result

            if #cSubs.bottom > 0 and #cSubs.top > 0 then

                result = string.format(config.copy_format.."\n"..config.copy_format, (dual.top and dual.top.lang or "S"), table.concat(cSubs.top, " "), (dual.bottom and dual.bottom.lang or "P"), table.concat(cSubs.bottom, " "))
            else

                result = #cSubs.top > 0 and table.concat(cSubs.top, " ") or table.concat(cSubs.bottom, " ")
            end

            mp.osd_message("⏸ Stopped. Subtitles copied.", 3)

            h.setClipboard(result)
        else

            h.notify("No subtitles on screen.", "copysubtitles", "error")
        end

        h.clearTable(cSubs.bottom)
        h.clearTable(cSubs.top)
    end

    local function updateSubtitleList(_, tracks)

        dual.updateList(#tracks)
    end

    local function cycleSecondary(mode)

        dual.cycleTop(mode == 1 and 1 or -1)
    end

    local function cycleSecondaryPosition(mode)

        if mode == 1 then

            mp.command("add secondary-sub-pos +1")
        else

            mp.command("add secondary-sub-pos -1")
        end
    end

    local function bindConfiguredKey(key, name, handler, flags)

        if not key or h.isEmpty(key) then return end

        mp.add_key_binding(key, name, handler, flags)
    end

    mp.register_event("file-loaded", setSubtitles)

    bindConfiguredKey(config.secondary_forward_key,       "dualsubtitles_secondaryforward",     function() cycleSecondary(1) end)
    bindConfiguredKey(config.secondary_backward_key,      "dualsubtitles_secondarybackward",    function() cycleSecondary(2) end)
    bindConfiguredKey(config.secondary_position_down_key, "dualsubtitles_increasesecondarypos", function() cycleSecondaryPosition(1) end, {repeatable = true})
    bindConfiguredKey(config.secondary_position_up_key,   "dualsubtitles_decreasesecondarypos", function() cycleSecondaryPosition(2) end, {repeatable = true})

    bindConfiguredKey(config.visibility_key,    "dualsubtitles_hide",         hideSubtitles)
    bindConfiguredKey(config.swap_key,          "dualsubtitles_swap",         swapSubtitles)
    bindConfiguredKey(config.merge_key,         "dualsubtitles_merge",        mergeSubtitles)
    bindConfiguredKey(config.delete_merged_key, "dualsubtitles_deletemerged", deleteMergedFile)
    bindConfiguredKey(config.copy_key,          "dualsubtitles_copy", function(state)

        if state.event == "down" then

            copySubtitlesOnPress()
        elseif state.event == "up" then

            copySubtitlesOnUp()
        end
    end, {complex = true})

    mp.observe_property("track-list", "native", updateSubtitleList)

    if config.expand_subtitle_search then

        local basePaths = mp.get_property_native("sub-file-paths")

        mp.add_hook("on_load", 50, function ()

            local newPaths = {}
            local filename = mp.get_property("filename/no-ext")

            for _, p in ipairs(basePaths) do

                table.insert(newPaths, p)
                table.insert(newPaths, p.."/"..filename)
            end

            if next(newPaths) ~= nil then mp.set_property_native("sub-file-paths", newPaths) end
        end)
    end

    if config.secondary_on_hover then

        mp.observe_property("mouse-pos", "native", function(_, mouse)

            if mp.get_property_number("sid", 0) == 0 or not dual.isMergedSelected() and mp.get_property_number("secondary-sid", 0) == 0 then return end

            local windowHeight = mp.get_property_number("osd-height")
            local hoverArea    = (windowHeight * config.hover_height_percent) / 100

            if mouse.y >= 0 and mouse.y <= hoverArea then

                dual.toggle(1,1)
            else

                dual.toggle(1,0)
            end
        end)
    end
end

this.setup()

return this
