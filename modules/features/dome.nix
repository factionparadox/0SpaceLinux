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

      # Picks each screen's scale from its pixel density at login.
      scaler = pkgs.writeShellApplication {
        name = "0space-scale";
        runtimeInputs = [ pkgs.wlr-randr pkgs.jq pkgs.coreutils ];
        text = builtins.readFile ../../session/0space-scale;
      };

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
            ${pkgs.imagemagick}/bin/magick "$user_dome" -resize 25% -blur 0x9 "$user_glass" || true
          fi
          [ -f "$user_glass" ] && export ZEROSPACE_GLASS="$user_glass"
        fi

        # GTK: the 0Space theme is system-wide for GTK 3. GTK 4 (libadwaita)
        # only reads ~/.config/gtk-4.0/gtk.css, so that's linked to the system
        # copy and follows updates. A gtk.css of your own is left alone; the
        # one-off copies older 0-Space versions made are cleared away.
        for v in gtk-3.0 gtk-4.0; do
          f="$HOME/.config/$v/gtk.css"
          if [ -f "$f" ] && [ ! -L "$f" ] && head -n1 "$f" | grep -q '^@define-color accent_color #9fd4ff;$'; then
            rm -f "$f"
          fi
        done
        if [ ! -e "$HOME/.config/gtk-4.0/gtk.css" ] || [ -L "$HOME/.config/gtk-4.0/gtk.css" ]; then
          mkdir -p "$HOME/.config/gtk-4.0"
          ln -sfn /etc/0space/gtk4.css "$HOME/.config/gtk-4.0/gtk.css"
        fi

        config="$HOME/.config/wayfire.ini"
        [ -f "$config" ] || config=${wayfireIni}
        exec wayfire -c "$config"
      '';
    in
    {
      # Electron apps (Discord) draw natively on Wayland, so they're sharp
      # when scaled.
      environment.sessionVariables.NIXOS_OZONE_WL = "1";

      environment.systemPackages = with pkgs; [
        scaler
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
