-- simple-suite/history.lua — SimpleHistory gövdesi
-- Kendi ortamında çalışır; liste motoru engine.lua'dan gelir.
-- scripts/simple-suite.lua tarafından yüklenir.

-- Copyright (c) 2022, Eisa AlAwadhi
-- License: BSD 2-Clause License
-- Creator: Eisa AlAwadhi
-- Project: SimpleHistory
-- Version: 1.1.6

o = {
---------------------------USER CUSTOMIZATION SETTINGS---------------------------
--These settings are for users to manually change some options.
--Changes are recommended to be made in the script-opts directory.

	-----Script Settings----
	auto_run_list_idle = 'recents', --Auto run the list when opening mpv and there is no video / file loaded. 'none' for disabled. Or choose between: 'all', 'recents', 'distinct', 'protocols', 'fileonly', 'titleonly', 'timeonly', 'keywords'.
	startup_idle_behavior = 'none', --The behavior when mpv launches and nothing is loaded. 'none' for disabled. 'resume' to automatically resume your last played item. 'resume-notime' to resume your last played item but starts from the beginning.
	toggle_idlescreen = false, --hides OSC idle screen message when opening and closing menu (could cause unexpected behavior if multiple scripts are triggering osc-idlescreen off)
	resume_offset = -0.65, --change to 0 so item resumes from the exact position, or decrease the value so that it gives you a little preview before loading the resume point
	osd_messages = true, --true is for displaying osd messages when actions occur. Change to false will disable all osd messages generated from this script
	resume_option = 'notification', --'none': for disabled. 'notification': a message to resume the previous reached time will be triggered. 'force': to forcefully resume last playback based on threshold
	resume_option_threshold = 2, --0 to always trigger the resume option when the same video has been played previously, a value such as 5 will only trigger the resume option if the last played time starts after 5% of the video and ends before completion by 5%
	mark_history_as_chapter = false, --true is for marking the time as a chapter. false disables mark as chapter behavior.
	invert_history_blacklist = false, --true so that blacklist becomes a whitelist, resulting in stuff such as paths / websites that are added to history_blacklist to be saved into history
	history_blacklist=[[
	[""]
	]], --Paths / URLs / Websites / Files / Protocols / Extensions, that wont be added to history automatically, e.g.: ["c:\\users\\eisa01\\desktop", "c:\\users\\eisa01\\desktop\\*", "c:\\temp\\naruto-01.mp4", "youtube.com", "https://dailymotion.com/", "avi", "https://www.youtube.com/watch?v=e8YBesRKq_U", ".jpeg", "magnet:", "https://", "ftp"]
	history_resume_keybind=[[
	["ctrl+r", "ctrl+R"]
	]], --Keybind that will be used to immediately load and resume last item when no video is playing. If video is playing it will resume to the last found position
	history_load_last_keybind=[[
	["alt+r", "alt+R"]
	]], --Keybind that will be used to immediately load the last item without resuming when no video is playing. If video is playing then it will add into playlist
	open_list_keybind=[[
	[ ["h", "all"], ["H", "all"], ["r", "recents"], ["R", "recents"] ]
	]], --Keybind that will be used to open the list along with the specified filter. Available filters: 'all', 'recents', 'distinct', 'protocols', 'fileonly', 'titleonly', 'timeonly', 'keywords'.
	list_filter_jump_keybind=[[
	[ ["h", "all"], ["H", "all"], ["r", "recents"], ["R", "recents"], ["d", "distinct"], ["D", "distinct"], ["f", "fileonly"], ["F", "fileonly"] ]
	]], --Keybind that is used while the list is open to jump to the specific filter (it also enables pressing a filter keybind twice to close list). Available fitlers: 'all', 'recents', 'distinct', 'protocols', 'fileonly', 'titleonly', 'timeonly', 'keywords'.
	
	-----Incognito Settings----
	auto_run_incognito_mode = false, --true to automatically start incognito mode when mpv launches, false disables this behavior
	delete_incognito_entry = true, --true so that the file that had incognito mode triggered on gets removed from history automatically, false keeps the file in history that incognito mode triggered on
	restore_incognito_entry = 'always', --'none' for disabled, 'deleted-restore' so that the the file that was removed when entering incognito automtically gets restored, 'always' so that exiting incognito_mode always immediately updates entry into history
	history_incognito_mode_keybind=[[
	["ctrl+H"]
	]], --Triggers incognito mode. When enabled files played wont be added to history until this mode is disabled.
	
	-----Logging Settings-----
	log_path = '/:dir%mpvconf%', --Change to '/:dir%script%' for placing it in the same directory of script, OR change to '/:dir%mpvconf%' for mpv portable_config directory. OR write any variable using '/:var' then the variable '/:var%APPDATA%' you can use path also, such as: '/:var%APPDATA%\\mpv' OR '/:var%HOME%/mpv' OR specify the absolute path , e.g.: 'C:\\Users\\Eisa01\\Desktop\\'
	log_file = 'mpvHistory.log', --name+extension of the file that will be used to store the log data
	date_format = '%A/%B %d/%m/%Y %X', --Date format in the log (see lua date formatting), e.g.:'%d/%m/%y %X' or '%d/%b/%y %X'
	file_title_logging = 'protocols', --Change between 'all', 'protocols', 'none'. This option will store the media title in log file, it is useful for websites / protocols because title cannot be parsed from links alone
	logging_protocols=[[
	["https?://", "magnet:", "rtmp:"]
	]], --add above (after a comma) any protocol you want its title to be stored in the log file. This is valid only for (file_title_logging = 'protocols' or file_title_logging = 'all')
	prefer_filename_over_title = 'local', --Prefers to log filename over filetitle. Select between 'local', 'protocols', 'all', and 'none'. 'local' prefer filenames for videos that are not protocols. 'protocols' will prefer filenames for protocols only. 'all' will prefer filename over filetitle for both protocols and not protocols videos. 'none' will always use filetitle instead of filename
	same_entry_limit = 2, --Limit saving entries with same path: -1 for unlimited, 0 will always update entries of same path, e.g. value of 3 will have the limit of 3 then it will start updating old values on the 4th entry.

	-----List Settings-----
	loop_through_list = false, --true is for going up on the first item loops towards the last item and vise-versa. false disables this behavior.
	list_middle_loader = true, --false is for more items to show, then u must reach the end. true is for new items to show after reaching the middle of list.
	show_paths = false, --Show file paths instead of media-title
	show_item_number = true, --Show the number of each item before displaying its name and values.
	slice_longfilenames = false, --Change to true or false. Slices long filenames per the amount specified below
	slice_longfilenames_amount = 55, --Amount for slicing long filenames
	list_show_amount = 10, --Change maximum number to show items at once
	quickselect_0to9_keybind = true, --Keybind entries from 0 to 9 for quick selection when list is open (list_show_amount = 10 is maximum for this feature to work)
	main_list_keybind_twice_exits = true, --Will exit the list when double tapping the main list, even if the list was accessed through a different filter.
	search_not_typing_smartly = true, --To smartly set the search as not typing (when search box is open) without needing to press ctrl+enter.
	search_behavior = 'any', --'specific' to find a match of either a date, title, path / url, time. 'any' to find any typed search based on combination of date, title, path / url, and time. 'any-notime' to find any typed search based on combination of date, title, and path / url, but without looking for time (this is to reduce unwanted results).
	
	-----Filter Settings------
	--available filters: "all" to display all the items. Or "recents" to display recently added items to log without duplicate. Or "distinct" to show recent saved entries for files in different paths. Or "fileonly" to display files saved without time. Or "timeonly" to display files that have time only. Or "keywords" to display files with matching keywords specified in the configuration. Or "playing" to show list of current playing file.
	filters_and_sequence=[[
	["all", "recents", "distinct", "protocols", "playing", "fileonly", "titleonly", "keywords"]
	]], --Jump to the following filters and in the shown sequence when navigating via left and right keys. You can change the sequence and delete filters that are not needed.
	next_filter_sequence_keybind=[[
	["RIGHT", "MBTN_FORWARD"]
	]], --Keybind that will be used to go to the next available filter based on the filters_and_sequence
	previous_filter_sequence_keybind=[[
	["LEFT", "MBTN_BACK"]
	]], --Keybind that will be used to go to the previous available filter based on the filters_and_sequence
	loop_through_filters = true, --true is for bypassing the last filter to go to first filter when navigating through filters using arrow keys, and vice-versa. false disables this behavior.
	keywords_filter_list=[[
	[""]
	]], --Create a filter out of your desired 'keywords', e.g.: youtube.com will filter out the videos from youtube. You can also insert a portion of filename or title, or extension or a full path / portion of a path. e.g.: ["youtube.com", "mp4", "naruto", "c:\\users\\eisa01\\desktop"]

	-----Sort Settings------
	--available sort: 'added-asc' is for the newest added item to show first. Or 'added-desc' for the newest added to show last. Or 'alphanum-asc' is for A to Z approach with filename and episode number lower first. Or 'alphanum-desc' is for its Z to A approach. Or 'time-asc', 'time-desc' to sort the list based on time.
	list_default_sort = 'added-asc', --the default sorting method for all the different filters in the list. select between 'added-asc', 'added-desc', 'time-asc', 'time-desc', 'alphanum-asc', 'alphanum-desc'
	list_filters_sort=[[
	[ ]
	]], --Default sort for specific filters, e.g.: [ ["all", "alphanum-asc"], ["playing", "added-desc"] ]
	list_cycle_sort_keybind=[[
	["alt+s", "alt+S"]
	]], --Keybind to cycle through the different available sorts when list is open

	-----List Design Settings-----
	list_alignment = 7, --The alignment for the list, uses numpad positions choose from 1-9 or 0 to disable. e,g.:7 top left alignment, 8 top middle alignment, 9 top right alignment.	
	text_time_type = 'duration', --The time type for items on the list. Select between 'duration', 'length', 'remaining'.
	time_seperator = ' 🕒 ', --Time seperator that will be used before the time
	list_sliced_prefix = '...\\h\\N\\N', --The text that indicates there are more items above. \\N is for new line. \\h is for hard space.
	list_sliced_suffix = '...', --The text that indicates there are more items below.
	quickselect_0to9_pre_text = false, --true enables pre text for showing quickselect keybinds before the list. false to disable
	text_color = 'ffffff', --Text color for list in BGR hexadecimal
	text_scale = 50, --Font size for the text of list
	text_border = 0.7, --Black border size for the text of list
	text_cursor_color = 'ffbf7f', --Text color of current cursor position in BGR hexadecimal
	text_cursor_scale = 50, --Font size for text of current cursor position in list
	text_cursor_border = 0.7, --Black border size for text of current cursor position in list
	text_highlight_pre_text = '✅ ', --Pre text for highlighted multi-select item
	search_color_typing = 'ffffaa', --Search color when in typing mode
	search_color_not_typing = '00bfff', --Search color when not in typing mode and it is active
	header_color = '00bfff', --Header color in BGR hexadecimal
	header_scale = 55, --Header text size for the list
	header_border = 0.8, --Black border size for the Header of list
	header_text = '⌛ History [%cursor%/%total%]%prehighlight%%highlight%%afterhighlight%%prelistduration%%listduration%%afterlistduration%%prefilter%%filter%%afterfilter%%presort%%sort%%aftersort%%presearch%%search%%aftersearch%', --Text to be shown as header for the list
	--Available header variables: %cursor%, %total%, %highlight%, %filter%, %search%, %listduration%, %listlength%, %listremaining%
	--User defined text that only displays if a variable is triggered: %prefilter%, %afterfilter%, %prehighlight%, %afterhighlight% %presearch%, %aftersearch%, %prelistduration%, %afterlistduration%, %prelistlength%, %afterlistlength%, %prelistremaining%, %afterlistremaining%
	--Variables explanation: %cursor: displays the number of cursor position in list. %total: total amount of items in current list. %highlight%: total number of highlighted items.  %filter: shows the filter name, %search: shows the typed search. Example of user defined text that only displays if a variable is triggered of user: %prefilter: user defined text before showing filter, %afterfilter: user defined text after showing filter.
	header_sort_hide_text = 'added-asc',--Sort method that is hidden from header when using %sort% variable
	header_sort_pre_text = ' \\{',--Text to be shown before sort in the header, when using %presort%
	header_sort_after_text = '}',--Text to be shown after sort in the header, when using %aftersort%
	header_filter_pre_text = ' [Filter: ', --Text to be shown before filter in the header, when using %prefilter%
	header_filter_after_text = ']', --Text to be shown after filter in the header, when using %afterfilter%
	header_search_pre_text = '\\h\\N\\N[Search=', --Text to be shown before search in the header, when using %presearch%
	header_search_after_text = '..]', --Text to be shown after search in the header, when using %aftersearch%
	header_highlight_pre_text = '✅', --Text to be shown before total highlighted items of displayed list in the header
	header_highlight_after_text = '', --Text to be shown after total highlighted items of displayed list in the header
	header_list_duration_pre_text = ' 🕒 ', --Text to be shown before playback total duration of displayed list in the header
	header_list_duration_after_text = '', --Text to be shown after playback total duration of displayed list in the header
	header_list_length_pre_text = ' 🕒 ', --Text to be shown before playback total duration of displayed list in the header
	header_list_length_after_text = '', --Text to be shown after playback total duration of displayed list in the header
	header_list_remaining_pre_text = ' 🕒 ', --Text to be shown before playback total duration of displayed list in the header
	header_list_remaining_after_text = '', --Text to be shown after playback total duration of displayed list in the header
	
	-----Time Format Settings-----
	--in the first parameter, you can define from the available styles: default, hms, hms-full, timestamp, timestamp-concise "default" to show in HH:MM:SS.sss format. "hms" to show in 1h 2m 3.4s format. "hms-full" is the same as hms but keeps the hours and minutes persistent when they are 0. "timestamp" to show the total time as timestamp 123456.700 format. "timestamp-concise" shows the total time in 123456.7 format (shows and hides decimals depending on availability).
	--in the second parameter, you can define whether to show milliseconds, round them or truncate them. Available options: 'truncate' to remove the milliseconds and keep the seconds. 0 to remove the milliseconds and round the seconds. 1 or above is the amount of milliseconds to display. The default value is 3 milliseconds.
	--in the third parameter you can define the seperator between hour:minute:second. "default" style is automatically set to ":", "hms", "hms-full" are automatically set to " ". You can define your own. Some examples: ["default", 3, "-"],["hms-full", 5, "."],["hms", "truncate", ":"],["timestamp-concise"],["timestamp", 0],["timestamp", "truncate"],["timestamp", 5]
	osd_time_format=[[
	["default", "truncate"]
	]],
	list_time_format=[[
	["default", "truncate"]
	]],
	header_duration_time_format=[[
	["hms", "truncate", ":"]
	]],
	header_length_time_format=[[
	["hms", "truncate", ":"]
	]],
	header_remaining_time_format=[[
	["hms", "truncate", ":"]
	]],

	-----List Keybind Settings-----
	--Add below (after a comma) any additional keybind you want to bind. Or change the letter inside the quotes to change the keybind
	--Example of changing and adding keybinds: --From ["b", "B"] To ["b"]. --From [""] to ["alt+b"]. --From [""] to ["a" "ctrl+a", "alt+a"]
	list_move_up_keybind=[[
	["UP", "WHEEL_UP"]
	]], --Keybind that will be used to navigate up on the list
	list_move_down_keybind=[[
	["DOWN", "WHEEL_DOWN"]
	]], --Keybind that will be used to navigate down on the list
	list_page_up_keybind=[[
	["PGUP"]
	]], --Keybind that will be used to go to the first item for the page shown on the list
	list_page_down_keybind=[[
	["PGDWN"]
	]], --Keybind that will be used to go to the last item for the page shown on the list
	list_move_first_keybind=[[
	["HOME"]
	]], --Keybind that will be used to navigate to the first item on the list
	list_move_last_keybind=[[
	["END"]
	]], --Keybind that will be used to navigate to the last item on the list
	list_highlight_move_keybind=[[
	["SHIFT"]
	]], --Keybind that will be used to highlight while pressing a navigational keybind, keep holding shift and then press any navigation keybind, such as: up, down, home, pgdwn, etc..
	list_highlight_all_keybind=[[
	["ctrl+a", "ctrl+A"]
	]], --Keybind that will be used to highlight all displayed items on the list
	list_unhighlight_all_keybind=[[
	["ctrl+d", "ctrl+D"]
	]], --Keybind that will be used to remove all currently highlighted items from the list
	list_select_keybind=[[
	["ENTER", "MBTN_MID"]
	]], --Keybind that will be used to load entry based on cursor position
	list_add_playlist_keybind=[[
	["CTRL+ENTER"]
	]], --Keybind that will be used to add entry to playlist based on cursor position
	list_add_playlist_highlighted_keybind=[[
	["SHIFT+ENTER"]
	]], --Keybind that will be used to add all highlighted entries to playlist
	list_close_keybind=[[
	["ESC", "MBTN_RIGHT"]
	]], --Keybind that will be used to close the list (closes search first if it is open)
	list_delete_keybind=[[
	["DEL"]
	]], --Keybind that will be used to delete the entry based on cursor position
	list_delete_highlighted_keybind=[[
	["SHIFT+DEL"]
	]], --Keybind that will be used to delete all highlighted entries from the list
	list_search_activate_keybind=[[
	["ctrl+f", "ctrl+F"]
	]], --Keybind that will be used to trigger search
	list_search_not_typing_mode_keybind=[[
	["ALT+ENTER"]
	]], --Keybind that will be used to exit typing mode of search while keeping search open
	list_ignored_keybind=[[
	["B", "b", "k", "K", "c", "C"]
	]], --Keybind thats are ignored when list is open

---------------------------END OF USER CUSTOMIZATION SETTINGS---------------------------
}

