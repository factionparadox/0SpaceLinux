# What the ship calls itself.
{
  flake.modules.nixos.branding = { lib, ... }: {
    system.nixos.distroName = "0-Space Linux";
    system.nixos.variantName = "Dome ship";
    system.nixos.variant_id = "0space";
    services.getty.greetingLine = lib.mkForce "< 0-Space Linux. Dome integrity nominal. >";
  };
}
