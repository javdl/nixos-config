{ isOmarchy, currentSystemName }:
{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [ ../companion-omarchy.nix ];

  # Companion's packaged startup entries for fu137 remain in that module;
  # j9 uses its existing native installations below.
  config = lib.mkIf isOmarchy {
    programs.companionOmarchy.enable = currentSystemName == "fu137";
    xdg.configFile = {
      "hypr/autostart.lua" =
        lib.mkIf
          (builtins.elem currentSystemName [
            "fu137"
            "j9"
          ])
          {
            force = true;
            text = ''
              -- Managed by Nix: users/joost/omarchy-startup.nix.
              -- Startup placement only: later windows open on the current workspace.
              hl.on("hyprland.start", function()
                hl.exec_cmd("/usr/bin/ghostty --gtk-single-instance=false -e ${pkgs.herdr}/bin/herdr --remote bali", { workspace = "1 silent" })
                hl.exec_cmd("/usr/bin/chatgpt", { workspace = "2 silent" })
                hl.exec_cmd("/usr/bin/zeditor --new", { workspace = "3 silent" })
                hl.exec_cmd("/usr/bin/brave-origin", { workspace = "4 silent" })
                hl.exec_cmd("/usr/bin/slack --gtk-version=3", { workspace = "5 silent" })
              end)
            '';
          };

      "autostart/companion.desktop" = lib.mkIf (currentSystemName == "j9") {
        force = true;
        text = ''
          [Desktop Entry]
          Type=Application
          Name=Companion
          TryExec=${config.home.homeDirectory}/.local/share/companion/companion-launcher
          Exec=${config.home.homeDirectory}/.local/share/companion/companion-launcher --gtk-version=3
          Icon=companion
          Terminal=false
        '';
      };
      "autostart/vicreo-listener.desktop" = lib.mkIf (currentSystemName == "j9") {
        force = true;
        text = ''
          [Desktop Entry]
          Type=Application
          Name=VICREO Listener
          TryExec=${config.home.homeDirectory}/.local/bin/vicreo-listener
          Exec=${config.home.homeDirectory}/.local/bin/vicreo-listener --gtk-version=3
          Icon=vicreo-listener
          Terminal=false
        '';
      };
      "autostart/jetbrains-toolbox.desktop" = lib.mkIf (currentSystemName == "j9") {
        force = true;
        text = ''
          [Desktop Entry]
          Type=Application
          Name=JetBrains Toolbox
          TryExec=/opt/jetbrains-toolbox/jetbrains-toolbox
          Exec=/opt/jetbrains-toolbox/jetbrains-toolbox --minimize
          Icon=jetbrains-toolbox
          Terminal=false
          StartupNotify=false
        '';
      };

      # Quattro owns notifications, the launcher and clipboard history.
      "autostart/walker.desktop" = {
        force = true;
        text = ''
          [Desktop Entry]
          Type=Application
          Name=Walker (disabled; Omarchy shell owns the launcher)
          Hidden=true
        '';
      };
      # Disabling Mako alone does not prevent D-Bus activation.
      "systemd/user/mako.service" = {
        force = true;
        source = config.lib.file.mkOutOfStoreSymlink "/dev/null";
      };
      "systemd/user/elephant.service" = {
        force = true;
        source = config.lib.file.mkOutOfStoreSymlink "/dev/null";
      };
    };
  };
}
