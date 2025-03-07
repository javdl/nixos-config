# Common Vim configuration
{ config, lib, pkgs, ... }:

{
  # Neovim configuration
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    
    plugins = with pkgs.vimPlugins; [
      # UI
      vim-airline
      vim-airline-themes
      vim-gitgutter
      
      # Syntax highlighting and language support
      vim-nix
      vim-markdown
      rust-vim
      typescript-vim
      vim-javascript
      vim-go
      
      # Editing features
      vim-surround
      vim-commentary
      vim-fugitive
      vim-repeat
      
      # Navigation
      fzf-vim
      nvim-tree-lua
      
      # LSP
      nvim-lspconfig
      
      # Completion
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      
      # Snippets
      vim-snippets
      cmp-vsnip
    ];
    
    extraConfig = ''
      " General settings
      set number
      set relativenumber
      set cursorline
      set expandtab
      set tabstop=2
      set shiftwidth=2
      set smartindent
      set ignorecase
      set smartcase
      set clipboard=unnamedplus
      
      " Set colorscheme
      set background=dark
      colorscheme desert
      
      " Key mappings
      let mapleader = ","
      nnoremap <leader>f :FZF<CR>
      nnoremap <leader>b :Buffers<CR>
      nnoremap <leader>g :Rg<CR>
      
      " Plugin settings
      let g:airline_powerline_fonts = 1
      let g:airline_theme='minimalist'
    '';
  };
}