-- lyrics.lua (gömülü/embedded lyrics gösterici)
-- Ctrl+Shift+l: mevcut parçanın ID3/vorbis "lyrics" tag'ini (ffprobe ile) okuyup
-- ekranda göster/gizle. Bu tag'lerde zaman damgası yok (unsynced/USLT) —
-- senkron kayan gösterim değil, düz metin gösterilir. Sığmayan uzun lyrics'ler
-- için panel açıkken Up/Down/PgUp/PgDn/Home/End ile kaydırma, Esc ile kapatma
-- aktif olur (sadece panel açıkken; kapatınca tuşlar normal işlevine döner).
-- Harici .lrc dosyaları mpv tarafından zaten native destekleniyor; bu script
-- sadece dosyanın kendi içine gömülü lyrics'i hedefler. Ek bağımlılık yok,
-- sadece ffprobe (ffmpeg paketiyle gelir) kullanılır.

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")
local options = require("mp.options")

local OPT = {
	-- kısayol
	toggle_key_binding = "Ctrl+Shift+l",

	-- lyrics bulunamayınca / dosya yokken gösterilecek OSD mesajının süresi (sn)
	osd_duration = 3,
	not_found_message = "Lyrics bulunamadı",

	-- panelde aynı anda gösterilecek satır sayısı; fazlası kaydırılarak görülür
	max_visible_lines = 20,
	scroll_step = 1,
	page_step = 10,
}

options.read_options(OPT, mp.get_script_name())

----------------------------------------------------------------------
-- Durum
----------------------------------------------------------------------
local overlay = mp.create_osd_overlay("ass-events")
local shown = false
local pending = false

-- Aynı dosya için ffprobe'u tekrar tekrar çalıştırmamak için basit cache
local cached_path = nil
local cached_lyrics = nil -- string (bulundu) | false (arandı, yok) | nil (henüz aranmadı)

local lines = {} -- açık panelin tüm satırları
local scroll_offset = 0 -- ilk görünür satırın index'i (0-based)

----------------------------------------------------------------------
-- Yardımcılar
----------------------------------------------------------------------
local function escape_ass(text)
	-- Not: gsub 2 değer döner (string, sayım); son ifade olarak table.insert'e
	-- argüman geçilince bu ikinci değer sızıp "insert" imzasını bozar —
	-- parantezle tek değere zorluyoruz.
	return (text:gsub("{", "("):gsub("}", ")"))
end

local function split_lines(raw)
	local text = raw:gsub("\r\n", "\n"):gsub("\r", "\n")
	local result = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		table.insert(result, line)
	end
	return result
end

----------------------------------------------------------------------
-- format.tags içinden "lyrics" ile başlayan alanı bul (lyrics, lyrics-eng, lyrics-XXX, ...)
-- "-xxx" (ISO 639-2 "belirsiz dil") diğerlerine göre en son tercih edilir.
----------------------------------------------------------------------
local function extract_lyrics_from_tags(tags)
	if type(tags) ~= "table" then
		return nil
	end

	local primary, fallback = {}, {}
	for k, _ in pairs(tags) do
		if k:lower():match("^lyrics") then
			if k:lower():match("%-xxx$") then
				table.insert(fallback, k)
			else
				table.insert(primary, k)
			end
		end
	end

	local function ci_sort(list)
		table.sort(list, function(a, b) return a:lower() < b:lower() end)
	end
	ci_sort(primary)
	ci_sort(fallback)

	for _, list in ipairs({ primary, fallback }) do
		for _, k in ipairs(list) do
			local v = tags[k]
			if type(v) == "string" and v:match("%S") then
				return v
			end
		end
	end

	return nil
end

----------------------------------------------------------------------
-- İleri bildirim: aşağıdaki fonksiyonlar birbirine çapraz referans veriyor
----------------------------------------------------------------------
local hide_overlay
local enable_scroll_keys
local disable_scroll_keys

----------------------------------------------------------------------
-- Görünür pencereyi (scroll_offset..+max_visible_lines) çiz
----------------------------------------------------------------------
local function render_visible()
	local total = #lines
	local last = math.min(total, scroll_offset + OPT.max_visible_lines)

	local visible = {}
	for i = scroll_offset + 1, last do
		table.insert(visible, escape_ass(lines[i]))
	end

	local ass = "{\\an7\\fs28\\bord2\\shad1}" .. table.concat(visible, "\\N")

	if total > OPT.max_visible_lines then
		ass = ass .. "\\N\\N{\\fs16}[" .. (scroll_offset + 1) .. "-" .. last .. " / " .. total
			.. " \xE2\x80\x94 \xE2\x86\x91\xE2\x86\x93 PgUp/PgDn Home/End, Esc kapat]"
	end

	overlay.data = ass
	overlay:update()
end