read_list_options(o, SUITE_CONF)
utils = require 'mp.utils'
msg = require 'mp.msg'

o.history_blacklist = utils.parse_json(o.history_blacklist) or { "" }
o.history_incognito_mode_keybind = utils.parse_json(o.history_incognito_mode_keybind)
o.filters_and_sequence = utils.parse_json(o.filters_and_sequence)
o.keywords_filter_list = utils.parse_json(o.keywords_filter_list)
o.list_filters_sort = utils.parse_json(o.list_filters_sort)
o.logging_protocols = utils.parse_json(o.logging_protocols)
o.history_resume_keybind = utils.parse_json(o.history_resume_keybind)
o.history_load_last_keybind = utils.parse_json(o.history_load_last_keybind)
o.osd_time_format = utils.parse_json(o.osd_time_format)
o.list_time_format = utils.parse_json(o.list_time_format)
o.header_duration_time_format = utils.parse_json(o.header_duration_time_format)
o.header_length_time_format = utils.parse_json(o.header_length_time_format)
o.header_remaining_time_format = utils.parse_json(o.header_remaining_time_format)
o.list_move_up_keybind = utils.parse_json(o.list_move_up_keybind)
o.list_move_down_keybind = utils.parse_json(o.list_move_down_keybind)
o.list_page_up_keybind = utils.parse_json(o.list_page_up_keybind)
o.list_page_down_keybind = utils.parse_json(o.list_page_down_keybind)
o.list_move_first_keybind = utils.parse_json(o.list_move_first_keybind)
o.list_move_last_keybind = utils.parse_json(o.list_move_last_keybind)
o.list_highlight_move_keybind = utils.parse_json(o.list_highlight_move_keybind)
o.list_highlight_all_keybind = utils.parse_json(o.list_highlight_all_keybind)
o.list_unhighlight_all_keybind = utils.parse_json(o.list_unhighlight_all_keybind)
o.list_cycle_sort_keybind = utils.parse_json(o.list_cycle_sort_keybind)
o.list_select_keybind = utils.parse_json(o.list_select_keybind)
o.list_add_playlist_keybind = utils.parse_json(o.list_add_playlist_keybind)
o.list_add_playlist_highlighted_keybind = utils.parse_json(o.list_add_playlist_highlighted_keybind)
o.list_close_keybind = utils.parse_json(o.list_close_keybind)
o.list_delete_keybind = utils.parse_json(o.list_delete_keybind)
o.list_delete_highlighted_keybind = utils.parse_json(o.list_delete_highlighted_keybind)
o.list_search_activate_keybind = utils.parse_json(o.list_search_activate_keybind)
o.list_search_not_typing_mode_keybind = utils.parse_json(o.list_search_not_typing_mode_keybind)
o.next_filter_sequence_keybind = utils.parse_json(o.next_filter_sequence_keybind)
o.previous_filter_sequence_keybind = utils.parse_json(o.previous_filter_sequence_keybind)
o.open_list_keybind = utils.parse_json(o.open_list_keybind)
o.list_filter_jump_keybind = utils.parse_json(o.list_filter_jump_keybind)
o.list_ignored_keybind = utils.parse_json(o.list_ignored_keybind)

