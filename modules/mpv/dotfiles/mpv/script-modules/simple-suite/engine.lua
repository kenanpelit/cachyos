-- simple-suite/engine.lua
-- Paylaşılan liste motoru: SimpleHistory / SimpleBookmark / SmartCopyPaste_II
-- (Eisa AlAwadhi'nin scriptlerinde birebir tekrarlanan gövde; tek kopyaya indirildi.)
--
-- Bu dosya bir modül DEĞİL. Her script kendi ortamını kurup
--   local f = assert(loadfile(path)); setfenv(f, env); f()
-- ile bu gövdeyi kendi ortamına yükler. Fonksiyonlar env'e global olarak düşer
-- ve script'in state'ini (o, list_contents, list_cursor, ...) doğrudan görür.
--
-- Script'in SAĞLAMASI gereken kancalar (kayıt formatına bağlı, script'e özel):
--   draw_list, display_list, write_log, read_log_table,
--   list_empty_error_msg, mark_chapter, list_close_and_trash_collection
--
-- ÜRETİLMİŞ DOSYA: kaynak SimpleHistory.lua idi. Elle düzenlenebilir,
-- ama üç script de bunu paylaşır - değişiklik üçünü birden etkiler.


function bind_keys(keys, name, func, opts)
	if not keys then
		mp.add_forced_key_binding(keys, name, func, opts)
		return
	end

	for i = 1, #keys do
		if i == 1 then
			mp.add_forced_key_binding(keys[i], name, func, opts)
		else
			mp.add_forced_key_binding(keys[i], name .. i, func, opts)
		end
	end
end

