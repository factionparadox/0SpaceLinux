# Mirrorwave: the ship's terminal, named for the Andalite mass call.
#
# kitty is the engine underneath; Mirrorwave is everything on top: its own
# name and window identity, the Andalite look, and tab titles written
# Andalite/English.
#
#   Ctrl+Alt+A   full Andalite: all letters in the script
#   Ctrl+Alt+L   back to English with the script as an accent
#
# Commands that take more than ten seconds report back in thought-speak if
# you've looked away. Your own settings go in ~/.config/mirrorwave/mirrorwave.conf.
let
  palette = import ../../lib/palette.nix;
  inherit (palette) c;
in
{
  flake.modules.nixos.mirrorwave = { lib, pkgs, ... }:
    let
      settings = pkgs.writeText "mirrorwave.conf" ''
        # Mirrorwave (kitty underneath)
        font_family Maple Mono NF
        font_size 11.5
        # The script's letters live at U+100000 + the letter, so only text
        # written as a translation is drawn in it.
        symbol_map U+100041-U+10007A 0-Space Script

        background_opacity 0.72
        dynamic_background_opacity yes
        window_padding_width 10
        confirm_os_window_close 0
        cursor_shape beam
        cursor #${c.glass}
        foreground #${c.text}
        background #${c.void}
        selection_foreground #${c.void}
        selection_background #${c.fur}
        url_color #${c.glass}
        active_border_color #${c.fur}
        inactive_border_color #${c.line}
        ${lib.concatImapStrings (i: col: "color${toString (i - 1)} #${col}\n") palette.console}

        # Tab titles, translated (tab_bar.py).
        tab_bar_edge top
        tab_bar_style custom
        tab_bar_min_tabs 1
        tab_powerline_style slanted
        tab_bar_background #${c.void}
        active_tab_foreground #${c.void}
        active_tab_background #${c.fur}
        active_tab_font_style bold
        inactive_tab_foreground #${c.tan}
        inactive_tab_background #${c.panel}

        # Thought-speak when a long command finishes while you're elsewhere.
        shell_integration enabled
        notify_on_cmd_finish unfocused 10.0

        map ctrl+alt+a load_config_file @dir@/full-andalite.conf
        map ctrl+alt+l load_config_file @dir@/kitty.conf

        # Yours, last so it wins. Ignored if it doesn't exist.
        include ''${HOME}/.config/mirrorwave/mirrorwave.conf
      '';

      fullAndalite = pkgs.writeText "full-andalite.conf" ''
        include @dir@/kitty.conf
        symbol_map U+0041-U+005A,U+0061-U+007A,U+100041-U+10007A 0-Space Script
      '';

      configDir = pkgs.runCommand "mirrorwave-config" { } ''
        mkdir -p $out
        substitute ${settings} $out/kitty.conf --subst-var-by dir $out
        substitute ${fullAndalite} $out/full-andalite.conf --subst-var-by dir $out
        cp ${../../mirrorwave/tab_bar.py} $out/tab_bar.py
      '';

      desktopItem = pkgs.makeDesktopItem {
        name = "mirrorwave";
        desktopName = "Mirrorwave";
        genericName = "Terminal";
        comment = "The ship's terminal";
        exec = "mirrorwave";
        icon = "utilities-terminal";
        categories = [ "System" "TerminalEmulator" ];
      };

      mirrorwave = pkgs.symlinkJoin {
        name = "mirrorwave";
        paths = [
          (pkgs.writeShellScriptBin "mirrorwave" ''
            export MIRRORWAVE=1
            export KITTY_CONFIG_DIRECTORY=${configDir}
            exec ${lib.getExe pkgs.kitty} --class mirrorwave "$@"
          '')
          desktopItem
        ];
      };
    in
    {
      environment.systemPackages = [ mirrorwave ];
      fonts.packages = [ (import ../../lib/script-font.nix pkgs) ];
      xdg.terminal-exec = {
        enable = true;
        settings.default = [ "mirrorwave.desktop" ];
      };
    };
}