if utils.shared_script_property_set then
    utils.shared_script_property_set('simplehistory-menu-open', 'no')
end
mp.set_property('user-data/simplehistory/menu-open', 'no')

if string.lower(o.log_path) == '/:dir%mpvconf%' then
	o.log_path = mp.find_config_file('.')
elseif string.lower(o.log_path) == '/:dir%script%' then
	o.log_path = debug.getinfo(1).source:match('@?(.*/)')
elseif o.log_path:match('/:var%%(.*)%%') then
	local os_variable = o.log_path:match('/:var%%(.*)%%')
	o.log_path = o.log_path:gsub('/:var%%(.*)%%', os.getenv(os_variable))
end
log_fullpath = utils.join_path(o.log_path, o.log_file)

log_length_text = 'length='
log_time_text = 'time='
protocols = {'https?:', 'magnet:', 'rtmps?:', 'smb:', 'ftps?:', 'sftp:'}
available_filters = {'all', 'recents', 'distinct', 'playing', 'protocols', 'fileonly', 'titleonly', 'timeonly', 'keywords'}
available_sorts = {'added-asc', 'added-desc', 'time-asc', 'time-desc', 'alphanum-asc', 'alphanum-desc'}
search_string = ''
search_active = false

incognito_mode = false
autosaved_entry = false
incognito_auto_run_triggered = false