function bind_search_keys()
	mp.add_forced_key_binding('a', 'search_string_a', function() update_search_results('a') end, 'repeatable')
	mp.add_forced_key_binding('b', 'search_string_b', function() update_search_results('b') end, 'repeatable')
	mp.add_forced_key_binding('c', 'search_string_c', function() update_search_results('c') end, 'repeatable')
	mp.add_forced_key_binding('d', 'search_string_d', function() update_search_results('d') end, 'repeatable')
	mp.add_forced_key_binding('e', 'search_string_e', function() update_search_results('e') end, 'repeatable')
	mp.add_forced_key_binding('f', 'search_string_f', function() update_search_results('f') end, 'repeatable')
	mp.add_forced_key_binding('g', 'search_string_g', function() update_search_results('g') end, 'repeatable')
	mp.add_forced_key_binding('h', 'search_string_h', function() update_search_results('h') end, 'repeatable')
	mp.add_forced_key_binding('i', 'search_string_i', function() update_search_results('i') end, 'repeatable')
	mp.add_forced_key_binding('j', 'search_string_j', function() update_search_results('j') end, 'repeatable')
	mp.add_forced_key_binding('k', 'search_string_k', function() update_search_results('k') end, 'repeatable')
	mp.add_forced_key_binding('l', 'search_string_l', function() update_search_results('l') end, 'repeatable')
	mp.add_forced_key_binding('m', 'search_string_m', function() update_search_results('m') end, 'repeatable')
	mp.add_forced_key_binding('n', 'search_string_n', function() update_search_results('n') end, 'repeatable')
	mp.add_forced_key_binding('o', 'search_string_o', function() update_search_results('o') end, 'repeatable')
	mp.add_forced_key_binding('p', 'search_string_p', function() update_search_results('p') end, 'repeatable')
	mp.add_forced_key_binding('q', 'search_string_q', function() update_search_results('q') end, 'repeatable')
	mp.add_forced_key_binding('r', 'search_string_r', function() update_search_results('r') end, 'repeatable')
	mp.add_forced_key_binding('s', 'search_string_s', function() update_search_results('s') end, 'repeatable')
	mp.add_forced_key_binding('t', 'search_string_t', function() update_search_results('t') end, 'repeatable')
	mp.add_forced_key_binding('u', 'search_string_u', function() update_search_results('u') end, 'repeatable')
	mp.add_forced_key_binding('v', 'search_string_v', function() update_search_results('v') end, 'repeatable')
	mp.add_forced_key_binding('w', 'search_string_w', function() update_search_results('w') end, 'repeatable')
	mp.add_forced_key_binding('x', 'search_string_x', function() update_search_results('x') end, 'repeatable')
	mp.add_forced_key_binding('y', 'search_string_y', function() update_search_results('y') end, 'repeatable')
	mp.add_forced_key_binding('z', 'search_string_z', function() update_search_results('z') end, 'repeatable')

	mp.add_forced_key_binding('A', 'search_string_A', function() update_search_results('A') end, 'repeatable')
	mp.add_forced_key_binding('B', 'search_string_B', function() update_search_results('B') end, 'repeatable')
	mp.add_forced_key_binding('C', 'search_string_C', function() update_search_results('C') end, 'repeatable')
	mp.add_forced_key_binding('D', 'search_string_D', function() update_search_results('D') end, 'repeatable')
	mp.add_forced_key_binding('E', 'search_string_E', function() update_search_results('E') end, 'repeatable')
	mp.add_forced_key_binding('F', 'search_string_F', function() update_search_results('F') end, 'repeatable')
	mp.add_forced_key_binding('G', 'search_string_G', function() update_search_results('G') end, 'repeatable')
	mp.add_forced_key_binding('H', 'search_string_H', function() update_search_results('H') end, 'repeatable')
	mp.add_forced_key_binding('I', 'search_string_I', function() update_search_results('I') end, 'repeatable')
	mp.add_forced_key_binding('J', 'search_string_J', function() update_search_results('J') end, 'repeatable')
	mp.add_forced_key_binding('K', 'search_string_K', function() update_search_results('K') end, 'repeatable')
	mp.add_forced_key_binding('L', 'search_string_L', function() update_search_results('L') end, 'repeatable')
	mp.add_forced_key_binding('M', 'search_string_M', function() update_search_results('M') end, 'repeatable')
	mp.add_forced_key_binding('N', 'search_string_N', function() update_search_results('N') end, 'repeatable')
	mp.add_forced_key_binding('O', 'search_string_O', function() update_search_results('O') end, 'repeatable')
	mp.add_forced_key_binding('P', 'search_string_P', function() update_search_results('P') end, 'repeatable')
	mp.add_forced_key_binding('Q', 'search_string_Q', function() update_search_results('Q') end, 'repeatable')
	mp.add_forced_key_binding('R', 'search_string_R', function() update_search_results('R') end, 'repeatable')
	mp.add_forced_key_binding('S', 'search_string_S', function() update_search_results('S') end, 'repeatable')
	mp.add_forced_key_binding('T', 'search_string_T', function() update_search_results('T') end, 'repeatable')
	mp.add_forced_key_binding('U', 'search_string_U', function() update_search_results('U') end, 'repeatable')
	mp.add_forced_key_binding('V', 'search_string_V', function() update_search_results('V') end, 'repeatable')
	mp.add_forced_key_binding('W', 'search_string_W', function() update_search_results('W') end, 'repeatable')
	mp.add_forced_key_binding('X', 'search_string_X', function() update_search_results('X') end, 'repeatable')
	mp.add_forced_key_binding('Y', 'search_string_Y', function() update_search_results('Y') end, 'repeatable')
	mp.add_forced_key_binding('Z', 'search_string_Z', function() update_search_results('Z') end, 'repeatable')

	mp.add_forced_key_binding('1', 'search_string_1', function() update_search_results('1') end, 'repeatable')
	mp.add_forced_key_binding('2', 'search_string_2', function() update_search_results('2') end, 'repeatable')
	mp.add_forced_key_binding('3', 'search_string_3', function() update_search_results('3') end, 'repeatable')
	mp.add_forced_key_binding('4', 'search_string_4', function() update_search_results('4') end, 'repeatable')
	mp.add_forced_key_binding('5', 'search_string_5', function() update_search_results('5') end, 'repeatable')
	mp.add_forced_key_binding('6', 'search_string_6', function() update_search_results('6') end, 'repeatable')
	mp.add_forced_key_binding('7', 'search_string_7', function() update_search_results('7') end, 'repeatable')
	mp.add_forced_key_binding('8', 'search_string_8', function() update_search_results('8') end, 'repeatable')
	mp.add_forced_key_binding('9', 'search_string_9', function() update_search_results('9') end, 'repeatable')
	mp.add_forced_key_binding('0', 'search_string_0', function() update_search_results('0') end, 'repeatable')

	mp.add_forced_key_binding('SPACE', 'search_string_space', function() update_search_results(' ') end, 'repeatable')
	mp.add_forced_key_binding('`', 'search_string_`', function() update_search_results('`') end, 'repeatable')
	mp.add_forced_key_binding('~', 'search_string_~', function() update_search_results('~') end, 'repeatable')
	mp.add_forced_key_binding('!', 'search_string_!', function() update_search_results('!') end, 'repeatable')
	mp.add_forced_key_binding('@', 'search_string_@', function() update_search_results('@') end, 'repeatable')
	mp.add_forced_key_binding('SHARP', 'search_string_sharp', function() update_search_results('#') end, 'repeatable')
	mp.add_forced_key_binding('$', 'search_string_$', function() update_search_results('$') end, 'repeatable')
	mp.add_forced_key_binding('%', 'search_string_percentage', function() update_search_results('%') end, 'repeatable')
	mp.add_forced_key_binding('^', 'search_string_^', function() update_search_results('^') end, 'repeatable')
	mp.add_forced_key_binding('&', 'search_string_&', function() update_search_results('&') end, 'repeatable')
	mp.add_forced_key_binding('*', 'search_string_*', function() update_search_results('*') end, 'repeatable')
	mp.add_forced_key_binding('(', 'search_string_(', function() update_search_results('(') end, 'repeatable')
	mp.add_forced_key_binding(')', 'search_string_)', function() update_search_results(')') end, 'repeatable')
	mp.add_forced_key_binding('-', 'search_string_-', function() update_search_results('-') end, 'repeatable')
	mp.add_forced_key_binding('_', 'search_string__', function() update_search_results('_') end, 'repeatable')
	mp.add_forced_key_binding('=', 'search_string_=', function() update_search_results('=') end, 'repeatable')
	mp.add_forced_key_binding('+', 'search_string_+', function() update_search_results('+') end, 'repeatable')
	mp.add_forced_key_binding('\\', 'search_string_\\', function() update_search_results('\\') end, 'repeatable')
	mp.add_forced_key_binding('|', 'search_string_|', function() update_search_results('|') end, 'repeatable')
	mp.add_forced_key_binding(']', 'search_string_]', function() update_search_results(']') end, 'repeatable')
	mp.add_forced_key_binding('}', 'search_string_rightcurly', function() update_search_results('}') end, 'repeatable')
	mp.add_forced_key_binding('[', 'search_string_[', function() update_search_results('[') end, 'repeatable')
	mp.add_forced_key_binding('{', 'search_string_leftcurly', function() update_search_results('{') end, 'repeatable')
	mp.add_forced_key_binding('\'', 'search_string_\'', function() update_search_results('\'') end, 'repeatable')
	mp.add_forced_key_binding('\"', 'search_string_\"', function() update_search_results('\"') end, 'repeatable')
	mp.add_forced_key_binding(';', 'search_string_semicolon', function() update_search_results(';') end, 'repeatable')
	mp.add_forced_key_binding(':', 'search_string_:', function() update_search_results(':') end, 'repeatable')
	mp.add_forced_key_binding('/', 'search_string_/', function() update_search_results('/') end, 'repeatable')
	mp.add_forced_key_binding('?', 'search_string_?', function() update_search_results('?') end, 'repeatable')
	mp.add_forced_key_binding('.', 'search_string_.', function() update_search_results('.') end, 'repeatable')
	mp.add_forced_key_binding('>', 'search_string_>', function() update_search_results('>') end, 'repeatable')
	mp.add_forced_key_binding(',', 'search_string_,', function() update_search_results(',') end, 'repeatable')
	mp.add_forced_key_binding('<', 'search_string_<', function() update_search_results('<') end, 'repeatable')

	mp.add_forced_key_binding('bs', 'search_string_del', function() update_search_results('', 'string_del') end, 'repeatable')
	bind_keys(o.list_close_keybind, 'search_exit', function() list_search_exit() end)
	bind_keys(o.list_search_not_typing_mode_keybind, 'search_string_not_typing', function()list_search_not_typing_mode(false) end)

	if o.search_not_typing_smartly then
		bind_keys(o.next_filter_sequence_keybind, 'list-filter-next', function() list_filter_next() list_search_not_typing_mode(true) end)
		bind_keys(o.previous_filter_sequence_keybind, 'list-filter-previous', function() list_filter_previous() list_search_not_typing_mode(true) end)
		bind_keys(o.list_delete_keybind, 'list-delete', function() list_delete() list_search_not_typing_mode(true) end)
		bind_keys(o.list_delete_highlighted_keybind, 'list-delete-highlight', function() list_delete('highlight') list_search_not_typing_mode(true) end)
	end
end

function contain_value(tab, val)
	if not tab then return msg.error('check value passed') end
	if not val then return msg.error('check value passed') end

	for index, value in ipairs(tab) do
		if value.match(string.lower(val), string.lower(value)) then
			return true
		end
	end

	return false
end

