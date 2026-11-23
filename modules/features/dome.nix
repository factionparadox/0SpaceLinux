# The Dome: the session itself. Wayfire with the carousel, the Quickshell
# shell (Dome, ring floor, script, thought-speak), and greetd logging the
# aristh straight in.
{
  flake.modules.nixos.dome = { config, lib, pkgs, ... }:
    let
      art = ../../art;
      shell = ../../shell;

      wayfireIni = pkgs.writeText "0space-wayfire.ini"
        (builtins.replaceStrings
          [ "quickshell -p /usr/share/0space/shell/shell.qml" ]
          [ "quickshell -p ${shell}/shell.qml" ]
          (builtins.readFile ../../shell/wayfire.ini));

      session = pkgs.writeShellScriptBin "0space-session" ''
        export XDG_CURRENT_DESKTOP=0space:wlroots
        export XDG_SESSION_DESKTOP=0space
        export XDG_SESSION_TYPE=wayland
        export MOZ_ENABLE_WAYLAND=1
        export QT_QPA_PLATFORM=wayland
        export QS_ICON_THEME=Papirus-Dark
        export ZEROSPACE_DOME=${art}/dome.png
        export ZEROSPACE_ART=${art}
        export ZEROSPACE_GLASS=${art}/dome-glass.png

        # A Dome of your own gets frosted for the shell's glass pills (once,
        # and again whenever you change it).
        user_dome="$HOME/.local/share/0space/art/dome.png"
        user_glass="$HOME/.cache/0space/dome-glass.png"
        if [ -f "$user_dome" ]; then
          if [ ! -f "$user_glass" ] || [ "$user_dome" -nt "$user_glass" ]; then
            mkdir -p "''${user_glass%/*}"
            ${pkgs.imagemagick}/bin/magick "$user_dome" -resize 50% -blur 0x18 "$user_glass" || true
          fi
          [ -f "$user_glass" ] && export ZEROSPACE_GLASS="$user_glass"
        fi

        # First login: give GTK apps the Andalite colours (yours to change after).
        for v in gtk-3.0 gtk-4.0; do
          if [ ! -e "$HOME/.config/$v/gtk.css" ]; then
            mkdir -p "$HOME/.config/$v"
            cp /etc/0space/gtk.css "$HOME/.config/$v/gtk.css"
            chmod u+w "$HOME/.config/$v/gtk.css"
          fi
        done

        config="$HOME/.config/wayfire.ini"
        [ -f "$config" ] || config=${wayfireIni}
        exec wayfire -c "$config"
      '';
    in
    {
      environment.systemPackages = with pkgs; [
        session
        quickshell
        # (the terminal is Mirrorwave, in mirrorwave.nix)
        swaylock
        swayidle
        grim
        slurp
        wl-clipboard
        libnotify
      ];

      environment.etc."0space/wayfire.ini".source = wayfireIni;

      services.greetd = {
        enable = true;
        settings = {
          # Straight to the desktop after boot; a plain prompt if you log out.
          initial_session = {
            command = "0space-session";
            user = config.zerospace.user;
          };
          default_session = {
            command = "${lib.getExe' pkgs.greetd "agreety"} --cmd 0space-session";
            user = "greeter";
          };
        };
      };

      security.pam.services.swaylock = { };

      xdg.portal = {
        enable = true;
        wlr.enable = true;
        config.common.default = "wlr";
      };

      fonts.packages = with pkgs; [ noto-fonts noto-fonts-color-emoji ];
    };
}
