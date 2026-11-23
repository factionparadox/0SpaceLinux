# The ship's frame: who sails it, how it boots, what it runs on.
{
  flake.modules.nixos.base = { config, lib, pkgs, ... }: {
    options.zerospace.user = lib.mkOption {
      type = lib.types.str;
      description = "The aristh: the one user this Dome ship is set up for.";
    };

    config = {
      nix.settings = {
        experimental-features = [ "nix-command" "flakes" ];
        trusted-users = [ "root" "@wheel" ];
        auto-optimise-store = true;
      };
      nixpkgs.config.allowUnfree = true;
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

      boot.loader.efi.canTouchEfiVariables = true;   # the boot menu itself (Limine) is in theme.nix
      boot.kernelPackages = pkgs.linuxPackages_latest;   # new enough for the Core Ultra 5 325H

      hardware.enableRedistributableFirmware = true;
      hardware.graphics.enable = true;
      services.fwupd.enable = true;
      services.power-profiles-daemon.enable = true;
      services.upower.enable = true;

      networking.networkmanager.enable = true;
      time.timeZone = lib.mkDefault "Europe/London";
      i18n.defaultLocale = lib.mkDefault "en_GB.UTF-8";
      console.keyMap = lib.mkDefault "uk";

      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        pulse.enable = true;
      };

      users.users.${config.zerospace.user} = {
        isNormalUser = true;
        extraGroups = [ "wheel" "networkmanager" "video" ];
      };

      # No Flatpak on 0-Space: everything comes from nixpkgs.
      services.flatpak.enable = false;

      system.stateVersion = lib.mkDefault "26.05";
    };
  };
}
