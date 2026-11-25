# escafil: the operator. One short command for every job, so NixOS's own
# commands never need typing.
{
  flake.modules.nixos.escafil = { pkgs, ... }:
    let
      escafil = pkgs.stdenvNoCC.mkDerivation {
        pname = "escafil";
        version = "0.3.0";
        src = ../../escafil;
        nativeBuildInputs = [ pkgs.makeWrapper ];
        installPhase = ''
          install -Dm755 escafil $out/bin/escafil
          wrapProgram $out/bin/escafil \
            --set-default ZEROSPACE_FLAKE /etc/0space \
            --prefix PATH : ${pkgs.lib.makeBinPath (with pkgs; [ coreutils gnugrep gnused gawk gnutar git nix nixos-rebuild-ng hostname procps ])}
        '';
      };
    in
    {
      environment.systemPackages = [ escafil ];
    };
}
