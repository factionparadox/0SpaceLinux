# The look of the whole ship, in one Andalite palette: boot menu, boot splash,
# consoles, login prompt, terminal, GTK and Qt apps, icons, cursor, Firefox
# and the lock screen. The desktop itself (Dome, carousel, script,
# thought-speak) is in dome.nix and the shell.
let
  # Andalite palette.
  c = {
    void = "071226";    # deep night under the dome
    hull = "0b1630";    # window backgrounds
    panel = "13203a";   # raised surfaces
    line = "24365a";    # borders
    fur = "6aa2d8";     # Andalite blue: focus, selection, accents
    glass = "9fd4ff";   # the dome's glass: links, highlights
    tan = "d8c29a";     # fur tan: headings, the boot title
    text = "c8d3e6";
    pink = "d46fa0";    # the trees of home
    red = "b8434f";
    green = "4fb89a";
  };

  consoleColours = [
    c.void c.red c.green c.tan c.fur c.pink c.glass c.text
    "2a3a5a" "e06070" "6fd3b5" "f0dcb0" "8fbcf0" "f08ac0" "c6ebff" "ffffff"
  ];

  # adw-gtk3 (GTK 3) and libadwaita (GTK 4) both take their colours from these names.
  gtkCss = ''
    @define-color accent_color #${c.glass};
    @define-color accent_bg_color #${c.fur};
    @define-color accent_fg_color #${c.void};
    @define-color window_bg_color #${c.hull};
    @define-color window_fg_color #${c.text};
    @define-color view_bg_color #${c.void};
    @define-color view_fg_color #${c.text};
    @define-color headerbar_bg_color #${c.panel};
    @define-color headerbar_fg_color #${c.tan};
    @define-color headerbar_backdrop_color #${c.hull};
    @define-color sidebar_bg_color #${c.panel};
    @define-color sidebar_fg_color #${c.text};
    @define-color card_bg_color #${c.panel};
    @define-color card_fg_color #${c.text};
    @define-color popover_bg_color #${c.panel};
    @define-color popover_fg_color #${c.text};
    @define-color dialog_bg_color #${c.panel};
    @define-color dialog_fg_color #${c.text};
    @define-color borders #${c.line};
  '';
in
{
  flake.modules.nixos.theme = { config, lib, pkgs, ... }:
    let
      plymouthTheme = pkgs.runCommand "0space-plymouth" { } ''
        d=$out/share/plymouth/themes/0space
        mkdir -p $d
        cp ${../../art/boot.png} $d/boot.png
        cp ${../../art/light.png} $d/light.png
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

      gtkCssFile = pkgs.writeText "0space-gtk.css" gtkCss;

      # The Andalite script, as a font (built by tools/make-script-font.py).
      scriptFont = pkgs.runCommand "0space-script-font" { } ''
        install -Dm444 ${../../art/0space-script.ttf} $out/share/fonts/truetype/0space-script.ttf
      '';

      # kitty: Andalite by default, English on demand.
      #   Ctrl+Alt+A  letters in the Andalite script
      #   Ctrl+Alt+L  letters in English
      # Only letters change; numbers and symbols stay readable either way.
      kittyBase = pkgs.writeText "0space-kitty-base.conf" ''
        font_family Maple Mono NF
        font_size 11.5
        background_opacity 0.72
        dynamic_background_opacity yes
        window_padding_width 10
        cursor_shape beam
        cursor #${c.glass}
        foreground #${c.text}
        background #${c.void}
        selection_foreground #${c.void}
        selection_background #${c.fur}
        url_color #${c.glass}
        active_border_color #${c.fur}
        tab_bar_style powerline
        active_tab_foreground #${c.void}
        active_tab_background #${c.fur}
        inactive_tab_foreground #${c.text}
        inactive_tab_background #${c.panel}
        ${lib.concatImapStrings (i: col: "color${toString (i - 1)} #${col}\n") consoleColours}
        map ctrl+alt+a load_config_file /etc/xdg/kitty/kitty.conf
        map ctrl+alt+l load_config_file /etc/xdg/kitty/english.conf
      '';
      kittyConf = pkgs.writeText "kitty.conf" ''
        include ${kittyBase}
        symbol_map U+0041-U+005A,U+0061-U+007A 0-Space Script
      '';
      kittyEnglish = pkgs.writeText "kitty-english.conf" ''
        include ${kittyBase}
      '';
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
      console.colors = consoleColours;
      services.greetd.settings.default_session.command = lib.mkForce (lib.concatStringsSep " " [
        (lib.getExe pkgs.tuigreet)
        "--time --remember --asterisks"
        "--greeting '< Welcome back to the Dome, aristh >'"
        "--theme 'border=blue;text=gray;prompt=cyan;time=yellow;action=blue;button=cyan;container=black;input=white;greet=yellow'"
        "--cmd 0space-session"
      ]);

      # --- apps: GTK, Qt, icons, cursor, fonts ---------------------------------------------
      environment.systemPackages = with pkgs; [
        adw-gtk3
        papirus-icon-theme
        bibata-cursors
        adwaita-qt
        adwaita-qt6
      ];
      fonts.packages = [ pkgs.maple-mono.NF scriptFont ];
      fonts.fontconfig.defaultFonts = {
        sansSerif = [ "Noto Sans" ];
        monospace = [ "Maple Mono NF" ];
      };

      programs.dconf.profiles.user.databases = [{
        settings."org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          gtk-theme = "adw-gtk3-dark";
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
          gtk-theme-name=adw-gtk3-dark
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
        "0space/gtk.css".source = gtkCssFile;
        "xdg/kitty/kitty.conf".source = kittyConf;
        "xdg/kitty/english.conf".source = kittyEnglish;
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
