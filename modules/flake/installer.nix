# The installer ISO: boots straight into 0space-install. It carries the ship's
# whole design and every package the ship needs; only the parts made for the
# machine's own hardware are downloaded during installation.
{ inputs, config, lib, ... }:
let
  ship = config.flake.nixosConfigurations.dome-ship;
  design = lib.cleanSource ../..;
in
{
  flake.nixosConfigurations.installer = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
      config.flake.modules.nixos.branding
      ({ pkgs, lib, ... }:
        let
          install = pkgs.writeShellApplication {
            name = "0space-install";
            runtimeInputs = with pkgs; [ gum util-linux parted dosfstools e2fsprogs nixos-install-tools networkmanager systemd coreutils gnused curl ];
            text = builtins.readFile ../../installer/0space-install;
          };
        in
        {
          nixpkgs.hostPlatform = "x86_64-linux";
          boot.kernelPackages = pkgs.linuxPackages_latest;
          boot.supportedFilesystems.zfs = lib.mkForce false;   # 0-Space does not use ZFS, and it lags new kernels
          hardware.enableRedistributableFirmware = true;
          networking.networkmanager.enable = true;
          # Not networking.wireless: NetworkManager switches it on itself to
          # run wpa_supplicant, which it needs to drive the Wi-Fi card.
          nix.settings.experimental-features = [ "nix-command" "flakes" ];

          image.baseName = lib.mkForce "0space-linux";
          isoImage.volumeID = "0SPACE";
          isoImage.storeContents = [
            ship.config.system.build.toplevel
            inputs.nixpkgs.outPath
            inputs.flake-parts.outPath
            inputs.import-tree.outPath
            inputs.nixos-hardware.outPath
          ];

          environment.etc."0space-flake".source = design;
          environment.systemPackages = [ install pkgs.git ];

          # The first console runs the installer as soon as it logs in.
          services.getty.autologinUser = lib.mkForce "root";
          programs.bash.loginShellInit = ''
            if [ "$(tty)" = /dev/tty1 ]; then 0space-install; fi
          '';
        })
    ];
  };

  perSystem = { system, ... }: {
    packages.iso = config.flake.nixosConfigurations.installer.config.system.build.isoImage;
  };
}
