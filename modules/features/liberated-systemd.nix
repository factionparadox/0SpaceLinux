# systemd, liberated: the birthDate field (the first step towards age
# verification) removed from user records.
#
# Patching systemd the usual way would change the hash of everything built
# against it and rebuild half the system. Instead, the finished system is
# downloaded from the cache as normal, and replaceDependencies swaps the
# patched systemd in afterwards. Only systemd itself is compiled, once per
# systemd version. The patch only removes code, so the swap is safe.
{
  flake.modules.nixos.liberated-systemd = { config, ... }:
    let
      # The systemd NixOS actually runs, which is its own variant of the
      # package, not plain pkgs.systemd.
      stock = config.systemd.package;
      liberated = stock.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ../../patches/0space-no-birthdate.patch ];
      });
    in
    {
      # The initrd is a compressed archive replaceDependencies can't rewrite,
      # and its systemd is PID 1 until switch-root, so it gets the liberated
      # build directly. Nothing else is rebuilt for this.
      boot.initrd.systemd.package = liberated;

      system.replaceDependencies.replacements = [
        { oldDependency = stock; newDependency = liberated; }
      ];
    };
}
