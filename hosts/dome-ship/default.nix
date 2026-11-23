# A reference Dome ship, used to build and test 0-Space. The installer makes
# a folder like this one for each machine it installs to.
{
  imports = [ ./hardware.nix ];
  zerospace.user = "aristh";
  zerospace.forms = import ./forms.nix;
  system.stateVersion = "26.05";
}
