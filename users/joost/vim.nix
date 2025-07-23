{ inputs }:
self: super:

{
  customVim = with self; {
    vim-copilot = vimUtils.buildVimPlugin {
      name = "vim-copilot";
      src = inputs.vim-copilot;
    };

    vim-misc = vimUtils.buildVimPlugin {
      name = "vim-misc";
      src = inputs.vim-misc;
    };

    nvim-telescope = vimUtils.buildVimPlugin {
      name = "nvim-telescope";
      src = inputs.nvim-telescope;
    };

    nvim-plenary = vimUtils.buildVimPlugin {
      name = "nvim-plenary";
      src = inputs.nvim-plenary;
    };

    nvim-lspconfig = vimUtils.buildVimPlugin {
      name = "nvim-lspconfig";
      src = inputs.nvim-lspconfig;
    };

    nvim-gitsigns = vimUtils.buildVimPlugin {
      name = "nvim-gitsigns";
      src = inputs.nvim-gitsigns;
    };

    nvim-lualine = vimUtils.buildVimPlugin {
      name = "nvim-lualine";
      src = inputs.nvim-lualine;
    };

    nvim-codecompanion = vimUtils.buildVimPlugin {
      name = "nvim-codecompanion";
      src = inputs.nvim-codecompanion;
    };

    nvim-conform = vimUtils.buildVimPlugin {
      name = "nvim-conform";
      src = inputs.nvim-conform;
    };

    nvim-dressing = vimUtils.buildVimPlugin {
      name = "nvim-dressing";
      src = inputs.nvim-dressing;
    };

    nvim-nui = vimUtils.buildVimPlugin {
      name = "nvim-nui";
      src = inputs.nvim-nui;
    };

    nvim-rust = vimUtils.buildVimPlugin {
      name = "nvim-rust";
      src = inputs.nvim-rust;
    };

    nvim-treesitter-context = vimUtils.buildVimPlugin {
      name = "nvim-treesitter-context";
      src = inputs.nvim-treesitter-context;
    };

    nvim-web-devicons = vimUtils.buildVimPlugin {
      name = "nvim-web-devicons";
      src = inputs.nvim-web-devicons;
    };
  };
}