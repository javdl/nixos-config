{ config, lib, ... }:

{
  # Allow unfree packages globally
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = _: true;
}
