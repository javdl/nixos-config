{ inputs }:
self: super:

let sources = import ../../nix/sources.nix; in rec {
  # My vim config
  customVim = with self; {
    vim-copilot = vimUtils.buildVimPlugin {
      name = "vim-copilot";
      src = inputs.vim-copilot;
    };

    vim-cue = vimUtils.buildVimPlugin {
      name = "vim-cue";
      src = sources.vim-cue;
    };

    vim-fish = vimUtils.buildVimPlugin {
      name = "vim-fish";
      src = sources.vim-fish;
    };

    vim-glsl = vimUtils.buildVimPlugin {
      name = "vim-glsl";
      src = sources.vim-glsl;
    };

    vim-misc = vimUtils.buildVimPlugin {
      name = "vim-misc";
      src = inputs.vim-misc;
    };

    vim-pgsql = vimUtils.buildVimPlugin {
      name = "vim-pgsql";
      src = sources.vim-pgsql;
    };

    vim-tla = vimUtils.buildVimPlugin {
      name = "tla.vim";
      src = sources.vim-tla;
    };

    # vim-zig = vimUtils.buildVimPlugin {
    #   name = "zig.vim";
    #   src = sources.vim-zig;
    # };

    dracula = vimUtils.buildVimPlugin {
      name = "dracula";
      src = sources.vim-dracula;
    };

    onehalf = vimUtils.buildVimPlugin {
      name = "onehalf";
      src = pkgs.fetchFromGitHub {
        owner = "sonph";
        repo = "onehalf";
        rev = "v2.0.0";
        sha256 = "1jx8k5kqxj7kml1v9ydm4yk6mzz5v3a61f2hgqmc145qf1qxyz1g";
      };
    };

    pigeon = vimUtils.buildVimPlugin {
      name = "pigeon.vim";
      src = sources.vim-pigeon;
    };

    AfterColors = vimUtils.buildVimPlugin {
      name = "AfterColors";
      src = pkgs.fetchFromGitHub {
        owner = "vim-scripts";
        repo = "AfterColors.vim";
        rev = "9936c26afbc35e6f92275e3f314a735b54ba1aaf";
        sha256 = "0j76g83zlxyikc41gn1gaj7pszr37m7xzl8i9wkfk6ylhcmjp2xi";
      };
    };

    vim-devicons = vimUtils.buildVimPlugin {
      name = "vim-devicons";
      src = sources.vim-devicons;
    };

    vim-nord = vimUtils.buildVimPlugin {
      name = "vim-nord";
      src = sources.vim-nord;
    };

    nvim-comment = vimUtils.buildVimPlugin {
      name = "nvim-comment";
      src = sources.nvim-comment;
      buildPhase = ":";
    };

    nvim-copilot-chat = vimUtils.buildVimPlugin {
         name = "nvim-copilot-chat";
         src = inputs.nvim-copilot-chat;
    };

    nvim-conform = vimUtils.buildVimPlugin {
          name = "nvim-conform";
          src = inputs.nvim-conform;
    };

    nvim-dressing = vimUtils.buildVimPlugin {
          name = "nvim-dressing";
          src = inputs.nvim-dressing;
    };

    nvim-gitsigns = vimUtils.buildVimPlugin {
          name = "nvim-gitsigns";
          src = inputs.nvim-gitsigns;
    };

    nvim-magma = vimUtils.buildVimPlugin {
      name = "nvim-magma";
      src = sources.nvim-magma;
    };

    nvim-lualine = vimUtils.buildVimPlugin {
           name = "nvim-lualine";
           src = inputs.nvim-lualine;
    };

    nvim-nui = vimUtils.buildVimPlugin {
          name = "nvim-nui";
          src = inputs.nvim-nui;
    };

    nvim-plenary = vimUtils.buildVimPlugin {
      name = "nvim-plenary";
      src = sources.nvim-plenary;
      buildPhase = ":";
    };

    nvim-rust = vimUtils.buildVimPlugin {
      name = "nvim-rust";
      src = sources.nvim-rust;
      buildPhase = ":";
    };

    nvim-snacks = vimUtils.buildVimPlugin {
          name = "nvim-snacks";
          src = inputs.nvim-snacks;
    };

    nvim-telescope = vimUtils.buildVimPlugin {
      name = "nvim-telescope";
      src = sources.nvim-telescope;
      buildPhase = ":";
    };

    nvim-treesitter-context = vimUtils.buildVimPlugin {
          name = "nvim-treesitter-context";
          src = inputs.nvim-treesitter-context;
    };

    nvim-lspconfig = vimUtils.buildVimPlugin {
      name = "nvim-lspconfig";
      src = sources.nvim-lspconfig;

      # We have to do this because the build phase runs tests which require
      # git and I don't know how to get git into here.
      buildPhase = ":";
    };

    nvim-treesitter-textobjects = vimUtils.buildVimPlugin {
      name = "nvim-treesitter-textobjects";
      src = sources.nvim-treesitter-textobjects;
    };
  };

  tree-sitter-hcl = self.callPackage
    (sources.nixpkgs + /pkgs/development/tools/parsing/tree-sitter/grammar.nix) { } {
    language = "hcl";
    version  = "0.1.0";
    source   = sources.tree-sitter-hcl;
  };
}
