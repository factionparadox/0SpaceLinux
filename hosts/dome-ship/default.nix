# A reference Dome ship, used to build and test 0-Space. The installer makes
# a folder like this one for each machine it installs to.
# It is a Framework Laptop 13 Pro (Intel Core Ultra series 3).
{ inputs, ... }:
{
  imports = [
    ./hardware.nix
    inputs.nixos-hardware.nixosModules.framework-intel-core-ultra-series3
  ];
  zerospace.user = "aristh";
  zerospace.forms = import ./forms.nix;
  system.stateVersion = "26.05";
}
