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

      # Lean running: compressed swap in RAM, no waiting for the network at
      # boot, no NixOS manual built into every generation, and old generations
      # cleared out weekly so the store doesn't creep.
      zramSwap = { enable = true; algorithm = "zstd"; memoryPercent = 50; };
      boot.kernel.sysctl = {
        "vm.swappiness" = 180;            # zram is cheap: swap to it before dropping cache
        "vm.page-cluster" = 0;
        "vm.watermark_boost_factor" = 0;
        "vm.watermark_scale_factor" = 125;
      };
      systemd.services.NetworkManager-wait-online.enable = false;
      documentation.nixos.enable = false;
      documentation.doc.enable = false;
      services.journald.settings.Journal = { SystemMaxUse = "200M"; RuntimeMaxUse = "48M"; };
      services.fstrim.enable = true;
      services.thermald.enable = lib.mkDefault true;
      services.speechd.enable = lib.mkForce false;   # screen-reader speech, pulled in by default
      boot.initrd.compressor = "zstd";
      nix.gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 14d"; };

      # The everyday kit every ship carries.
      programs.git.enable = true;
      environment.systemPackages = with pkgs; [
        git wget curl fastfetch btop jq tree file
        unzip zip p7zip
        pciutils usbutils lsof
        pavucontrol networkmanagerapplet
      ];

      # Bluetooth, removable drives, saved passwords (Proton VPN and Discord keep
      # theirs in the keyring), and a prompt when an app needs admin rights.
      hardware.bluetooth = { enable = true; powerOnBoot = false; };
      services.blueman.enable = true;
      services.udisks2.enable = true;
      services.gnome.gnome-keyring.enable = true;
      security.pam.services.greetd.enableGnomeKeyring = true;
      security.polkit.enable = true;

      # No Flatpak on 0-Space: everything comes from nixpkgs.
      services.flatpak.enable = false;

      system.stateVersion = lib.mkDefault "26.05";
    };
  };
}
