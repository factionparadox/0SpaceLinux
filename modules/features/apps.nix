# The ship's standard apps, each on a key (shell/wayfire.ini has the keys),
# and the two small commands the keys use to talk to the shell.
#
#   0space-call TARGET FUNCTION [ARGS]   call the running shell, e.g.
#                                        0space-call launcher toggle
#   0space-level up|down|mute|mic|brighter|dimmer
#                                        change a level and show its gauge
{
  flake.modules.nixos.apps = { lib, pkgs, ... }:
    let
      shell = ../../shell;

      call = pkgs.writeShellScriptBin "0space-call" ''
        exec ${lib.getExe pkgs.quickshell} ipc -p ${shell}/shell.qml call "$@"
      '';

      level = pkgs.writeShellApplication {
        name = "0space-level";
        runtimeInputs = [ pkgs.wireplumber pkgs.brightnessctl pkgs.gawk call ];
        text = ''
          sink=@DEFAULT_AUDIO_SINK@
          source=@DEFAULT_AUDIO_SOURCE@

          # "Volume: 0.45 [MUTED]" -> "45 true"
          read_volume() {
            wpctl get-volume "$1" | awk '{ printf "%d %s\n", $2 * 100 + 0.5, ($3 == "[MUTED]") ? "true" : "false" }'
          }

          case "''${1:-}" in
            up)       wpctl set-mute "$sink" 0; wpctl set-volume -l 1 "$sink" 5%+ ;;
            down)     wpctl set-volume "$sink" 5%- ;;
            mute)     wpctl set-mute "$sink" toggle ;;
            mic)      wpctl set-mute "$source" toggle ;;
            brighter) brightnessctl -q set 5%+ ;;
            dimmer)   brightnessctl -q set 5%- ;;
            *)        echo "usage: 0space-level up|down|mute|mic|brighter|dimmer" >&2; exit 2 ;;
          esac

          case "$1" in
            up | down | mute) read -r pct muted < <(read_volume "$sink"); kind=Volume ;;
            mic)              read -r pct muted < <(read_volume "$source"); kind=Microphone ;;
            *)                pct=$(brightnessctl -m | awk -F, '{ sub("%", "", $4); print $4 }'); muted=false; kind=Brightness ;;
          esac

          0space-call level display "$kind" "$pct" "$muted" >/dev/null 2>&1 || true
        '';
      };
    in
    {
      environment.systemPackages = with pkgs; [
        call
        level
        discord      # Super+D
        vlc          # Super+V
        ani-cli      # Super+A
        proton-vpn   # Super+P
        swappy       # Super+Shift+S, after grim and slurp
        brightnessctl
      ];

      # Super+E: Thunar, with thumbnails, the bin and removable drives.
      programs.thunar = {
        enable = true;
        plugins = with pkgs; [ thunar-volman thunar-archive-plugin ];
      };
      services.gvfs.enable = true;
      services.tumbler.enable = true;

      # Electron apps (Discord) on Wayland rather than through XWayland.
      environment.sessionVariables.NIXOS_OZONE_WL = "1";
    };
}
