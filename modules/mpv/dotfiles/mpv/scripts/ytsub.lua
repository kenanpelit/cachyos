-- optionally import module, from SO
local function want(name)
  local out; if xpcall(
      function()  out = require(name) end,
      function(e) out = e end)
  then return out          -- success                                     
  else return nil, out end -- error                                       
end

local utils = require('mp.utils')
local input = require('mp.input')
local mp = require('mp')
local http = want("socket.http")
local https = want("ssl.https")

local options = {
    source_lang = "",
    source_langs = "en,tr",
    load_autosub_binding = "alt+y",
    autoload_autosub_binding = "alt+Y",
    cache_dir = ".cache/ytsub/",
    filter_sub_single_line = false,
}
require("mp.options").read_options(options)

local function trim(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

local function split_csv(value)
    local items = {}

    for item in string.gmatch(value or "", "([^,]+)") do
        local normalized_item = trim(item):lower()

        if normalized_item ~= "" then
            table.insert(items, normalized_item)
        end
    end

    return items
end

local function get_source_languages()
    local langs = split_csv(options.source_langs)

    if #langs == 0 then
        local fallback = trim(options.source_lang):lower()

        if fallback ~= "" then
            table.insert(langs, fallback)
        end
    end

    return langs
end

local function find_subtitle_key(subs, lang)
    local wanted = trim(lang):lower()

    if wanted == "" then
        return nil
    end

    for _, matcher in ipairs({
        function(key)
            return key == wanted
        end,
        function(key)
            return key:match("^" .. wanted .. "%-") ~= nil
        end,
        function(key)
            return key:match("^" .. wanted .. "%(") ~= nil
        end,
    }) do
        for key, _ in pairs(subs) do
            local normalized = key:lower()

            if matcher(normalized) then
                return key
            end
        end
    end

    return nil
end

local function get_available_subtitles(info_json)
    local auto_subs = info_json["automatic_captions"]

    if auto_subs ~= nil and next(auto_subs) ~= nil then
        return auto_subs, "automatic captions"
    end

    local subtitles = info_json["subtitles"]

    if subtitles ~= nil and next(subtitles) ~= nil then
        return subtitles, "subtitles"
    end

    return nil, nil
end

local function get_ytdl_target(info_json)
    local target = nil

    if info_json ~= nil then
        target = info_json["webpage_url"] or info_json["original_url"]
    end

    if target == nil or trim(target) == "" then
        target = mp.get_property("path")
    end

    target = trim(target)

    if target == "" then
        return nil
    end

    return target:gsub("^ytdl://", "")
end

local function append_unique(values, seen, value)
    local normalized = trim(value)

    if normalized == "" or seen[normalized] then
        return
    end

    table.insert(values, normalized)
    seen[normalized] = true
end

local function get_ytdl_candidates()
    local candidates = {}
    local seen = {}

    append_unique(candidates, seen, mp.get_property_native("user-data/mpv/ytdl/path"))
    append_unique(candidates, seen, mp.get_property("options/script-opts/ytdl_hook-ytdl_path"))
    append_unique(candidates, seen, "yt-dlp-mpv")
    append_unique(candidates, seen, "yt-dlp")

    return candidates
end

local function run_ytdl_command(extra_args, capture_output)
    local last_result = nil

    for _, ytdl_bin in ipairs(get_ytdl_candidates()) do
        local args = {ytdl_bin}

        for _, arg in ipairs(extra_args) do
            table.insert(args, arg)
        end

        local command = {
            name = "subprocess",
            playback_only = false,
            args = args,
        }

        if capture_output then
            command.capture_stdout = true
            command.capture_stderr = true
        end

        local result = mp.command_native(command)
        last_result = result

        if result.status == 0 then
            return result, ytdl_bin
        end

        if result.stderr ~= nil and trim(result.stderr) ~= "" then
            mp.msg.warn(string.format("[ytsub] %s failed: %s", ytdl_bin, trim(result.stderr)))
        end
    end

    return last_result, nil
end

local function query_subtitles_with_ytdl(info_json)
    local target = get_ytdl_target(info_json)

    if target == nil then
        return nil
    end

    local result, ytdl_bin = run_ytdl_command({
        "-J",
        "--no-playlist",
        "--skip-download",
        "--write-subs",
        "--write-auto-sub",
        "--sub-langs",
        "all,-live_chat",
        target,
    }, true)

    if result == nil or result.status ~= 0 or result.stdout == nil or trim(result.stdout) == "" then
        if result.stderr ~= nil and trim(result.stderr) ~= "" then
            mp.msg.warn("[ytsub] yt-dlp subtitle query failed: " .. trim(result.stderr))
        end
        return nil
    end

    mp.msg.info("[ytsub] subtitle metadata resolved via " .. tostring(ytdl_bin))

    return utils.parse_json(result.stdout)
end

-- create cache directory for subtitles if it doesn't exist
local res = utils.file_info(options.cache_dir)
if not res or not res.is_dir then
    local command
    local platform = mp.get_property_native("platform") or "unknown"

    if string.find(platform, "win") then
        -- This is Windows
        -- Convert path to use backslashes and run via cmd.exe
        options.cache_dir = utils.join_path(os.getenv("USERPROFILE"), options.cache_dir)
        options.cache_dir = string.gsub(options.cache_dir, "/", "\\")
        command = {
            name = "subprocess",
            args = {"cmd", "/c", "if not exist", options.cache_dir, "mkdir", options.cache_dir},
            playback_only = false,
        }
    else
        -- This is likely Linux, macOS, or another Unix-like system
        -- Use mkdir -p to create parent directories if they don't exist
        options.cache_dir =  utils.join_path(os.getenv("HOME"), options.cache_dir)
        command = {
            name = "subprocess",
            args = {"mkdir", "-p", options.cache_dir},
            playback_only = false,
        }
    end
    mp.command_native(command)
end

local function info(msg)
    mp.osd_message('ytsub : ' .. msg, 5)
end

local function filter_sub(path)
    local lines = {}
    for line in io.lines(path) do
        table.insert(lines, line)
    end
    local out = io.open(path, "w")
    for i, line in ipairs(lines) do
        if i < 5 or i % 8 == 5 or i % 8 == 7 or i % 8 == 0 then
            out:write(line)
            out:write("\n")
        end
    end
    out:close()
end

local function load_autosub(lang, sub_info, ytid, is_primary, source_type)
    if sub_info == nil then
        info("subtitle language unavailable: " .. tostring(lang))
        return false
    end

    local lang_name
    local url
    for _,v in pairs(sub_info) do
        lang_name = v["name"]
        if v["ext"] == "vtt" then
            url = v["url"]
        end
    end

    lang_name = lang_name or lang

    if url == nil then
        info("no VTT subtitle URL found for " .. tostring(lang_name))
        return false
    end

    info('loading '..lang_name)

    local subfile_base = utils.join_path(options.cache_dir, ytid) -- for yt-dlp
    local subfile = subfile_base .. "." .. lang .. ".vtt"

    local f = io.open(subfile, "r")
    local sub_is_available = false
    if f ~= nil then
        -- sub file already present
        io.close(f)
        sub_is_available = true
    else
        -- sub file not already present, download
        if http ~= nil and https ~= nil then
            -- downloading via direct url
            local client = http

            if string.match(url, "^https://") then
                client = https
            end

            local body, _ = client.request(url)
            if body ~= nil then
                f = assert(io.open(subfile, 'wb'))
                f:write(body)
                f:close()
                sub_is_available = true
            end
        else
            -- lua http modules not available, download via yt-dlp
            local args = {"--skip-download", "--sub-lang", lang}

            if source_type == "automatic captions" then
                table.insert(args, "--write-auto-sub")
            else
                table.insert(args, "--write-sub")
            end

            table.insert(args, "-o")
            table.insert(args, subfile_base)
            table.insert(args, ytid)

            local result, ytdl_bin = run_ytdl_command(args, false)

            if ytdl_bin ~= nil then
                mp.msg.info("[ytsub] subtitle download attempted via " .. ytdl_bin)
            end

            if result ~= nil and result.status == 0 then
                f = io.open(subfile, "r")
                if f ~= nil then
                    io.close(f)
                    sub_is_available = true
                end
            end
        end
        if sub_is_available and options.filter_sub_single_line then
            filter_sub(subfile)
        end
    end

    -- load the subtitle file as track ans select it
    if sub_is_available then
        if is_primary then
            mp.commandv("sub-add", subfile, "select", "youtube subtitle", lang)
        else
            -- compute the number of subtitle tracks in order to select the new track by id
            local n_tracks = mp.get_property_native("track-list/count")
            local n_subs = 0
            local i = 0
            while i < n_tracks do
                if mp.get_property_native("track-list/"..i.."/type") == "sub" then
                    n_subs = n_subs + 1
                end
                i = i + 1
            end
            mp.commandv("sub-add", subfile, "auto", "youtube subtitle", lang)
            mp.set_property("secondary-sid", n_subs + 1)
        end
        info(lang_name .. ' loaded')
        return true
    else
        info('failed to download ' .. lang_name)
        return false
    end
end

local function ytsub(is_auto)
    local ytdl_output = mp.get_property_native('user-data/mpv/ytdl/json-subprocess-result')
    if ytdl_output == nil then
        info('no ytdl info available')
        return
    end

    local j = utils.parse_json(ytdl_output['stdout'])

    if j == nil then
        info("failed to parse ytdl metadata")
        return
    end

    local subs, source_type = get_available_subtitles(j)

    if subs == nil then
        local refreshed = query_subtitles_with_ytdl(j)

        if refreshed ~= nil then
            j = refreshed
            subs, source_type = get_available_subtitles(j)
        end

        if subs == nil then
            info('no subtitles found')
            return
        end
    end

    if is_auto then
        local preferred_langs = get_source_languages()
        local selected = {}
        local seen = {}

        for _, lang in ipairs(preferred_langs) do
            local key = find_subtitle_key(subs, lang)

            if key ~= nil and not seen[key] then
                table.insert(selected, key)
                seen[key] = true
            end

            if #selected == 2 then
                break
            end
        end

        if #selected == 0 then
            info("preferred subtitles not found in " .. source_type .. ": " .. table.concat(preferred_langs, ", "))
            return
        end

        load_autosub(selected[1], subs[selected[1]], j["id"], true, source_type)

        if selected[2] ~= nil then
            load_autosub(selected[2], subs[selected[2]], j["id"], false, source_type)
        end

    else
        -- let the user select the language to load interactively
        local langs = {}
        for k,_ in pairs(subs) do
            table.insert(langs, k)
        end

        table.sort(langs)

        input.select({
            prompt = "Select a language",
            items = langs,
            submit = function(lang_id) load_autosub(langs[lang_id], subs[langs[lang_id]], j["id"], true, source_type) end,
        })
    end
end

mp.add_key_binding(options.load_autosub_binding, function() ytsub(false) end)
mp.add_key_binding(options.autoload_autosub_binding, function() ytsub(true) end)
