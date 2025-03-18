{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [    ];

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = ["nvidia"];


# Enable Graphics
  hardware.graphics = {
    enable = true;
  };

  # Wayland and NVidia do not combine well. (example: Electron apps like VS code / codium wont work)
  services.xserver.displayManager.gdm.wayland = true;

   systemd.services.nvidia-control-devices = {
     wantedBy = [ "multi-user.target" ];
     serviceConfig.ExecStart = "${pkgs.linuxPackages.nvidia_x11.bin}/bin/nvidia-smi";
   };

  hardware.nvidia = {

    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = false;
    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    # On the other hand;
    # Hyprland recommends using the open core driver if your GPU is supported.
    # Sway doesn't work at all with the closed source driver.
    open = false;

    # Enable the Nvidia settings menu,
	# accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
}
