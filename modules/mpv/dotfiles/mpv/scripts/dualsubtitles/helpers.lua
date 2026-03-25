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