loadTriggered = false --1.1.5# to identify if load is triggered atleast once for idle option
resume_selected = false
list_contents = {}
list_start = 0
list_cursor = 1
list_highlight_cursor = {}
list_drawn = false
list_pages = {}
filePath, fileTitle, fileLength = nil, nil, nil
seekTime = 0
logTime = 0 --1.3# use logTime since seekTime is used in multiple places
filterName = 'all'
sortName = nil










---------Start of LogManager---------
--LogManager (Read and Format the List from Log)--

function read_log_table()
	local line_pos = 0
	return read_log(function(line)
		local tt, p, t, s, d, n, e, l, dt, ln, r
		if line:match('^.-\"(.-)\"') then
			tt = line:match('^.-\"(.-)\"')
			n, p = line:match('^.-\"(.-)\" | (.*) | ' .. esc_string(log_length_text) .. '(.*)')
		else
			p = line:match('[(.*)%]]%s(.*) | ' .. esc_string(log_length_text) .. '(.*)')
			d, n, e = p:match('^(.-)([^\\/]-)%.([^\\/%.]-)%.?$')
		end
		dt = line:match('%[(.-)%]')
		t = line:match(' | ' .. esc_string(log_time_text) .. '(%d*%.?%d*)(.*)$')
		ln = line:match(' | ' .. esc_string(log_length_text) .. '(%d*%.?%d*)(.*)$')
		r = tonumber(ln) - tonumber(t)
		l = line
		line_pos = line_pos + 1
		return {found_path = p, found_time = t, found_name = n, found_title = tt, found_line = l, found_sequence = line_pos, found_directory = d, found_datetime = dt, found_length = ln, found_remaining = r}
	end)
end