----------------------------------------------------------------------
-- Kaydırma
----------------------------------------------------------------------
local function clamp_offset(offset)
	local max_offset = math.max(0, #lines - OPT.max_visible_lines)
	if offset < 0 then
		return 0
	elseif offset > max_offset then
		return max_offset
	end
	return offset
end

local function scroll_to(offset)
	local new_offset = clamp_offset(offset)
	if new_offset ~= scroll_offset then
		scroll_offset = new_offset
		render_visible()
	end
end

local function scroll_by(delta)
	scroll_to(scroll_offset + delta)
end

----------------------------------------------------------------------
-- Panel açıkken aktif olan kaydırma/kapatma tuşları (forced: geçici olarak
-- kullanıcının normal Up/Down/PgUp/PgDn/Esc bağlarının önüne geçer; panel
-- kapanınca kaldırılır ve normal davranış geri gelir)
----------------------------------------------------------------------
local SCROLL_BINDINGS = {
	{ "DOWN", "lyrics-scroll-down", function() scroll_by(OPT.scroll_step) end, { repeatable = true } },
	{ "UP", "lyrics-scroll-up", function() scroll_by(-OPT.scroll_step) end, { repeatable = true } },
	{ "PGDWN", "lyrics-scroll-pagedown", function() scroll_by(OPT.page_step) end, { repeatable = true } },
	{ "PGUP", "lyrics-scroll-pageup", function() scroll_by(-OPT.page_step) end, { repeatable = true } },
	{ "HOME", "lyrics-scroll-top", function() scroll_to(0) end, nil },
	{ "END", "lyrics-scroll-bottom", function() scroll_to(math.huge) end, nil },
}

enable_scroll_keys = function()
	for _, b in ipairs(SCROLL_BINDINGS) do
		mp.add_forced_key_binding(b[1], b[2], b[3], b[4])
	end
	mp.add_forced_key_binding("ESC", "lyrics-close", function() hide_overlay() end)
end

disable_scroll_keys = function()
	for _, b in ipairs(SCROLL_BINDINGS) do
		mp.remove_key_binding(b[2])
	end
	mp.remove_key_binding("lyrics-close")
end

----------------------------------------------------------------------
-- Göster / gizle
----------------------------------------------------------------------
hide_overlay = function()
	if shown then
		overlay:remove()
		shown = false
		disable_scroll_keys()
	end
end

local function show_lyrics_overlay(text)
	lines = split_lines(text)
	scroll_offset = 0
	render_visible()
	if not shown then
		enable_scroll_keys()
	end
	shown = true
end

----------------------------------------------------------------------
-- ffprobe ile format_tags'ı async oku (playback'i bloklamaz)
----------------------------------------------------------------------
local function probe_tags_async(path, callback)
	local command = {
		name = "subprocess",
		playback_only = false,
		capture_stdout = true,
		capture_stderr = false,
		args = { "ffprobe", "-v", "quiet", "-print_format", "json", "-show_entries", "format_tags", "--", path },
	}

	mp.command_native_async(command, function(success, result)
		if not success or result == nil or result.stdout == nil then
			callback(nil)
			return
		end

		local json = utils.parse_json(result.stdout)
		if json == nil or json.format == nil then
			callback(nil)
			return
		end

		callback(extract_lyrics_from_tags(json.format.tags))
	end)
end

----------------------------------------------------------------------
-- Ana toggle
----------------------------------------------------------------------
local function toggle_lyrics()
	if shown then
		hide_overlay()
		return
	end

	local path = mp.get_property("path")
	if not path or path == "" then
		mp.osd_message("lyrics: oynatılan dosya yok", OPT.osd_duration)
		return
	end

	if cached_path == path and cached_lyrics ~= nil then
		if cached_lyrics == false then
			mp.osd_message(OPT.not_found_message, OPT.osd_duration)
		else
			show_lyrics_overlay(cached_lyrics)
		end
		return
	end

	if pending then
		return
	end
	pending = true

	msg.debug("probing embedded lyrics:", path)

	probe_tags_async(path, function(lyrics)
		pending = false

		-- Yanıt gelene kadar dosya değiştiyse sonucu at
		if mp.get_property("path") ~= path then
			return
		end

		cached_path = path
		cached_lyrics = lyrics or false

		if lyrics then
			show_lyrics_overlay(lyrics)
		else
			mp.osd_message(OPT.not_found_message, OPT.osd_duration)
		end
	end)
end

----------------------------------------------------------------------
-- Dosya değişince: paneli kapat, cache'i sıfırla
----------------------------------------------------------------------
mp.register_event("file-loaded", function()
	hide_overlay()
	cached_path = nil
	cached_lyrics = nil
end)

----------------------------------------------------------------------
-- Keybinding
----------------------------------------------------------------------
if OPT.toggle_key_binding and OPT.toggle_key_binding ~= "" then
	mp.add_key_binding(OPT.toggle_key_binding, "toggle_lyrics", toggle_lyrics)
end
