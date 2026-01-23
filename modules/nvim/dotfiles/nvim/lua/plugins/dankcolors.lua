return {
	{
		"RRethy/base16-nvim",
		priority = 1000,
		config = function()
			require('base16-colorscheme').setup({
				base00 = '#0e1416',
				base01 = '#0e1416',
				base02 = '#758789',
				base03 = '#758789',
				base04 = '#c3dbde',
				base05 = '#f2fdff',
				base06 = '#f2fdff',
				base07 = '#f2fdff',
				base08 = '#ff3f82',
				base09 = '#ff3f82',
				base0A = '#22d2e9',
				base0B = '#4cfe5c',
				base0C = '#8cf2ff',
				base0D = '#22d2e9',
				base0E = '#4ceaff',
				base0F = '#4ceaff',
			})

			vim.api.nvim_set_hl(0, 'Visual', {
				bg = '#758789',
				fg = '#f2fdff',
				bold = true
			})
			vim.api.nvim_set_hl(0, 'Statusline', {
				bg = '#22d2e9',
				fg = '#0e1416',
			})
			vim.api.nvim_set_hl(0, 'LineNr', { fg = '#758789' })
			vim.api.nvim_set_hl(0, 'CursorLineNr', { fg = '#8cf2ff', bold = true })

			vim.api.nvim_set_hl(0, 'Statement', {
				fg = '#4ceaff',
				bold = true
			})
			vim.api.nvim_set_hl(0, 'Keyword', { link = 'Statement' })
			vim.api.nvim_set_hl(0, 'Repeat', { link = 'Statement' })
			vim.api.nvim_set_hl(0, 'Conditional', { link = 'Statement' })

			vim.api.nvim_set_hl(0, 'Function', {
				fg = '#22d2e9',
				bold = true
			})
			vim.api.nvim_set_hl(0, 'Macro', {
				fg = '#22d2e9',
				italic = true
			})
			vim.api.nvim_set_hl(0, '@function.macro', { link = 'Macro' })

			vim.api.nvim_set_hl(0, 'Type', {
				fg = '#8cf2ff',
				bold = true,
				italic = true
			})
			vim.api.nvim_set_hl(0, 'Structure', { link = 'Type' })

			vim.api.nvim_set_hl(0, 'String', {
				fg = '#4cfe5c',
				italic = true
			})

			vim.api.nvim_set_hl(0, 'Operator', { fg = '#c3dbde' })
			vim.api.nvim_set_hl(0, 'Delimiter', { fg = '#c3dbde' })
			vim.api.nvim_set_hl(0, '@punctuation.bracket', { link = 'Delimiter' })
			vim.api.nvim_set_hl(0, '@punctuation.delimiter', { link = 'Delimiter' })

			vim.api.nvim_set_hl(0, 'Comment', {
				fg = '#758789',
				italic = true
			})

			local current_file_path = vim.fn.stdpath("config") .. "/lua/plugins/dankcolors.lua"
			if not _G._matugen_theme_watcher then
				local uv = vim.uv or vim.loop
				_G._matugen_theme_watcher = uv.new_fs_event()
				_G._matugen_theme_watcher:start(current_file_path, {}, vim.schedule_wrap(function()
					local new_spec = dofile(current_file_path)
					if new_spec and new_spec[1] and new_spec[1].config then
						new_spec[1].config()
						print("Theme reload")
					end
				end))
			end
		end
	}
}
