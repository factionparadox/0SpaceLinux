# The Andalite palette, shared by the theme and Mirrorwave.
# (Outside modules/ so import-tree doesn't load it as a module.)
rec {
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

  # 16 terminal colours: normal, then bright.
  console = [
    c.void c.red c.green c.tan c.fur c.pink c.glass c.text
    "2a3a5a" "e06070" "6fd3b5" "f0dcb0" "8fbcf0" "f08ac0" "c6ebff" "ffffff"
  ];
}
