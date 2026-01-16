# This function creates a NixOS system based on our VM setup for a
# particular architecture.
{ nixpkgs, overlays, inputs }:

name:
{
  system,
  user,
  darwin ? false,
  wsl ? false,
  raphael ? false,
  pstate ? false,
  zenpower ? false,
  server ? false
}:

let
  # True if this is a WSL system.
  isWSL = wsl;

  # True if Linux, which is a heuristic for not being Darwin.
  isLinux = !darwin && !isWSL;

  # True if this is a Raphael iGPU system
  isRaphael = raphael;
  isPstate = pstate;
  isZenpower = zenpower;

  # The config files for this system.
  machineConfig = ../hosts/${name}.nix;
  userOSConfig = ../users/${user}/${if darwin then "darwin" else "nixos" }.nix;
  userHMConfig = ../users/${user}/${if server then "home-manager-server" else "home-manager"}.nix;

  # NixOS vs nix-darwin functionst
  systemFunc = if darwin then inputs.darwin.lib.darwinSystem else nixpkgs.lib.nixosSystem;
  home-manager = if darwin then inputs.home-manager.darwinModules else inputs.home-manager.nixosModules;
in systemFunc rec {
  inherit system;

  modules = [
    # Apply our overlays. Overlays are keyed by system type so we have
    # to go through and apply our system type. We do this first so
    # the overlays are available globally.
    { nixpkgs.overlays = overlays; }

    # Allow unfree packages - JL: Allow globally so that CI build works
    { nixpkgs.config.allowUnfree = true; }

    # Bring in WSL if this is a WSL build
    (if isWSL then inputs.nixos-wsl.nixosModules.wsl else {})

    # Bring in AMD Raphael iGPI if this is a Raphael build
    (if isRaphael then inputs.nixos-hardware.nixosModules.common-cpu-amd-raphael-igpu else {})
    # pstate for modern AMD CPUs
    (if isPstate then inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate else {})
    (if isZenpower then inputs.nixos-hardware.nixosModules.common-cpu-amd-zenpower else {})

    # Snapd on Linux
    (if isLinux then inputs.nix-snapd.nixosModules.default else {})

    machineConfig
    userOSConfig
    home-manager.home-manager {
      home-manager.backupFileExtension = "backup";
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.${user} = import userHMConfig {
        isWSL = isWSL;
        inputs = inputs;
      };
    }

    # We expose some extra arguments so that our modules can parameterize
    # better based on these values.
    {
      config._module.args = {
        currentSystem = system;
        currentSystemName = name;
        currentSystemUser = user;
        isWSL = isWSL;
        inputs = inputs;
      };
    }
  ];
}
