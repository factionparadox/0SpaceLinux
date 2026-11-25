# The look of the whole ship, in one Andalite palette: boot menu, boot splash,
# consoles, login prompt, terminal, GTK and Qt apps, icons, cursor, Firefox
# and the lock screen. The desktop itself (Dome, carousel, script,
# thought-speak) is in dome.nix and the shell.
let
  palette = import ../../lib/palette.nix;
  inherit (palette) c;
  consoleColours = palette.console;

in
{
  flake.modules.nixos.theme = { config, lib, pkgs, ... }:
    let
      plymouthTheme = pkgs.runCommand "0space-plymouth" { } ''
        d=$out/share/plymouth/themes/0space
        mkdir -p $d
        cp ${../../art/boot.png} $d/boot.png
        cp ${../../art/light.png} $d/light.png
        cp ${../../art/logo-512.png} $d/logo.png
        cp ${../../theme/plymouth/0space.script} $d/0space.script
        cat > $d/0space.plymouth <<EOF
        [Plymouth Theme]
        Name=0-Space
        Description=The Dome ship waking
        ModuleName=script

        [script]
        ImageDir=$d
        ScriptFile=$d/0space.script
        EOF
      '';

      # The 0Space GTK theme: adw-gtk3's dark theme underneath, the Andalite
      # palette and glass on top (theme/gtk). Installed system-wide, so it
      # changes with the system.
      gtkTheme = pkgs.runCommand "0space-gtk-theme" { } ''
        t=$out/share/themes/0Space
        mkdir -p $t/gtk-3.0
        sed 's/adw-gtk3-dark/0Space/' ${pkgs.adw-gtk3}/share/themes/adw-gtk3-dark/index.theme > $t/index.theme
        {
          echo '@import url("file://${pkgs.adw-gtk3}/share/themes/adw-gtk3-dark/gtk-3.0/gtk.css");'
          cat ${../../theme/gtk/colours.css} ${../../theme/gtk/widgets.css}
        } > $t/gtk-3.0/gtk.css
        ln -s ${pkgs.adw-gtk3}/share/themes/adw-gtk3-dark/gtk-3.0/assets $t/gtk-3.0/assets
      '';

      # GTK 4 (libadwaita) apps ignore themes and read ~/.config/gtk-4.0/gtk.css;
      # the session links that to this.
      gtk4Css = pkgs.concatText "0space-gtk4.css" [ ../../theme/gtk/colours.css ../../theme/gtk/widgets.css ];


    in
    {
      # --- boot menu: Limine, over the Dome ------------------------------------------------
      boot.loader.systemd-boot.enable = lib.mkForce false;
      boot.loader.limine = {
        enable = true;
        efiSupport = true;
        maxGenerations = 12;
        style = {
          wallpapers = [ ../../art/boot.png ];
          wallpaperStyle = "stretched";
          interface.branding = "0-Space Linux";
          interface.brandingColor = c.tan;
          graphicalTerminal = {
            foreground = c.text;
            background = "40${c.void}";
            palette = lib.concatStringsSep ";" (lib.take 8 consoleColours);
            brightPalette = lib.concatStringsSep ";" (lib.drop 8 consoleColours);
            margin = 64;
          };
        };
      };

      # --- boot splash ---------------------------------------------------------------------------
      boot.plymouth = {
        enable = true;
        theme = "0space";
        themePackages = [ plymouthTheme ];
      };
      boot.consoleLogLevel = 3;
      boot.kernelParams = [ "quiet" "splash" "rd.udev.log_level=3" "udev.log_priority=3" ];

      # --- consoles and the login prompt -----------------------------------------------------
      # (the console palette itself is in branding.nix, shared with the installer)
      services.greetd.settings.default_session.command = lib.mkForce (lib.concatStringsSep " " [
        (lib.getExe pkgs.tuigreet)
        "--time --remember --asterisks"
        "--greeting '< Welcome back to the Dome, aristh >'"
        "--theme 'border=blue;text=gray;prompt=cyan;time=yellow;action=blue;button=cyan;container=black;input=white;greet=yellow'"
        "--cmd 0space-session"
      ]);

      # --- apps: GTK, Qt, icons, cursor, fonts ---------------------------------------------
      environment.systemPackages = with pkgs; [
        gtkTheme
        adw-gtk3
        papirus-icon-theme
        bibata-cursors
        adwaita-qt
        adwaita-qt6
      ];
      fonts.packages = [ pkgs.maple-mono.NF (import ../../lib/script-font.nix pkgs) ];
      fonts.fontconfig.defaultFonts = {
        sansSerif = [ "Noto Sans" ];
        monospace = [ "Maple Mono NF" ];
      };

      programs.dconf.profiles.user.databases = [{
        settings."org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          gtk-theme = "0Space";
          icon-theme = "Papirus-Dark";
          cursor-theme = "Bibata-Modern-Ice";
          cursor-size = lib.gvariant.mkInt32 24;
          font-name = "Noto Sans 11";
          monospace-font-name = "Maple Mono NF 11";
          accent-color = "blue";
        };
      }];

      environment.etc = {
        "xdg/gtk-3.0/settings.ini".text = ''
          [Settings]
          gtk-theme-name=0Space
          gtk-icon-theme-name=Papirus-Dark
          gtk-cursor-theme-name=Bibata-Modern-Ice
          gtk-cursor-theme-size=24
          gtk-font-name=Noto Sans 11
          gtk-application-prefer-dark-theme=1
        '';
        "xdg/gtk-4.0/settings.ini".text = ''
          [Settings]
          gtk-icon-theme-name=Papirus-Dark
          gtk-cursor-theme-name=Bibata-Modern-Ice
          gtk-cursor-theme-size=24
          gtk-font-name=Noto Sans 11
          gtk-application-prefer-dark-theme=1
        '';
        "0space/gtk4.css".source = gtk4Css;
        "swaylock/config".text = ''
          image=${../../art/dome.png}
          scaling=fill
          indicator-idle-visible
          indicator-radius=110
          indicator-thickness=8
          inside-color=${c.void}cc
          ring-color=${c.fur}ff
          key-hl-color=${c.glass}ff
          bs-hl-color=${c.pink}ff
          inside-ver-color=${c.hull}cc
          ring-ver-color=${c.tan}ff
          inside-wrong-color=${c.void}cc
          ring-wrong-color=${c.red}ff
          line-color=00000000
          separator-color=00000000
          text-color=${c.tan}ff
          text-ver-color=${c.tan}ff
          text-wrong-color=${c.red}ff
          font=Noto Sans
        '';
      };

      qt = {
        enable = true;
        platformTheme = "gnome";
        style = "adwaita-dark";
      };

      environment.sessionVariables = {
        XCURSOR_THEME = "Bibata-Modern-Ice";
        XCURSOR_SIZE = "24";
      };

      # --- Firefox: dark, and quiet about telemetry ---------------------------------------
      programs.firefox = {
        enable = true;
        preferences = {
          "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
          "ui.systemUsesDarkTheme" = 1;
          "browser.aboutwelcome.enabled" = false;
          "datareporting.policy.dataSubmissionPolicyBypassNotification" = true;
        };
        policies = {
          DisableTelemetry = true;
          DisableFirefoxStudies = true;
        };
      };
    };
}
