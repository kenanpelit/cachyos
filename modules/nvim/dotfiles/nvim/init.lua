-- =======================================================================
-- Neovim Configuration (Pure Lua with Lazy.nvim)
-- =======================================================================

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Set Leader Key (must be set before lazy.nvim setup)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- =======================================================================
-- Lazy.nvim Setup
-- =======================================================================
require("lazy").setup({
  spec = {
    -- LazyVim Core
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },

    -- =======================================================================
    -- Themes
    -- =======================================================================
    {
      "catppuccin/nvim",
      name = "catppuccin",
      priority = 1000,
      config = function()
        require("catppuccin").setup({
          flavour = "mocha",
          transparent_background = false,
          term_colors = true,
        })
        -- Set as default colorscheme
        vim.cmd.colorscheme "catppuccin"
      end,
    },
    {
      "folke/tokyonight.nvim",
      lazy = true, -- load only if switched to
      opts = { style = "storm" },
    },

    -- =======================================================================
    -- Language Support
    -- =======================================================================
    { import = "lazyvim.plugins.extras.lang.typescript" },
    { import = "lazyvim.plugins.extras.lang.json" },
    { import = "lazyvim.plugins.extras.lang.python" },
    { import = "lazyvim.plugins.extras.lang.rust" },
    { import = "lazyvim.plugins.extras.lang.markdown" },

    -- =======================================================================
    -- Formatting & Linting
    -- =======================================================================
    { import = "lazyvim.plugins.extras.formatting.prettier" },
    { import = "lazyvim.plugins.extras.linting.eslint" },

    -- =======================================================================
    -- Editor Enhancements
    -- =======================================================================
    { import = "lazyvim.plugins.extras.editor.telescope" },
    { import = "lazyvim.plugins.extras.ui.treesitter-context" },
    { import = "lazyvim.plugins.extras.util.mini-hipatterns" },

    -- =======================================================================
    -- Git Integration
    -- =======================================================================
    {
      "kdheepak/lazygit.nvim",
      dependencies = { "nvim-lua/plenary.nvim" },
      keys = {
        { "<leader>gg", "<cmd>LazyGit<cr>", desc = "LazyGit" },
      },
    },

    -- =======================================================================
    -- Gemini AI Integration
    -- =======================================================================
    {
      "kiddos/gemini.nvim",
      dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim" },
      opts = {
        model_config = {
          model_id = "gemini-2.0-flash-exp", -- Updated model
          temperature = 0.10,
          top_k = 128,
          response_mime_type = "text/plain",
        },
        chat_config = { enabled = true },
        hints = { enabled = true, hints_delay = 2000 },
        completion = { enabled = true, completion_delay = 800 },
      },
      config = function(_, opts)
        require("gemini").setup(opts)
      end,
    },
  },
  defaults = {
    lazy = false,
    version = false,
  },
  checker = { enabled = true },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin",
      },
    },
  },
})

-- =======================================================================
-- General Settings
-- =======================================================================
local opt = vim.opt

opt.relativenumber = true
opt.number = true
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true
opt.wrap = false
opt.swapfile = false
opt.backup = false
opt.undofile = true
opt.hlsearch = false
opt.incsearch = true
opt.termguicolors = true
opt.scrolloff = 8
opt.signcolumn = "yes"
opt.updatetime = 50
opt.colorcolumn = "80"

-- Desktop environment detection for clipboard
local desktop_env = os.getenv("XDG_CURRENT_DESKTOP") or ""

-- GNOME-specific clipboard safety (prevent freeze with xclip/wl-copy conflict)
if desktop_env == "GNOME" then
  local handle = io.popen("which wl-copy 2>/dev/null")
  local wl_copy_path = handle:read("*a")
  handle:close()

  if wl_copy_path ~= "" then
    vim.opt.clipboard = ""
  else
    -- Fallback to xclip if available
    vim.opt.clipboard = "unnamedplus"
  end
else
  -- Default behavior (Hyprland/Sway uses wl-clipboard via unnamedplus)
  vim.opt.clipboard = "unnamedplus"
end