function get_list_contents(filter, sort)
	if not filter then filter = filterName end
	if not sort then sort = get_list_sort(filter) end
	
	local current_sort

	local filtered_table = {}

	local prev_list_contents
	if list_contents ~= nil and list_contents[1] then 
		prev_list_contents = list_contents
	else
		prev_list_contents = read_log_table()
	end
	
	list_contents = read_log_table()
	if not list_contents and not search_active or not list_contents[1] and not search_active then return end
	current_sort = 'added-asc'
	
	if filter == 'recents' then
		table.sort(list_contents, function(a, b) return a['found_sequence'] < b['found_sequence'] end)
		local unique_values = {}
		local list_total = #list_contents
		
		if filePath == list_contents[#list_contents].found_path and tonumber(list_contents[#list_contents].found_time) == 0 then
			list_total = list_total -1
		end
	
		for i = list_total, 1, -1 do
			if not has_value(unique_values, list_contents[i].found_path) then
				table.insert(unique_values, list_contents[i].found_path)
				table.insert(filtered_table, list_contents[i])
			end
		end
		table.sort(filtered_table, function(a, b) return a['found_sequence'] < b['found_sequence'] end)
		
		list_contents = filtered_table
	
	end
	
	if filter == 'distinct' then
		table.sort(list_contents, function(a, b) return a['found_sequence'] < b['found_sequence'] end)
		local unique_values = {}
		local list_total = #list_contents
		
		if filePath == list_contents[#list_contents].found_path and tonumber(list_contents[#list_contents].found_time) == 0 then
			list_total = list_total -1
		end
	
		for i = list_total, 1, -1 do
			if list_contents[i].found_directory and not has_value(unique_values, list_contents[i].found_directory) and not starts_protocol(protocols, list_contents[i].found_path) then
				table.insert(unique_values, list_contents[i].found_directory)
				table.insert(filtered_table, list_contents[i])
			end
		end
		table.sort(filtered_table, function(a, b) return a['found_sequence'] < b['found_sequence'] end)
		
		list_contents = filtered_table
	end
	
	if filter == 'fileonly' then
		for i = 1, #list_contents do
			if tonumber(list_contents[i].found_time) == 0 then
				table.insert(filtered_table, list_contents[i])
			end
		end
		
		list_contents = filtered_table
	end
	
	if filter == 'timeonly' then
		for i = 1, #list_contents do
			if tonumber(list_contents[i].found_time) > 0 then
				table.insert(filtered_table, list_contents[i])
			end
		end
		
		list_contents = filtered_table
	end
	
	if filter == 'titleonly' then
		for i = 1, #list_contents do
			if list_contents[i].found_title then
				table.insert(filtered_table, list_contents[i])
			end
		end
		
		list_contents = filtered_table
	end
	
	if filter == 'protocols' then
		for i = 1, #list_contents do
			if starts_protocol(o.logging_protocols, list_contents[i].found_path) then
				table.insert(filtered_table, list_contents[i])
			end
		end
		
		list_contents = filtered_table
	end
	
	if filter == 'keywords' then
		for i = 1, #list_contents do
			if contain_value(o.keywords_filter_list, list_contents[i].found_line) then
				table.insert(filtered_table, list_contents[i])
			end
		end
		
		list_contents = filtered_table
	end
	
	if filter == 'playing' then
		for i = 1, #list_contents do
			if list_contents[i].found_path == filePath then
				table.insert(filtered_table, list_contents[i])
			end
		end
		
		list_contents = filtered_table
	end
	
	if search_active and search_string ~= '' then
		local filtered_table = {}
		
		local search_query = ''
		for search in search_string:gmatch("[^%s]+") do
			search_query = search_query..'.-'..esc_string(search)
		end
		
		local contents_string = ''
		for i = 1, #list_contents do
			
			if o.search_behavior == 'specific' then
				if string.lower(list_contents[i].found_path):match(string.lower(search_query)) then
					table.insert(filtered_table, list_contents[i])
				elseif list_contents[i].found_title and string.lower(list_contents[i].found_title):match(string.lower(search_query)) then
					table.insert(filtered_table, list_contents[i])
				elseif tonumber(list_contents[i].found_time) > 0 and format_time(list_contents[i].found_time, o.osd_time_format[3], o.osd_time_format[2], o.osd_time_format[1]):match(search_query) then
					table.insert(filtered_table, list_contents[i])
				elseif string.lower(list_contents[i].found_datetime):match(string.lower(search_query)) then
					table.insert(filtered_table, list_contents[i])
				end
			elseif o.search_behavior == 'any' then
				contents_string = list_contents[i].found_datetime..(list_contents[i].found_title or '')..list_contents[i].found_path
				if tonumber(list_contents[i].found_time) > 0 then 
					contents_string = contents_string..format_time(list_contents[i].found_time, o.osd_time_format[3], o.osd_time_format[2], o.osd_time_format[1])
				end
			elseif o.search_behavior == 'any-notime' then
				contents_string = list_contents[i].found_datetime..(list_contents[i].found_title or '')..list_contents[i].found_path
			end
			
			if string.lower(contents_string):match(string.lower(search_query)) then
				table.insert(filtered_table, list_contents[i])
			end
		end
		
		list_contents = filtered_table
		
	end
	
	if sort ~= current_sort then
		list_sort(list_contents, sort)
	end
	
	if not list_contents and not search_active or not list_contents[1] and not search_active then return end
end


function draw_list()
	local osd_msg = ''
	local osd_index = ''
	local osd_key = ''
	local osd_color = ''
	local key = 0
	local osd_text = string.format("{\\an%f{\\fscx%f}{\\fscy%f}{\\bord%f}{\\1c&H%s}", o.list_alignment, o.text_scale, o.text_scale, o.text_border, o.text_color)
	local osd_cursor = string.format("{\\an%f}{\\fscx%f}{\\fscy%f}{\\bord%f}{\\1c&H%s}", o.list_alignment, o.text_cursor_scale, o.text_cursor_scale, o.text_cursor_border, o.text_cursor_color)
	local osd_header = string.format("{\\an%f}{\\fscx%f}{\\fscy%f}{\\bord%f}{\\1c&H%s}", o.list_alignment, o.header_scale, o.header_scale, o.header_border, o.header_color)
	local osd_msg_end = "{\\1c&HFFFFFF}"
	local osd_time_type = 'found_time'
	
	if o.text_time_type == 'length' then
		osd_time_type = 'found_length'
	elseif o.text_time_type == 'remaining' then
		osd_time_type = 'found_remaining'
	end
	
	if o.header_text ~= '' then
		osd_msg = osd_msg .. osd_header .. parse_header(o.header_text)
		osd_msg = osd_msg .. "\\h\\N\\N" .. osd_msg_end
	end
	
	if search_active and not list_contents[1] then
		osd_msg = osd_msg .. 'No search results found' .. osd_msg_end
	end
	
	if o.list_middle_loader then
		list_start = list_cursor - math.floor(o.list_show_amount / 2)
	else
		list_start = list_cursor - o.list_show_amount
	end
	
	local showall = false
	local showrest = false
	if list_start < 0 then list_start = 0 end
	if #list_contents <= o.list_show_amount then
		list_start = 0
		showall = true
	end
	if list_start > math.max(#list_contents - o.list_show_amount - 1, 0) then
		list_start = #list_contents - o.list_show_amount
		showrest = true
	end
	if list_start > 0 and not showall then
		osd_msg = osd_msg .. o.list_sliced_prefix .. osd_msg_end
	end
	for i = list_start, list_start + o.list_show_amount - 1, 1 do
		if i == #list_contents then break end
		
		if o.show_paths then
			p = list_contents[#list_contents - i].found_path or list_contents[#list_contents - i].found_name or ""
		else
			p = list_contents[#list_contents - i].found_name or list_contents[#list_contents - i].found_path or ""
		end
		
		if o.slice_longfilenames and p:len() > o.slice_longfilenames_amount then
			p = p:sub(1, o.slice_longfilenames_amount) .. "..."
		end
		
		if o.quickselect_0to9_keybind and o.list_show_amount <= 10 and o.quickselect_0to9_pre_text then
			key = 1 + key
			if key == 10 then key = 0 end
			osd_key = '(' .. key .. ')  '
		end
		
		if o.show_item_number then
			osd_index = (i + 1) .. '. '
		end
		
		if i + 1 == list_cursor then
			osd_color = osd_cursor
		else
			osd_color = osd_text
		end
		
		for j = 1, #list_highlight_cursor do
			if list_highlight_cursor[j] and list_highlight_cursor[j][1] == i+1 then
				osd_msg = osd_msg..osd_color..esc_string(o.text_highlight_pre_text)
			end
		end
		
		osd_msg = osd_msg .. osd_color .. osd_key .. osd_index .. p
		
		if list_contents[#list_contents - i][osd_time_type] and tonumber(list_contents[#list_contents - i][osd_time_type]) > 0 then
			osd_msg = osd_msg .. o.time_seperator .. format_time(list_contents[#list_contents - i][osd_time_type], o.list_time_format[3], o.list_time_format[2], o.list_time_format[1])
		end
		
		osd_msg = osd_msg .. '\\h\\N\\N' .. osd_msg_end
		
		if i == list_start + o.list_show_amount - 1 and not showall and not showrest then
			osd_msg = osd_msg .. o.list_sliced_suffix
		end
	
	end
	mp.set_osd_ass(0, 0, osd_msg)
end

function list_empty_error_msg()
	if list_contents ~= nil and list_contents[1] then return end
	local msg_text
	if filterName ~= 'all' then
		msg_text = filterName .. " filter in History Empty"
	else
		msg_text = "History Empty"
	end
	msg.info(msg_text)
	if o.osd_messages == true and not list_drawn then
		mp.osd_message(msg_text)
	end
end

function display_list(filter, sort, action)
	if not filter or not has_value(available_filters, filter) then filter = 'all' end
	if not sortName then sortName = get_list_sort(filter) end
	
	local prev_sort = sortName
	if not has_value(available_sorts, prev_sort) then prev_sort = get_list_sort() end

	if not sort then sort = get_list_sort(filter) end
	sortName = sort

	local prev_filter = filterName
	filterName = filter
	
	get_list_contents(filter, sort)
	
	if action ~= 'hide-osd' then
		if not list_contents or not list_contents[1] then
			list_empty_error_msg()
			filterName = prev_filter
			get_list_contents(filterName)
			return
		end
	end
	if not list_contents and not search_active or not list_contents[1] and not search_active then return end
	
	if not has_value(o.filters_and_sequence, filter) then
		table.insert(o.filters_and_sequence, filter)
	end
	
	local insert_new = false
	
	local trigger_close_list = false
	local trigger_initial_list = false
	
	
	if not list_pages or not list_pages[1] then
		table.insert(list_pages, {filter, 1, 1, {}, sort})
	else
		for i = 1, #list_pages do
			if list_pages[i][1] == filter then
				list_pages[i][3] = list_pages[i][3]+1
				insert_new = false
				break
			else
				insert_new = true
			end
		end
	end
	
	if insert_new then table.insert(list_pages, {filter, 1, 1, {}, sort}) end
	
	for i = 1, #list_pages do
		if not search_active and list_pages[i][1] == prev_filter then
			list_pages[i][2] = list_cursor
			list_pages[i][4] = list_highlight_cursor
			list_pages[i][5] = prev_sort
		end
		if list_pages[i][1] ~= filter then
			list_pages[i][3] = 0
		end
		if list_pages[i][3] == 2 and filter == 'all' and o.main_list_keybind_twice_exits then
			trigger_close_list = true
		elseif list_pages[i][3] == 2 and list_pages[1][1] == filter then
			trigger_close_list = true		
		elseif list_pages[i][3] == 2 then
			trigger_initial_list = true
		end
	end
	
	if trigger_initial_list then
		display_list(list_pages[1][1], nil, 'hide-osd')
		return
	end
	
	if trigger_close_list then
		list_close_and_trash_collection()
		return
	end
	
	if not search_active then get_page_properties(filter) else update_search_results('','') end
	draw_list()
	if utils.shared_script_property_set then
		utils.shared_script_property_set('simplehistory-menu-open', 'yes')
	end
	mp.set_property('user-data/simplehistory/menu-open', 'yes')
	if o.toggle_idlescreen then mp.commandv('script-message', 'osc-idlescreen', 'no', 'no_osd') end --1.1.6# fix osc-idlescreen (value was yes for some reason)
	list_drawn = true
	if not search_active then get_list_keybinds() end
end

--End of LogManager (Read and Format the List from Log)--

--LogManager Navigation--








--End of LogManager Navigation--

--LogManager Actions--











--End of LogManager Actions--

--LogManager Filter Functions--


--End of LogManager Filter Functions--

--LogManager (List Bind and Unbind)--


function list_close_and_trash_collection()
	if utils.shared_script_property_set then
		utils.shared_script_property_set('simplehistory-menu-open', 'no')
	end
	mp.set_property('user-data/simplehistory/menu-open', 'no')
	if o.toggle_idlescreen then mp.commandv('script-message', 'osc-idlescreen', 'yes', 'no_osd') end
	unbind_list_keys()
	unbind_search_keys()
	mp.set_osd_ass(0, 0, "")
	list_drawn = false
	list_cursor = 1
	list_start = 0
	filterName = 'all'
	list_pages = {}
	search_string = ''
	search_active = false
	list_highlight_cursor = {}
	sortName = nil
end
--End of LogManager (List Bind and Unbind)--

--LogManager Search Feature--





--End of LogManager Search Feature--
---------End of LogManager---------

function history_blacklist_check()
	local history_blacklist = o.history_blacklist or { "" }
	if type(history_blacklist) ~= "table" then
		history_blacklist = { "" }
	end
	if not history_blacklist[1] or #history_blacklist == 1 and history_blacklist[1] == "" then return false end
	local invertable_return = {true, false}
	local blacklist_msg = 'File was not added to history because of blacklist'
	if o.invert_history_blacklist then 
		invertable_return = {false, true} 
		blacklist_msg = 'File was added to history because of whitelist'
	end
	
	if has_value(history_blacklist, filePath, nil) then
		msg.info(blacklist_msg)
		return invertable_return[1]
	elseif not starts_protocol(protocols, filePath) then
		if has_value(history_blacklist, filePath:match('^(.-)([^\\/]-)%.([^\\/%.]-)%.?$'), nil) or 
		has_value(history_blacklist, filePath:match('^(.-)([^\\/]-)%.([^\\/%.]-)%.?$'):gsub('\\$', ''), nil) then
			msg.info(blacklist_msg)
			return invertable_return[1]
		elseif has_value(history_blacklist, filePath:match('%.([^%.]+)$'), nil) or
		has_value(history_blacklist, "."..filePath:match('%.([^%.]+)$'), nil) then
			msg.info(blacklist_msg)
			return invertable_return[1]
		else --1.1.2# check to add any subfolder after /* to blacklist. issue #70
			for i=1, #history_blacklist do --1.1.2# loop through blacklisted items, if the blacklist ends with * and it is a match after subbing of the current filePath then log it. #and additionally if it is the exact same path then ignore it.
				if string.lower(filePath):match(string.lower(history_blacklist[i])) and history_blacklist[i]:sub(-1,#history_blacklist[i]) == '*' and string.lower(history_blacklist[i]:sub(1,-2)) ~= string.lower(filePath):match("(.*[\\/])") then
					msg.info(blacklist_msg)
					return invertable_return[1]
				end
			end
		end
	elseif starts_protocol(protocols, filePath) then
		if has_value(history_blacklist, filePath:match('(.-)(:)'), nil) or
		has_value(history_blacklist, filePath:match('(.-:)'), nil) or
		has_value(history_blacklist, filePath:match('(.-:/?/?)'), nil) then
			msg.info(blacklist_msg)
			return invertable_return[1]
		elseif filePath:find('https?://') == 1 then
			local difchk_1, difchk_2 = filePath:match("(https?://)w?w?w?%.?([%w%.%:]*)")
			local different_check_temp = difchk_1..difchk_2
			local different_checks = {different_check_temp, filePath:match("https?://w?w?w?%.?([%w%.%:]*)"), filePath:match("https?://([%w%.%:]*)"), filePath:match("(https?://[%w%.%:]*)") }
			for i = 1, #different_checks do
				if different_checks[i] and has_value(history_blacklist, different_checks[i], nil)
				or different_checks[i]..'/' and has_value(history_blacklist, different_checks[i]..'/', nil) then
					msg.info(blacklist_msg)
					return invertable_return[1]
				end
			end
		end
	end
	
	return invertable_return[2]
end

function mark_chapter()
	if not o.mark_history_as_chapter then return end
	
	local all_chapters = mp.get_property_native("chapter-list")
	local chapter_index = 0
	local chapters_time = {}
	
	get_list_contents()
	if not list_contents or not list_contents[1] then return end
	for i = 1, #list_contents do
		if list_contents[i].found_path == filePath and tonumber(list_contents[i].found_time) > 0 then
			table.insert(chapters_time, tonumber(list_contents[i].found_time))
		end
	end
	if not chapters_time[1] then return end
	
	table.sort(chapters_time, function(a, b) return a < b end)
	
	for i = 1, #chapters_time do
		chapter_index = chapter_index + 1
		
		all_chapters[chapter_index] = {
			title = 'SimpleHistory ' .. chapter_index,
			time = chapters_time[i]
		}
	end
	
	table.sort(all_chapters, function(a, b) return a['time'] < b['time'] end)
	
	mp.set_property_native("chapter-list", all_chapters)
end

function write_log(target_time, update_seekTime, entry_limit)
	if not filePath then return end
	local prev_seekTime = seekTime
	seekTime = (mp.get_property_number('time-pos') or 0)
	if target_time then
		seekTime = target_time
	end
	if seekTime < 0 then seekTime = 0 end
	
	delete_log_entry(false, true, filePath, math.floor(seekTime), entry_limit)

	local f = io.open(log_fullpath, "a+")
	if o.file_title_logging == 'all' then
		f:write(("[%s] \"%s\" | %s | %s | %s"):format(os.date(o.date_format), fileTitle, filePath, log_length_text .. tostring(fileLength), log_time_text .. tostring(seekTime)))
	elseif o.file_title_logging == 'protocols' and (starts_protocol(o.logging_protocols, filePath)) then
		f:write(("[%s] \"%s\" | %s | %s | %s"):format(os.date(o.date_format), fileTitle, filePath, log_length_text .. tostring(fileLength), log_time_text .. tostring(seekTime)))
	elseif o.file_title_logging == 'protocols' and not (starts_protocol(o.logging_protocols, filePath)) then
		f:write(("[%s] %s | %s | %s"):format(os.date(o.date_format), filePath, log_length_text .. tostring(fileLength), log_time_text .. tostring(seekTime)))
	else
		f:write(("[%s] %s | %s | %s"):format(os.date(o.date_format), filePath, log_length_text .. tostring(fileLength), log_time_text .. tostring(seekTime)))
	end

	f:write('\n')
	f:close()
	
	if not update_seekTime then
		seekTime = prev_seekTime
	end
end

function history_incognito_mode()
	if not incognito_mode then
		incognito_mode = true
		if o.osd_messages == true then
			mp.osd_message('🕵 Incognito Mode Enabled')
		end
		msg.info('Incognito Mode Enabled')
		
		if o.delete_incognito_entry and autosaved_entry == true then
			delete_log_entry_specific('last', filePath, 0)
			autosaved_entry = 'autosaved-restore'
			if list_drawn then
				get_list_contents()
				select(0)
			end
		end
	else
		incognito_mode = false
		if o.osd_messages == true then
			mp.osd_message('Incognito Mode Disabled')
		end
		msg.info('Incognito Mode Disabled')
		
		if o.restore_incognito_entry == 'always' then
			history_fileonly_save()
			autosaved_entry = true
		elseif o.restore_incognito_entry == 'deleted-restore' and autosaved_entry == 'autosaved-restore' then
			history_fileonly_save()
			autosaved_entry = true
			if list_drawn then
				get_list_contents()
				select(0)
			end
		end
	end
end

function history_resume_option()
	if o.resume_option == 'notification' or o.resume_option == 'force' then
		local video_time = mp.get_property_number('time-pos')
		local video_path = mp.get_property('path') --1.1.4# local variable instead of filePath
		if video_time > 0 then return end
		local logged_time = 0
		local percentage = 0
		local video_duration = (mp.get_property_number('duration') or 0)
		list_contents = read_log_table()
		if not list_contents or not list_contents[1] then return end
		for i = #list_contents, 1, -1 do
			if list_contents[i].found_path == video_path and tonumber(list_contents[i].found_time) > 0 then --1.1.4# instead of filePath in case it is causing issue
				logged_time = tonumber(list_contents[i].found_time) + o.resume_offset
				break
			end
		end
		if logged_time > 0 then
			percentage = math.floor((logged_time / video_duration) * 100 + 0.5)
			if o.resume_option == 'notification' then
				if percentage > o.resume_option_threshold and percentage < (100-o.resume_option_threshold) or o.resume_option_threshold == 0 then
					mp.osd_message('⌨ [' .. string.upper(o.history_resume_keybind[1]) .. '] Resumes To' .. o.time_seperator .. format_time(logged_time, o.osd_time_format[3], o.osd_time_format[2], o.osd_time_format[1]),3)
				end
			elseif o.resume_option == 'force' then
				if percentage > o.resume_option_threshold and percentage < (100-o.resume_option_threshold) or o.resume_option_threshold == 0 then
					mp.commandv('seek', logged_time, 'absolute', 'exact')
					if (o.osd_messages == true) then
						mp.osd_message('Resumed To Last Played Position\n' .. o.time_seperator .. format_time(logged_time, o.osd_time_format[3], o.osd_time_format[2], o.osd_time_format[1]))
					end
					msg.info('Resumed to the last played position')
				end
			end
		end
	end
end

function history_save(target_time)
	if filePath ~= nil then
		if history_blacklist_check() then
			return
		end
		write_log(target_time, false, o.same_entry_limit)
		if list_drawn then
			get_list_contents()
			select(0)
		end
		msg.info('Added the below into history\n' .. fileTitle .. o.time_seperator .. format_time(seekTime))
	else
		msg.info("Failed to add into history")
	end
end

function history_fileonly_save()
	if filePath ~= nil then
		if history_blacklist_check() then
			return
		end
		write_log(0, false)
		if list_drawn then
			get_list_contents()
			select(0)
		end
		msg.info('Added the below into history\n' .. fileTitle .. o.time_seperator .. format_time(seekTime))
	else
		msg.info("Failed to add into history, no file found")
	end
end

function history_resume()
	if filePath == nil then
		list_contents = read_log_table()
		load(1)
	elseif filePath ~= nil then
		list_contents = read_log_table()
		if list_contents ~= nil and list_contents[1] then
			for i = #list_contents, 1, -1 do
				if list_contents[i].found_path == filePath and tonumber(list_contents[i].found_time) > 0 then
					seekTime = tonumber(list_contents[i].found_time) + o.resume_offset
					break
				end
			end
		end
		if seekTime > 0 then
			mp.commandv('seek', seekTime, 'absolute', 'exact')
			if (o.osd_messages == true) then
				mp.osd_message('Resumed To Last Played Position\n' .. o.time_seperator .. format_time(seekTime, o.osd_time_format[3], o.osd_time_format[2], o.osd_time_format[1]))
			end
			msg.info('Resumed to the last played position')
		else
			if (o.osd_messages == true) then
				mp.osd_message('No Resume Position Found For This Video')
			end
			msg.info('No resume position found for this video')
		end
	end
end

function history_load_last()
	if filePath == nil then
		list_contents = read_log_table()
		load(1, false, 0)
	elseif filePath ~= nil then
		list_contents = read_log_table()
		load(2, true)
	end
end

mp.register_event('file-loaded', function()
	list_close_and_trash_collection()
	filePath, fileTitle, fileLength = get_file()
	loadTriggered = true --1.1.5# for resume and resume-notime startup behavior (so that it only triggers if started as idle and only once)
	if (resume_selected == true and seekTime > 0) then
		mp.commandv('seek', seekTime, 'absolute', 'exact')
		resume_selected = false
	end
	history_resume_option() --1.1.4# remove timeout, cant remember why I put it in first place
	mark_chapter()
	if not incognito_mode then
		history_fileonly_save()
		autosaved_entry = true
	end
end)

mp.add_hook('on_unload', 9, function()--1.1.3# get the LogTime only when using on_unload because big functions do not run fully in here
	logTime = (mp.get_property_number('time-pos') or 0)
end)
mp.register_event('end-file', function()--1.1.3# use end-file instead so that it doesn't cause crash while seeking ( i am able to run big functions here)
	if not incognito_mode then
		if autosaved_entry == true then delete_log_entry_specific('last', filePath, 0) end
		history_save(logTime) --1.1.3# get the updated time from on_unload since it will still be preserved
	end
	autosaved_entry = false
	logTime = 0 --1.1.3# reset logTime to 0
end)

mp.observe_property("idle-active", "bool", function(_, v)
	if v then --1.1.2# if idle is triggered
		filePath, fileTitle, fileLength = nil --1.1.2# set it back to nil if idle is triggered for better trash collection. issue #69
	end
	
	if v and o.startup_idle_behavior == 'resume' and not loadTriggered then --1.1.5# option to resume on startup
		history_resume()
	elseif v and o.startup_idle_behavior == 'resume-notime' and not loadTriggered then --1.1.5# option to load last item on startup
		history_load_last()
	elseif v and has_value(available_filters, o.auto_run_list_idle) then
		display_list(o.auto_run_list_idle, nil, 'hide-osd')
	end
	
	if v and o.auto_run_incognito_mode and not incognito_auto_run_triggered or
	not v and o.auto_run_incognito_mode and not incognito_auto_run_triggered then
		history_incognito_mode()
		incognito_auto_run_triggered = true
	end
end)

bind_keys(o.history_resume_keybind, 'history-resume', history_resume)
bind_keys(o.history_load_last_keybind, 'history-load-last', history_load_last)
bind_keys(o.history_incognito_mode_keybind, 'history-incognito-mode', history_incognito_mode)

for i = 1, #o.open_list_keybind do
	if i == 1 then
		mp.add_forced_key_binding(o.open_list_keybind[i][1], 'open-list', function()display_list(o.open_list_keybind[i][2]) end)
	else
		mp.add_forced_key_binding(o.open_list_keybind[i][1], 'open-list'..i, function()display_list(o.open_list_keybind[i][2]) end)
	end
end
