# Stand-in hardware for the reference build. On a real install this file is
# written by nixos-generate-config for that machine.
{
  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "thunderbolt" "usb_storage" "sd_mod" ];
  fileSystems."/" = { device = "/dev/disk/by-label/0space"; fsType = "ext4"; };
  fileSystems."/boot" = { device = "/dev/disk/by-label/0SPACE-EFI"; fsType = "vfat"; options = [ "umask=0077" ]; };
}
