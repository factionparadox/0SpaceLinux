# Forms: the extra packages a ship has acquired. Each host keeps its list in
# hosts/<name>/forms.nix, which `escafil acquire` and `escafil shed` edit.
{
  flake.modules.nixos.forms = { config, lib, pkgs, ... }: {
    options.zerospace.forms = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "nixpkgs attribute names to install, such as \"vlc\" or \"python3Packages.requests\".";
    };

    config.environment.systemPackages =
      map (name: lib.getAttrFromPath (lib.splitString "." name) pkgs) config.zerospace.forms;
  };
}
