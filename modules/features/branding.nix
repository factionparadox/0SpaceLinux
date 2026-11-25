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

    themed = file: pkgs.writeText (baseNameOf file) (builtins.replaceStrings
      [ "@LOGO_PNG@" "@LOGO_TXT@" ]
      [ "${logo}/share/icons/hicolor/512x512/apps/0space.png" "${../../theme/fastfetch/logo.txt}" ]
      (builtins.readFile file));
    consoleConfig = themed ../../theme/fastfetch/console.jsonc;
    mirrorwaveConfig = themed ../../theme/fastfetch/mirrorwave.jsonc;

    fastfetch = pkgs.writeShellScriptBin "fastfetch" ''
      own="''${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch"
      if [ -e "$own/config.jsonc" ] || [ -e "$own/config.json" ]; then
        exec ${pkgs.fastfetch}/bin/fastfetch "$@"
      elif [ -n "''${MIRRORWAVE:-}" ] || [ "''${TERM:-}" = xterm-kitty ]; then
        # Too narrow for the logo beside the readout: leave it out.
        cols=$(${pkgs.ncurses}/bin/tput cols 2>/dev/null || echo 80)
        if [ "$cols" -lt 60 ]; then set -- --logo none "$@"; fi
        exec ${pkgs.fastfetch}/bin/fastfetch -c ${mirrorwaveConfig} "$@"
      else
        exec ${pkgs.fastfetch}/bin/fastfetch -c ${consoleConfig} "$@"
      fi
    '';
  in
  {
    environment.systemPackages = [ logo fastfetch ];
    system.nixos.extraOSReleaseArgs.LOGO = "0space";

    # fastfetch, themed: in Mirrorwave the logo is a picture and every label is
    # <script>/English; on a text console the logo is drawn in characters.
    # (theme/fastfetch is made by tools/make-fastfetch.py.) A config of your own
    # in ~/.config/fastfetch is used instead.
    environment.etc."xdg/fastfetch/config.jsonc".source = consoleConfig;

    console.colors = (import ../../lib/palette.nix).console;
    system.nixos.distroName = "0-Space Linux";
    system.nixos.variantName = "Dome ship";
    system.nixos.variant_id = "0space";
    services.getty.greetingLine = lib.mkForce "< 0-Space Linux. Dome integrity nominal. >";
  };
}