function delete_log_entry(multiple, round, target_path, target_time, entry_limit)
	if not target_path then target_path = filePath end
	if not target_time then target_time = seekTime end
	list_contents = read_log_table()
	if not list_contents or not list_contents[1] then return end
	local trigger_delete = false

	if not multiple then
		for i = #list_contents, 1, -1 do
			if not round then
				if list_contents[i].found_path == target_path and tonumber(list_contents[i].found_time) == target_time then
					table.remove(list_contents, i)
					trigger_delete = true
					break
				end
			else
				if list_contents[i].found_path == target_path and math.floor(tonumber(list_contents[i].found_time)) == target_time then
					table.remove(list_contents, i)
					trigger_delete = true
					break
				end
			end
		end
	else
		for i = #list_contents, 1, -1 do
			if not round then
				if list_contents[i].found_path == target_path and tonumber(list_contents[i].found_time) == target_time then
					table.remove(list_contents, i)
					trigger_delete = true
				end
			else
				if list_contents[i].found_path == target_path and math.floor(tonumber(list_contents[i].found_time)) == target_time then
					table.remove(list_contents, i)
					trigger_delete = true
				end
			end
		end
	end

	if entry_limit and entry_limit > -1 then
		local entries_found = 0
		for i = #list_contents, 1, -1 do
			if list_contents[i].found_path == target_path and entries_found < entry_limit then
				entries_found = entries_found + 1
			elseif list_contents[i].found_path == target_path and entries_found >= entry_limit then
				table.remove(list_contents,i)
				trigger_delete = true
			end
		end
	end

	if not trigger_delete then return end
	local f = io.open(log_fullpath, "w+")
	if list_contents ~= nil and list_contents[1] then
		for i = 1, #list_contents do
			f:write(("%s\n"):format(list_contents[i].found_line))
		end
	end
	f:close()
end

