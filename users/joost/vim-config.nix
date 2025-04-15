{ sources }:
''
"--------------------------------------------------------------------
" Fix vim paths so we load the vim-misc directory
let g:vim_home_path = "~/.vim"

" This works on NixOS 21.05
let vim_misc_path = split(&packpath, ",")[0] . "/pack/home-manager/start/vim-misc/vimrc.vim"
if filereadable(vim_misc_path) && !has('nvim')
  execute "source " . vim_misc_path
endif

" This works on NixOS 21.11
let vim_misc_path = split(&packpath, ",")[0] . "/pack/home-manager/start/vimplugin-vim-misc/vimrc.vim"
if filereadable(vim_misc_path) && !has('nvim')
  execute "source " . vim_misc_path
endif

" This works on NixOS 22.11
let vim_misc_path = split(&packpath, ",")[0] . "/pack/myNeovimPackages/start/vimplugin-vim-misc/vimrc.vim"
if filereadable(vim_misc_path) && !has('nvim')
  execute "source " . vim_misc_path
endif

" Neovim-specific settings when using vim-misc
if has('nvim')
  set mouse=a
  set termguicolors
  set clipboard+=unnamedplus

  " Basic settings from vim-misc that we still want
  set encoding=utf-8
  set autoread
  set backspace=2
  set colorcolumn=80
  set hidden
  set laststatus=2
  set number
  set ruler
  set t_Co=256
  set scrolloff=999
  set showmatch
  set showmode
  set splitbelow
  set splitright
  set visualbell

  " Color scheme settings
  syntax on
  set runtimepath+=pack/*/start/onehalf/vim
  colorscheme onehalfdark

  " Search settings
  set hlsearch
  set ignorecase
  set incsearch
  set smartcase

  " Tab settings
  set expandtab
  set tabstop=4
  set softtabstop=4
  set shiftwidth=4
endif

lua <<EOF
---------------------------------------------------------------------
-- Add our custom treesitter parsers
local parser_config = require "nvim-treesitter.parsers".get_parser_configs()

---------------------------------------------------------------------
-- Add our treesitter textobjects
require'nvim-treesitter.configs'.setup {
  textobjects = {
    select = {
      enable = true,
      keymaps = {
        -- You can use the capture groups defined in textobjects.scm
        ["af"] = "@function.outer",
        ["if"] = "@function.inner",
        ["ac"] = "@class.outer",
        ["ic"] = "@class.inner",
      },
    },

    move = {
      enable = true,
      set_jumps = true, -- whether to set jumps in the jumplist
      goto_next_start = {
        ["]m"] = "@function.outer",
        ["]]"] = "@class.outer",
      },
      goto_next_end = {
        ["]M"] = "@function.outer",
        ["]["] = "@class.outer",
      },
      goto_previous_start = {
        ["[m"] = "@function.outer",
        ["[["] = "@class.outer",
      },
      goto_previous_end = {
        ["[M"] = "@function.outer",
        ["[]"] = "@class.outer",
      },
    },
  },
}


---------------------------------------------------------------------
-- Gitsigns

require('gitsigns').setup()

---------------------------------------------------------------------
-- Lualine

require('lualine').setup()

---------------------------------------------------------------------
-- Cinnamon

-- require('cinnamon').setup()
-- require('cinnamon').setup {
--  extra_keymaps = true,
--  override_keymaps = true,
--  scroll_limit = -1,
--}

vim.opt.termsync = false

EOF
''
