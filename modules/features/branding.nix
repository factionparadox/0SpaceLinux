# What the ship calls itself, and the Andalite palette on its text consoles.
# The installer ISO uses this module too.
{
  flake.modules.nixos.branding = { lib, ... }: {
    console.colors = (import ../../lib/palette.nix).console;
    system.nixos.distroName = "0-Space Linux";
    system.nixos.variantName = "Dome ship";
    system.nixos.variant_id = "0space";
    services.getty.greetingLine = lib.mkForce "< 0-Space Linux. Dome integrity nominal. >";
  };
}