function delete_log_entry_highlighted()
	if not list_highlight_cursor or not list_highlight_cursor[1] then return end
	list_contents = read_log_table()
	if not list_contents or not list_contents[1] then return end

	local list_contents_length = #list_contents

	for i = 1, list_contents_length do
		for j=1, #list_highlight_cursor do
			if list_contents[list_contents_length+1-i] then
				if list_contents[list_contents_length+1-i].found_sequence == list_highlight_cursor[j][2].found_sequence then
					table.remove(list_contents, list_contents_length+1-i)
				end
			end
		end
	end

	msg.info("Deleted "..#list_highlight_cursor.." Item/s")

	list_unhighlight_all()

	local f = io.open(log_fullpath, "w+")
	if list_contents ~= nil and list_contents[1] then
		for i = 1, #list_contents do
			f:write(("%s\n"):format(list_contents[i].found_line))
		end
	end
	f:close()

end

function delete_log_entry_specific(target_index, target_path, target_time)
	local trigger_delete = false
	list_contents = read_log_table()
	if not list_contents or not list_contents[1] then return end
	if target_index == 'last' then target_index = #list_contents end
	if not target_index then return end

	if target_index and target_path and target_time then
		if list_contents[target_index].found_path == target_path and tonumber(list_contents[target_index].found_time) == target_time then
			table.remove(list_contents, target_index)
			trigger_delete = true
		end
	elseif target_index and target_path and not target_time then
		if list_contents[target_index].found_path == target_path then
			table.remove(list_contents, target_index)
			trigger_delete = true
		end
	elseif target_index and target_time and not target_path then
		if tonumber(list_contents[target_index].found_time) == target_time then
			table.remove(list_contents, target_index)
			trigger_delete = true
		end
	elseif target_index and not target_path and not target_time then
		table.remove(list_contents, target_index)
		trigger_delete = true
	end

	if not trigger_delete then return end
	local f = io.open(log_fullpath, "w+")
	if list_contents ~= nil and list_contents[1] then
		for i = 1, #list_contents do
			f:write(("%s\n"):format(list_contents[i].found_line))
		end
	end
	f:close()
end

function delete_selected()
	filePath = list_contents[#list_contents - list_cursor + 1].found_path
	fileTitle = list_contents[#list_contents - list_cursor + 1].found_name
	seekTime = tonumber(list_contents[#list_contents - list_cursor + 1].found_time)
	if not filePath and not seekTime then
		msg.info("Failed to delete")
		return
	end
	delete_log_entry()
	msg.info("Deleted \"" .. filePath .. "\" | " .. format_time(seekTime))
	filePath, fileTitle, fileLength = get_file()
end

function esc_string(str)
	return str:gsub("([%p])", "%%%1")
end

---------Start of LogManager---------
--LogManager (Read and Format the List from Log)--

function file_exists(name)
	local f = io.open(name, "r")
	if f ~= nil then io.close(f) return true else return false end
end

function format_time(seconds, sep, decimals, style)
	local function divmod (a, b)
		return math.floor(a / b), a % b
	end
	decimals = decimals == nil and 3 or decimals

	local s = seconds
	local h, s = divmod(s, 60*60)
	local m, s = divmod(s, 60)

	if decimals == 'truncate' then
		s = math.floor(s)
		decimals = 0
		if style == 'timestamp' then
			seconds = math.floor(seconds)
		end
	end

	if not style or style == '' or style == 'default' then
		local second_format = string.format("%%0%d.%df", 2+(decimals > 0 and decimals+1 or 0), decimals)
		sep = sep and sep or ":"
		return string.format("%02d"..sep.."%02d"..sep..second_format, h, m, s)
	elseif style == 'hms' or style == 'hms-full' then
	  sep = sep ~= nil and sep or " "
	  if style == 'hms-full' or h > 0 then
		return string.format("%dh"..sep.."%dm"..sep.."%." .. tostring(decimals) .. "fs", h, m, s)
	  elseif m > 0 then
		return string.format("%dm"..sep.."%." .. tostring(decimals) .. "fs", m, s)
	  else
		return string.format("%." .. tostring(decimals) .. "fs", s)
	  end
	elseif style == 'timestamp' then
		return string.format("%." .. tostring(decimals) .. "f", seconds)
	elseif style == 'timestamp-concise' then
		return seconds
	end
end

function get_file()
	local path = mp.get_property('path')
	if not path then return end

	local length = (mp.get_property_number('duration') or 0)

	local title = mp.get_property('media-title'):gsub("\"", "")


	if starts_protocol(o.logging_protocols, path) and o.prefer_filename_over_title == 'protocols' then
		title = mp.get_property('filename'):gsub("\"", "")
	elseif not starts_protocol(o.logging_protocols, path) and o.prefer_filename_over_title == 'local' then
		title = mp.get_property('filename'):gsub("\"", "")
	elseif o.prefer_filename_over_title == 'all' then
		title = mp.get_property('filename'):gsub("\"", "")
	end

	return path, title, length
end

function get_list_keybinds()
	bind_keys(o.list_ignored_keybind, 'ignore')
	bind_keys(o.list_move_up_keybind, 'move-up', list_move_up, 'repeatable')
	bind_keys(o.list_move_down_keybind, 'move-down', list_move_down, 'repeatable')
	bind_keys(o.list_move_first_keybind, 'move-first', list_move_first, 'repeatable')
	bind_keys(o.list_move_last_keybind, 'move-last', list_move_last, 'repeatable')
	bind_keys(o.list_page_up_keybind, 'page-up', list_page_up, 'repeatable')
	bind_keys(o.list_page_down_keybind, 'page-down', list_page_down, 'repeatable')
	bind_keys(o.list_select_keybind, 'list-select', list_select)
	bind_keys(o.list_add_playlist_keybind, 'list-add-playlist', list_add_playlist)
	bind_keys(o.list_add_playlist_highlighted_keybind, 'list-add-playlist-highlight', function()list_add_playlist('highlight')end)
	bind_keys(o.list_delete_keybind, 'list-delete', list_delete)
	bind_keys(o.list_delete_highlighted_keybind, 'list-delete-highlight', function()list_delete('highlight')end)
	bind_keys(o.next_filter_sequence_keybind, 'list-filter-next', list_filter_next)
	bind_keys(o.previous_filter_sequence_keybind, 'list-filter-previous', list_filter_previous)
	bind_keys(o.list_search_activate_keybind, 'list-search-activate', list_search_activate)
	bind_keys(o.list_highlight_all_keybind, 'list-highlight-all', list_highlight_all)
	bind_keys(o.list_unhighlight_all_keybind, 'list-unhighlight-all', list_unhighlight_all)
	bind_keys(o.list_cycle_sort_keybind, 'list-cycle-sort', list_cycle_sort)

	for i = 1, #o.list_highlight_move_keybind do
		for j = 1, #o.list_move_up_keybind do
			mp.add_forced_key_binding(o.list_highlight_move_keybind[i]..'+'..o.list_move_up_keybind[j], 'highlight-move-up'..j, function()list_move_up('highlight') end, 'repeatable')
		end
		for j = 1, #o.list_move_down_keybind do
			mp.add_forced_key_binding(o.list_highlight_move_keybind[i]..'+'..o.list_move_down_keybind[j], 'highlight-move-down'..j, function()list_move_down('highlight') end, 'repeatable')
		end
		for j = 1, #o.list_move_first_keybind do
			mp.add_forced_key_binding(o.list_highlight_move_keybind[i]..'+'..o.list_move_first_keybind[j], 'highlight-move-first'..j, function()list_move_first('highlight') end, 'repeatable')
		end
		for j = 1, #o.list_move_last_keybind do
			mp.add_forced_key_binding(o.list_highlight_move_keybind[i]..'+'..o.list_move_last_keybind[j], 'highlight-move-last'..j, function()list_move_last('highlight') end, 'repeatable')
		end
		for j = 1, #o.list_page_up_keybind do
			mp.add_forced_key_binding(o.list_highlight_move_keybind[i]..'+'..o.list_page_up_keybind[j], 'highlight-page-up'..j, function()list_page_up('highlight') end, 'repeatable')
		end
		for j = 1, #o.list_page_down_keybind do
			mp.add_forced_key_binding(o.list_highlight_move_keybind[i]..'+'..o.list_page_down_keybind[j], 'highlight-page-down'..j, function()list_page_down('highlight') end, 'repeatable')
		end
	end

	if not search_active then
		bind_keys(o.list_close_keybind, 'list-close', list_close_and_trash_collection)
	end

	for i = 1, #o.list_filter_jump_keybind do
		mp.add_forced_key_binding(o.list_filter_jump_keybind[i][1], 'list-filter-jump'..i, function()display_list(o.list_filter_jump_keybind[i][2]) end)
	end

	for i = 1, #o.open_list_keybind do
		if i == 1 then
			mp.remove_key_binding('open-list')
		else
			mp.remove_key_binding('open-list'..i)
		end
	end

	if o.quickselect_0to9_keybind and o.list_show_amount <= 10 then
		mp.add_forced_key_binding("1", "recent-1", function()load(list_start + 1) end)
		mp.add_forced_key_binding("2", "recent-2", function()load(list_start + 2) end)
		mp.add_forced_key_binding("3", "recent-3", function()load(list_start + 3) end)
		mp.add_forced_key_binding("4", "recent-4", function()load(list_start + 4) end)
		mp.add_forced_key_binding("5", "recent-5", function()load(list_start + 5) end)
		mp.add_forced_key_binding("6", "recent-6", function()load(list_start + 6) end)
		mp.add_forced_key_binding("7", "recent-7", function()load(list_start + 7) end)
		mp.add_forced_key_binding("8", "recent-8", function()load(list_start + 8) end)
		mp.add_forced_key_binding("9", "recent-9", function()load(list_start + 9) end)
		mp.add_forced_key_binding("0", "recent-0", function()load(list_start + 10) end)
	end
end

function get_list_sort(filter)
	if not filter then filter = filterName end

	local sort
	for i=1, #o.list_filters_sort do
		if o.list_filters_sort[i][1] == filter then
			if has_value(available_sorts, o.list_filters_sort[i][2]) then sort = o.list_filters_sort[i][2] end
			break
		end
	end

	if not sort and has_value(available_sorts, o.list_default_sort) then sort = o.list_default_sort end

	if not sort then sort = 'added-asc' end

	return sort
end

function get_page_properties(filter)
	if not filter then return end
	for i=1, #list_pages do
		if list_pages[i][1] == filter then
			list_cursor = list_pages[i][2]
			list_highlight_cursor = list_pages[i][4]
			sortName = list_pages[i][5]
		end
	end
	if list_cursor > #list_contents then
		list_move_last()
	end
end

function get_total_duration(action)
	if not list_contents or not list_contents[1] then return 0 end
	local list_total_duration = 0
	if action == 'found_time' or action == 'found_length' or action == 'found_remaining' then
		for i = #list_contents, 1, -1 do
			if tonumber(list_contents[i][action]) > 0 then
				list_total_duration = list_total_duration + list_contents[i][action]
			end
		end
	end
	return list_total_duration
end

function has_value(tab, val, array2d)
	if not tab then return msg.error('check value passed') end
	if not val then return msg.error('check value passed') end
	if not array2d then
		for index, value in ipairs(tab) do
			if string.lower(value) == string.lower(val) then
				return true
			end
		end
	end
	if array2d then
		for i=1, #tab do
			if tab[i] and string.lower(tab[i][array2d]) == string.lower(val) then
				return true
			end
		end
	end

	return false
end

function list_add_playlist(action)
	if not action then
		load(list_cursor, true)
	elseif action == 'highlight' then
		if not list_highlight_cursor or not list_highlight_cursor[1] then return end
		local file_ignored_total = 0

		for i=1, #list_highlight_cursor do
			if file_exists(list_highlight_cursor[i][2].found_path) or starts_protocol(protocols, list_highlight_cursor[i][2].found_path) then
				mp.commandv("loadfile", list_highlight_cursor[i][2].found_path, "append-play")
			else
				msg.warn('The below file was not added into playlist as it does not seem to exist:\n' .. list_highlight_cursor[i][2].found_path)
				file_ignored_total = file_ignored_total + 1
			end
		end
		if o.osd_messages == true then
			if file_ignored_total > 0 then
				mp.osd_message('Added into Playlist '..#list_highlight_cursor - file_ignored_total..' Item/s\nIgnored '..file_ignored_total.. " Item/s That Do Not Exist")
			else
				mp.osd_message('Added into Playlist '..#list_highlight_cursor - file_ignored_total..' Item/s')
			end
		end
		if file_ignored_total > 0 then
			msg.warn('Ignored a total of '..file_ignored_total.. " Item/s that does not seem to exist")
		end
		msg.info('Added into playlist a total of '..#list_highlight_cursor - file_ignored_total..' item/s')
	end
end

function list_cycle_sort()
	local next_sort
	for i = 1, #available_sorts do
		if sortName == available_sorts[i] then
			if i == #available_sorts then
				next_sort = available_sorts[1]
				break
			else
				next_sort = available_sorts[i+1]
				break
			end
		end
	end
	if not next_sort then return end
	get_list_contents(filterName, next_sort)
	sortName = next_sort
	update_list_highlist_cursor()
	select(0)
end

function list_delete(action)
	if not action then
		delete_selected()
	elseif action == 'highlight' then
		delete_log_entry_highlighted()
	end
	get_list_contents()
	if not list_contents or not list_contents[1] then
		list_close_and_trash_collection()
		return
	end
	if list_cursor < #list_contents + 1 then
		select(0)
	else
		list_move_last()
	end
end

function list_filter_next()
	select_filter_sequence(1)
end

function list_filter_previous()
	select_filter_sequence(-1)
end
--End of LogManager Filter Functions--

--LogManager (List Bind and Unbind)--

function list_highlight_all()
	get_list_contents(filterName)
	if not list_contents or not list_contents[1] then return end

	if #list_highlight_cursor < #list_contents then
		for i=1, #list_contents do
			if not has_value(list_highlight_cursor, i, 1) then
				table.insert(list_highlight_cursor, {i, list_contents[#list_contents+1-i]})
			end
		end
		select(0)
	else
		list_unhighlight_all()
	end
end

function list_move_down(action)
	select(1, action)

	if search_active and o.search_not_typing_smartly then
		list_search_not_typing_mode(true)
	end
end

function list_move_first(action)
	select(1 - list_cursor, action)

	if search_active and o.search_not_typing_smartly then
		list_search_not_typing_mode(true)
	end
end

function list_move_last(action)
	select(#list_contents - list_cursor, action)

	if search_active and o.search_not_typing_smartly then
		list_search_not_typing_mode(true)
	end
end

function list_move_up(action)
	select(-1, action)

	if search_active and o.search_not_typing_smartly then
		list_search_not_typing_mode(true)
	end
end

function list_page_down(action)
	if o.list_middle_loader then
		if #list_contents < o.list_show_amount then
			select(#list_contents - list_cursor, action)
		else
			select(o.list_show_amount + list_start - list_cursor, action)
		end
	else
		if o.list_show_amount > list_cursor then
			select(o.list_show_amount - list_cursor, action)
		elseif #list_contents - list_cursor >= o.list_show_amount then
			select(o.list_show_amount, action)
		else
			select(#list_contents - list_cursor, action)
		end
	end

	if search_active and o.search_not_typing_smartly then
		list_search_not_typing_mode(true)
	end
end

function list_page_up(action)
	select(list_start + 1 - list_cursor, action)

	if search_active and o.search_not_typing_smartly then
		list_search_not_typing_mode(true)
	end
end

function list_search_activate()
	if not list_drawn then return end
	if search_active == 'typing' then list_search_exit() return end
	search_active = 'typing'

	for i = 1, #list_pages do
		if list_pages[i][1] == filterName then
			list_pages[i][2] = list_cursor
			list_pages[i][4] = list_highlight_cursor
			list_pages[i][5] = sortName
		end
	end

	update_search_results('','')
	bind_search_keys()
end

function list_search_exit()
	search_active = false
	get_list_contents(filterName)
	get_page_properties(filterName)
	select(0)
	unbind_search_keys()
	get_list_keybinds()
end

function list_search_not_typing_mode(auto_triggered)
	if auto_triggered then
		if search_string ~= '' and list_contents[1] then
			search_active = 'not_typing'
		elseif not list_contents[1] then
			return
		else
			search_active = false
		end
	else
		if search_string ~= '' then
			search_active = 'not_typing'
		else
			search_active = false
		end
	end
	select(0)
	unbind_search_keys()
	get_list_keybinds()
end

function list_select()
	load(list_cursor)
end

function list_sort(tab, sort)
	if sort == 'added-asc' then
		table.sort(tab, function(a, b) return a['found_sequence'] < b['found_sequence'] end)
	elseif sort == 'added-desc' then
		table.sort(tab, function(a, b) return a['found_sequence'] > b['found_sequence'] end)
	elseif sort == 'time-asc' then
		table.sort(tab, function(a, b) return tonumber(a['found_time']) > tonumber(b['found_time']) end)
	elseif sort == 'time-desc' then
		table.sort(tab, function(a, b) return tonumber(a['found_time']) < tonumber(b['found_time']) end)
	elseif sort == 'alphanum-asc' or sort == 'alphanum-desc' then
		local function padnum(d) local dec, n = string.match(d, "(%.?)0*(.+)")
			return #dec > 0 and ("%.12f"):format(d) or ("%s%03d%s"):format(dec, #n, n) end
		if sort == 'alphanum-asc' then
			table.sort(tab, function(a, b) return tostring(a['found_path']):gsub("%.?%d+", padnum) .. ("%3d"):format(#b) > tostring(b['found_path']):gsub("%.?%d+", padnum) .. ("%3d"):format(#a) end)
		elseif sort == 'alphanum-desc' then
			table.sort(tab, function(a, b) return tostring(a['found_path']):gsub("%.?%d+", padnum) .. ("%3d"):format(#b) < tostring(b['found_path']):gsub("%.?%d+", padnum) .. ("%3d"):format(#a) end)
		end
	end

	return tab
end

function list_unhighlight_all()
	if not list_highlight_cursor or not list_highlight_cursor[1] then return end
	list_highlight_cursor = {}
	select(0)
end
--End of LogManager Navigation--

--LogManager Actions--

function load(list_cursor, add_playlist, target_time)
	if not list_contents or not list_contents[1] then return end
	if not target_time then
		seekTime = tonumber(list_contents[#list_contents - list_cursor + 1].found_time) + o.resume_offset
		if (seekTime < 0) then
			seekTime = 0
		end
	else
		seekTime = target_time
	end
	if file_exists(list_contents[#list_contents - list_cursor + 1].found_path) or starts_protocol(protocols, list_contents[#list_contents - list_cursor + 1].found_path) then
		if not add_playlist then
			if filePath ~= list_contents[#list_contents - list_cursor + 1].found_path then
				mp.commandv('loadfile', list_contents[#list_contents - list_cursor + 1].found_path)
				resume_selected = true
			else
				mp.commandv('seek', seekTime, 'absolute', 'exact')
				list_close_and_trash_collection()
			end
			if o.osd_messages == true then
				mp.osd_message('Loaded:\n' .. list_contents[#list_contents - list_cursor + 1].found_name.. o.time_seperator .. format_time(seekTime, o.osd_time_format[3], o.osd_time_format[2], o.osd_time_format[1]))
			end
			msg.info('Loaded the below file:\n' .. list_contents[#list_contents - list_cursor + 1].found_name  .. ' | '.. format_time(seekTime))
		else
			mp.commandv('loadfile', list_contents[#list_contents - list_cursor + 1].found_path, 'append-play')
			if o.osd_messages == true then
				mp.osd_message('Added into Playlist:\n'..list_contents[#list_contents - list_cursor + 1].found_name..' ')
			end
			msg.info('Added the below file into playlist:\n' .. list_contents[#list_contents - list_cursor + 1].found_path)
		end
	else
		if o.osd_messages == true then
			mp.osd_message('File Doesn\'t Exist:\n' .. list_contents[#list_contents - list_cursor + 1].found_path)
		end
		msg.info('The file below doesn\'t seem to exist:\n' .. list_contents[#list_contents - list_cursor + 1].found_path)
		return
	end
end

function parse_header(string)
	local osd_header_color = string.format("{\\1c&H%s}", o.header_color)
	local osd_search_color = osd_header_color
	if search_active == 'typing' then
		osd_search_color = string.format("{\\1c&H%s}", o.search_color_typing)
	elseif search_active == 'not_typing' then
		osd_search_color = string.format("{\\1c&H%s}", o.search_color_not_typing)
	end
	local osd_msg_end = "{\\1c&HFFFFFF}"

	string = string:gsub("%%total%%", #list_contents)
		:gsub("%%cursor%%", list_cursor)

	if filterName ~= 'all' then
		string = string:gsub("%%filter%%", filterName)
		:gsub("%%prefilter%%", o.header_filter_pre_text)
		:gsub("%%afterfilter%%", o.header_filter_after_text)
	else
		string = string:gsub("%%filter%%", '')
		:gsub("%%prefilter%%", '')
		:gsub("%%afterfilter%%", '')
	end

	local list_total_duration = 0
	if string:match('%listduration%%') then
		list_total_duration = get_total_duration('found_time')
		if list_total_duration > 0 then
			string = string:gsub("%%listduration%%", format_time(list_total_duration, o.header_duration_time_format[3], o.header_duration_time_format[2], o.header_duration_time_format[1]))
		else
			string = string:gsub("%%listduration%%", '')
		end
	end
	if list_total_duration > 0 then
		string = string:gsub("%%prelistduration%%", o.header_list_duration_pre_text)
		:gsub("%%afterlistduration%%", o.header_list_duration_after_text)
	else
		string = string:gsub("%%prelistduration%%", '')
		:gsub("%%afterlistduration%%", '')
	end

	local list_total_length = 0
	if string:match('%listlength%%') then
		list_total_length = get_total_duration('found_length')
		if list_total_length > 0 then
			string = string:gsub("%%listlength%%", format_time(list_total_length, o.header_length_time_format[3], o.header_length_time_format[2], o.header_length_time_format[1]))
		else
			string = string:gsub("%%listlength%%", '')
		end
	end
	if list_total_length > 0 then
		string = string:gsub("%%prelistlength%%", o.header_list_length_pre_text)
		:gsub("%%afterlistlength%%", o.header_list_length_after_text)
	else
		string = string:gsub("%%prelistlength%%", '')
		:gsub("%%afterlistlength%%", '')
	end

	local list_total_remaining = 0
	if string:match('%listremaining%%') then
		list_total_remaining = get_total_duration('found_remaining')
		if list_total_remaining > 0 then
			string = string:gsub("%%listremaining%%", format_time(list_total_remaining, o.header_remaining_time_format[3], o.header_remaining_time_format[2], o.header_remaining_time_format[1]))
		else
			string = string:gsub("%%listremaining%%", '')
		end
	end
	if list_total_remaining > 0 then
		string = string:gsub("%%prelistremaining%%", o.header_list_remaining_pre_text)
		:gsub("%%afterlistremaining%%", o.header_list_remaining_after_text)
	else
		string = string:gsub("%%prelistremaining%%", '')
		:gsub("%%afterlistremaining%%", '')
	end

	if #list_highlight_cursor > 0 then
		string = string:gsub("%%highlight%%", #list_highlight_cursor)
		:gsub("%%prehighlight%%", o.header_highlight_pre_text)
		:gsub("%%afterhighlight%%", o.header_highlight_after_text)
	else
		string = string:gsub("%%highlight%%", '')
		:gsub("%%prehighlight%%", '')
		:gsub("%%afterhighlight%%", '')
	end

	if sortName and sortName ~= o.header_sort_hide_text then
		string = string:gsub("%%sort%%", sortName)
		:gsub("%%presort%%", o.header_sort_pre_text)
		:gsub("%%aftersort%%", o.header_sort_after_text)
	else
		string = string:gsub("%%sort%%", '')
		:gsub("%%presort%%", '')
		:gsub("%%aftersort%%", '')
	end

	if search_active then
		local search_string_osd = search_string
		if search_string_osd ~= '' then
			search_string_osd = search_string:gsub('%%', '%%%%%%%%'):gsub('\\', '\\​'):gsub('{', '\\{')
		end

		string = string:gsub("%%search%%", osd_search_color..search_string_osd..osd_header_color)
		:gsub("%%presearch%%", o.header_search_pre_text)
		:gsub("%%aftersearch%%", o.header_search_after_text)
	else
		string = string:gsub("%%search%%", '')
		:gsub("%%presearch%%", '')
		:gsub("%%aftersearch%%", '')
	end
	string = string:gsub("%%%%", "%%")
	return string
end

function read_log(func)
	local f = io.open(log_fullpath, "r")
	if not f then return end
	local contents = {}
	for line in f:lines() do
		table.insert(contents, (func(line)))
	end
	f:close()
	return contents
end

function select(pos, action)
	if not search_active then
		if not list_contents or not list_contents[1] then
			list_close_and_trash_collection()
			return
		end
	end

	local list_cursor_temp = list_cursor + pos
	if list_cursor_temp > 0 and list_cursor_temp <= #list_contents then
		list_cursor = list_cursor_temp

		if action == 'highlight' then
			if not has_value(list_highlight_cursor, list_cursor, 1) then
				if pos > -1 then
					for i = pos, 1, -1 do
						if not has_value(list_highlight_cursor, list_cursor-i, 1) then
							table.insert(list_highlight_cursor, {list_cursor-i, list_contents[#list_contents+1+i - list_cursor]})
						end
					end
				else
					for i = pos, -1, 1 do
						if not has_value(list_highlight_cursor, list_cursor-i, 1) then
							table.insert(list_highlight_cursor, {list_cursor-i, list_contents[#list_contents+1+i - list_cursor]})
						end
					end
				end
				table.insert(list_highlight_cursor, {list_cursor, list_contents[#list_contents+1 - list_cursor]})
			else
				for i=1, #list_highlight_cursor do
					if list_highlight_cursor[i] and list_highlight_cursor[i][1] == list_cursor then
						table.remove(list_highlight_cursor, i)
					end
				end
				if pos > -1 then
					for i=1, #list_highlight_cursor do
						for j = pos, 1, -1 do
							if list_highlight_cursor[i] and list_highlight_cursor[i][1] == list_cursor-j then
								table.remove(list_highlight_cursor, i)
							end
						end
					end
				else
					for i=#list_highlight_cursor, 1, -1 do
						for j = pos, -1, 1 do
							if list_highlight_cursor[i] and list_highlight_cursor[i][1] == list_cursor-j then
								table.remove(list_highlight_cursor, i)
							end
						end
					end
				end
			end
		end
	end

	if o.loop_through_list then
		if list_cursor_temp > #list_contents then
			list_cursor = 1
		elseif list_cursor_temp < 1 then
			list_cursor = #list_contents
		end
	end

	draw_list()
end

function select_filter_sequence(pos)
	if not list_drawn then return end
	local curr_pos
	local target_pos

	for i = 1, #o.filters_and_sequence do
		if filterName == o.filters_and_sequence[i] then
			curr_pos = i
		end
	end

	if curr_pos and pos > -1 then
		for i = curr_pos, #o.filters_and_sequence do
			if o.filters_and_sequence[i + pos] then
				get_list_contents(o.filters_and_sequence[i + pos])
				if list_contents ~= nil and list_contents[1] then
					target_pos = i + pos
					break
				end
			end
		end
	elseif curr_pos and pos < 0 then
		for i = curr_pos, 0, -1 do
			if o.filters_and_sequence[i + pos] then
				get_list_contents(o.filters_and_sequence[i + pos])
				if list_contents ~= nil and list_contents[1] then
					target_pos = i + pos
					break
				end
			end
		end
	end

	if o.loop_through_filters then
		if not target_pos and pos > -1 or target_pos and target_pos > #o.filters_and_sequence then
			for i = 1, #o.filters_and_sequence do
				get_list_contents(o.filters_and_sequence[i])
				if list_contents ~= nil and list_contents[1] then
					target_pos = i
					break
				end
			end
		end
		if not target_pos and pos < 0 or target_pos and target_pos < 1 then
			for i = #o.filters_and_sequence, 1, -1 do
				get_list_contents(o.filters_and_sequence[i])
				if list_contents ~= nil and list_contents[1] then
					target_pos = i
					break
				end
			end
		end
	end

	if o.filters_and_sequence[target_pos] then
		display_list(o.filters_and_sequence[target_pos], nil, 'hide-osd')
	end
end

function starts_protocol(tab, val)
	for index, value in ipairs(tab) do
		if (val:find(value) == 1) then
			return true
		end
	end
	return false
end

function unbind_keys(keys, name)
	if not keys then
		mp.remove_key_binding(name)
		return
	end

	for i = 1, #keys do
		if i == 1 then
			mp.remove_key_binding(name)
		else
			mp.remove_key_binding(name .. i)
		end
	end
end

function unbind_list_keys()
	unbind_keys(o.list_ignored_keybind, 'ignore')
	unbind_keys(o.list_move_up_keybind, 'move-up')
	unbind_keys(o.list_move_down_keybind, 'move-down')
	unbind_keys(o.list_move_first_keybind, 'move-first')
	unbind_keys(o.list_move_last_keybind, 'move-last')
	unbind_keys(o.list_page_up_keybind, 'page-up')
	unbind_keys(o.list_page_down_keybind, 'page-down')
	unbind_keys(o.list_select_keybind, 'list-select')
	unbind_keys(o.list_add_playlist_keybind, 'list-add-playlist')
	unbind_keys(o.list_add_playlist_highlighted_keybind, 'list-add-playlist-highlight')
	unbind_keys(o.list_delete_keybind, 'list-delete')
	unbind_keys(o.list_delete_highlighted_keybind, 'list-delete-highlight')
	unbind_keys(o.list_close_keybind, 'list-close')
	unbind_keys(o.next_filter_sequence_keybind, 'list-filter-next')
	unbind_keys(o.previous_filter_sequence_keybind, 'list-filter-previous')
	unbind_keys(o.list_highlight_all_keybind, 'list-highlight-all')
	unbind_keys(o.list_highlight_all_keybind, 'list-unhighlight-all')
	unbind_keys(o.list_cycle_sort_keybind, 'list-cycle-sort')

	for i = 1, #o.list_move_up_keybind do
		mp.remove_key_binding('highlight-move-up'..i)
	end
	for i = 1, #o.list_move_down_keybind do
		mp.remove_key_binding('highlight-move-down'..i)
	end
	for i = 1, #o.list_move_first_keybind do
		mp.remove_key_binding('highlight-move-first'..i)
	end
	for i = 1, #o.list_move_last_keybind do
		mp.remove_key_binding('highlight-move-last'..i)
	end
	for i = 1, #o.list_page_up_keybind do
		mp.remove_key_binding('highlight-page-up'..i)
	end
	for i = 1, #o.list_page_down_keybind do
		mp.remove_key_binding('highlight-page-down'..i)
	end

	for i = 1, #o.list_filter_jump_keybind do
		mp.remove_key_binding('list-filter-jump'..i)
	end

	for i = 1, #o.open_list_keybind do
		if i == 1 then
			mp.add_forced_key_binding(o.open_list_keybind[i][1], 'open-list', function()display_list(o.open_list_keybind[i][2]) end)
		else
			mp.add_forced_key_binding(o.open_list_keybind[i][1], 'open-list'..i, function()display_list(o.open_list_keybind[i][2]) end)
		end
	end

	if o.quickselect_0to9_keybind and o.list_show_amount <= 10 then
		mp.remove_key_binding("recent-1")
		mp.remove_key_binding("recent-2")
		mp.remove_key_binding("recent-3")
		mp.remove_key_binding("recent-4")
		mp.remove_key_binding("recent-5")
		mp.remove_key_binding("recent-6")
		mp.remove_key_binding("recent-7")
		mp.remove_key_binding("recent-8")
		mp.remove_key_binding("recent-9")
		mp.remove_key_binding("recent-0")
	end
end

function unbind_search_keys()
	mp.remove_key_binding('search_string_a')
	mp.remove_key_binding('search_string_b')
	mp.remove_key_binding('search_string_c')
	mp.remove_key_binding('search_string_d')
	mp.remove_key_binding('search_string_e')
	mp.remove_key_binding('search_string_f')
	mp.remove_key_binding('search_string_g')
	mp.remove_key_binding('search_string_h')
	mp.remove_key_binding('search_string_i')
	mp.remove_key_binding('search_string_j')
	mp.remove_key_binding('search_string_k')
	mp.remove_key_binding('search_string_l')
	mp.remove_key_binding('search_string_m')
	mp.remove_key_binding('search_string_n')
	mp.remove_key_binding('search_string_o')
	mp.remove_key_binding('search_string_p')
	mp.remove_key_binding('search_string_q')
	mp.remove_key_binding('search_string_r')
	mp.remove_key_binding('search_string_s')
	mp.remove_key_binding('search_string_t')
	mp.remove_key_binding('search_string_u')
	mp.remove_key_binding('search_string_v')
	mp.remove_key_binding('search_string_w')
	mp.remove_key_binding('search_string_x')
	mp.remove_key_binding('search_string_y')
	mp.remove_key_binding('search_string_z')

	mp.remove_key_binding('search_string_A')
	mp.remove_key_binding('search_string_B')
	mp.remove_key_binding('search_string_C')
	mp.remove_key_binding('search_string_D')
	mp.remove_key_binding('search_string_E')
	mp.remove_key_binding('search_string_F')
	mp.remove_key_binding('search_string_G')
	mp.remove_key_binding('search_string_H')
	mp.remove_key_binding('search_string_I')
	mp.remove_key_binding('search_string_J')
	mp.remove_key_binding('search_string_K')
	mp.remove_key_binding('search_string_L')
	mp.remove_key_binding('search_string_M')
	mp.remove_key_binding('search_string_N')
	mp.remove_key_binding('search_string_O')
	mp.remove_key_binding('search_string_P')
	mp.remove_key_binding('search_string_Q')
	mp.remove_key_binding('search_string_R')
	mp.remove_key_binding('search_string_S')
	mp.remove_key_binding('search_string_T')
	mp.remove_key_binding('search_string_U')
	mp.remove_key_binding('search_string_V')
	mp.remove_key_binding('search_string_W')
	mp.remove_key_binding('search_string_X')
	mp.remove_key_binding('search_string_Y')
	mp.remove_key_binding('search_string_Z')

	mp.remove_key_binding('search_string_1')
	mp.remove_key_binding('search_string_2')
	mp.remove_key_binding('search_string_3')
	mp.remove_key_binding('search_string_4')
	mp.remove_key_binding('search_string_5')
	mp.remove_key_binding('search_string_6')
	mp.remove_key_binding('search_string_7')
	mp.remove_key_binding('search_string_8')
	mp.remove_key_binding('search_string_9')
	mp.remove_key_binding('search_string_0')

	mp.remove_key_binding('search_string_space')
	mp.remove_key_binding('search_string_`')
	mp.remove_key_binding('search_string_~')
	mp.remove_key_binding('search_string_!')
	mp.remove_key_binding('search_string_@')
	mp.remove_key_binding('search_string_sharp')
	mp.remove_key_binding('search_string_$')
	mp.remove_key_binding('search_string_percentage')
	mp.remove_key_binding('search_string_^')
	mp.remove_key_binding('search_string_&')
	mp.remove_key_binding('search_string_*')
	mp.remove_key_binding('search_string_(')
	mp.remove_key_binding('search_string_)')
	mp.remove_key_binding('search_string_-')
	mp.remove_key_binding('search_string__')
	mp.remove_key_binding('search_string_=')
	mp.remove_key_binding('search_string_+')
	mp.remove_key_binding('search_string_\\')
	mp.remove_key_binding('search_string_|')
	mp.remove_key_binding('search_string_]')
	mp.remove_key_binding('search_string_rightcurly')
	mp.remove_key_binding('search_string_[')
	mp.remove_key_binding('search_string_leftcurly')
	mp.remove_key_binding('search_string_\'')
	mp.remove_key_binding('search_string_\"')
	mp.remove_key_binding('search_string_semicolon')
	mp.remove_key_binding('search_string_:')
	mp.remove_key_binding('search_string_/')
	mp.remove_key_binding('search_string_?')
	mp.remove_key_binding('search_string_.')
	mp.remove_key_binding('search_string_>')
	mp.remove_key_binding('search_string_,')
	mp.remove_key_binding('search_string_<')

	mp.remove_key_binding('search_string_del')
	if not search_active then
		unbind_keys(o.list_close_keybind, 'search_exit')
	end
end
--End of LogManager Search Feature--
---------End of LogManager---------

function update_list_highlist_cursor()
	if not list_highlight_cursor or not list_highlight_cursor[1] then return end

	local temp_list_highlight_cursor = {}
	for i = 1, #list_contents do
		for j=1, #list_highlight_cursor do
			if list_contents[#list_contents+1-i].found_sequence == list_highlight_cursor[j][2].found_sequence then
				table.insert(temp_list_highlight_cursor, {i, list_highlight_cursor[j][2]})
			end
		end
	end

	list_highlight_cursor = temp_list_highlight_cursor
end

--End of LogManager Actions--

--LogManager Filter Functions--

function update_search_results(character, action)
	if not character then character = '' end
	if action == 'string_del' then
		search_string = search_string:sub(1, -2)
	end
	search_string = search_string..character
	local prev_contents_length = #list_contents
	get_list_contents(filterName)

	if prev_contents_length ~= #list_contents then
		list_highlight_cursor = {}
	end

	if character ~= '' and #list_contents > 0 or action ~= nil and #list_contents > 0 then
		select(1-list_cursor)
	elseif #list_contents == 0 then
		list_cursor = 0
		select(list_cursor)
	else
		select(0)
	end
end

-- ── ortak ayar okuyucu ─────────────────────────────────────────────────────
-- Önce script-opts/simple-suite.conf (üç script'in ortak ayarları), sonra
-- script'in kendi conf'u okunur; ikincisi birincisini ezer.
function read_list_options(opts, conf_name)
	local options = require 'mp.options'
	options.read_options(opts, 'simple-suite')          -- ortak varsayılanlar
	options.read_options(opts, conf_name or SUITE_CONF) -- bu örneğe özel (ezer)
end
