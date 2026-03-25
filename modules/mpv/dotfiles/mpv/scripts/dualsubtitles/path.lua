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
