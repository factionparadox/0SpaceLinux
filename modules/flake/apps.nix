# `nix run github:factionparadox/0SpaceLinux`: bring an installed ship up to
# the newest 0-Space straight from GitHub, with no clone and no git needed.
{ self, ... }:
{
  perSystem = { pkgs, ... }: {
    apps.default = {
      type = "app";
      program = "${pkgs.writeShellScript "0space-jump" ''
        # /run/wrappers/bin first: the system's sudo is the setuid one.
        export PATH=/run/wrappers/bin:${pkgs.lib.makeBinPath (with pkgs; [ bash coreutils gnutar hostname nixos-rebuild-ng ])}:$PATH
        exec bash ${self}/tools/sync
      ''}";
      meta.description = "Update this 0-Space ship to the newest design, keeping its own hosts/ folder";
    };
  };
}
