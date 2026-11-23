# The flake's frame: which systems it builds for, and the flake.modules
# option every feature file below contributes its NixOS module to.
{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];
  systems = [ "x86_64-linux" ];
}
