# The carousel: our Wayfire plugin. Windows stand on a ring that runs back
# into the screen, and spinning it brings the next one round to the front.
let
  carousel = pkgs: pkgs.stdenv.mkDerivation {
    pname = "zerospace-ring";
    version = "0.4.0";
    src = ../../ring;

    nativeBuildInputs = with pkgs; [ meson ninja pkg-config ];
    buildInputs = with pkgs; [ wayfire wf-config wlroots_0_19 glm libdrm pixman libxkbcommon libevdev libGL nlohmann_json ];

    # Install into this package, not into Wayfire's own (read-only) folders;
    # programs.wayfire.plugins points Wayfire here.
    env = {
      PKG_CONFIG_WAYFIRE_PLUGINDIR = "${placeholder "out"}/lib/wayfire";
      PKG_CONFIG_WAYFIRE_METADATADIR = "${placeholder "out"}/share/wayfire/metadata";
    };
  };
in
{
  perSystem = { pkgs, ... }: {
    packages.zerospace-ring = carousel pkgs;
  };

  flake.modules.nixos.carousel = { pkgs, ... }: {
    programs.wayfire = {
      enable = true;
      plugins = [ (carousel pkgs) ];
    };
  };
}
