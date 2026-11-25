# What the ship calls itself, and the Andalite palette on its text consoles.
# The installer ISO uses this module too.
{
  flake.modules.nixos.branding = { lib, pkgs, ... }:
  let
    # The logo (art/logo.svg, drawn by tools/render-logo.py), installed as an
    # icon so anything that asks os-release for the logo finds it.
    logo = pkgs.runCommand "0space-logo" { } ''
      install -Dm444 ${../../art/logo.svg} $out/share/icons/hicolor/scalable/apps/0space.svg
      for s in 64 128 256 512; do
        install -Dm444 ${../../art}/logo-$s.png $out/share/icons/hicolor/''${s}x''${s}/apps/0space.png
      done
      install -Dm444 ${../../art/logo-256.png} $out/share/pixmaps/0space.png
    '';
  in
  {
    environment.systemPackages = [ logo ];
    system.nixos.extraOSReleaseArgs.LOGO = "0space";

    # fastfetch shows our logo: as a picture in Mirrorwave, as characters on a
    # text console.
    environment.etc."xdg/fastfetch/config.jsonc".text = builtins.toJSON {
      logo = {
        type = "auto";
        source = "${logo}/share/icons/hicolor/512x512/apps/0space.png";
        width = 30;
        padding = { left = 2; right = 3; };
      };
      display.color = { keys = "blue"; title = "yellow"; };
    };

    console.colors = (import ../../lib/palette.nix).console;
    system.nixos.distroName = "0-Space Linux";
    system.nixos.variantName = "Dome ship";
    system.nixos.variant_id = "0space";
    services.getty.greetingLine = lib.mkForce "< 0-Space Linux. Dome integrity nominal. >";
  };
}
