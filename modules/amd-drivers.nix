{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [    ];

    # Make the kernel use the correct driver early
    boot.initrd.kernelModules = [ "amdgpu" ];

    # Load AMD driver for Xorg and Wayland
    services.xserver.videoDrivers = ["amdgpu"];
}