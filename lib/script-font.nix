# The Andalite script as an installable font (art/0space-script.ttf, drawn by
# tools/make-script-font.py).
pkgs:
pkgs.runCommand "0space-script-font" { } ''
  install -Dm444 ${../art/0space-script.ttf} $out/share/fonts/truetype/0space-script.ttf
''
