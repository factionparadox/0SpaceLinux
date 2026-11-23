# Every folder in hosts/ becomes a machine. Each one gets all of the 0-Space
# features (everything under flake.modules.nixos) plus its own folder, which
# holds what only that machine knows: its hardware, its aristh, its forms.
# The installer adds a folder here for the machine it installs to.
{ inputs, config, lib, ... }:
let
  features = builtins.attrValues config.flake.modules.nixos;
  hosts = lib.filterAttrs (_: type: type == "directory") (builtins.readDir ../../hosts);
in
{
  flake.nixosConfigurations = lib.mapAttrs (name: _:
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = features ++ [
        ../../hosts/${name}
        { networking.hostName = lib.mkDefault name; }
      ];
    }) hosts;
}
