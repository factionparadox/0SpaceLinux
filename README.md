# 0-Space Linux

> `< Dome integrity nominal. All engines report ready. >`

An Andalite war-cruiser for a desktop, built on NixOS.

- **The carousel**: a Wayfire plugin of our own. Windows stand on a ring that
  runs back into the screen, seen from slightly above. The front window is full
  size; the others recede round the ring in perspective, smaller, higher and
  dimmer with distance, and squashed side-on round the sides. Spinning brings
  the next one round to the front. No title bars, no window chrome.
- **The Dome**: the biosphere you carry with you, as the background: night
  sky, nebula, two moons, the dome's glass rim, hills in mist, and the red,
  blue and pink trees of home (`art/dome.png`, rendered by `tools/render-dome.py`).
- **The ring floor**: the carousel's ring in perspective under the windows,
  marked in the script, with every window named and the front one bracketed.
- **The script**: an invented alphabet. Thought-speak, window names and the
  ring's markings are written in it, with plain English underneath.
- **Thought-speak**: notifications float at the top, `< like this >`.
- **The morph limit**: at one hour fifty minutes, the ship tells you to demorph.
- **Idle lock**: locks after 9 minutes idle and always before sleep.
- **Liberated systemd**: systemd without the `birthDate` user-record field.
- **escafil**: the operator. One short command for every job.
- No Flatpak: everything comes from nixpkgs.

## escafil

```
escafil scan              kernel, generation, packages date, Wi-Fi, power, disk
escafil doctor            scan, plus failed services and network
escafil morph             rebuild the ship from its design and switch to it
escafil jump              update to the newest packages, then morph
escafil demorph           go back to the previous generation
escafil generations       list the generations you can go back to
escafil acquire FORM...   add packages, then morph
escafil shed FORM...      remove packages you acquired, then morph
escafil forms             list what you've acquired
escafil seek TERM         search for packages
escafil try FORM...       use packages in this shell only
escafil run FORM [ARGS]   run a package once
escafil shred [AGE]       clear generations older than AGE (default 14d)
escafil record [NAME]     keep a copy of the ship's design and state
escafil edit              open this ship's design
escafil orders            all of the above
```

## Controls

| Keys | Order |
|---|---|
| Super+Left / Super+Right | Spin the carousel |
| Super+Tab | Stalk-eye overview: every window laid out flat |
| Super+R | Cycle the front window's width: 33, 50, 67 or 100% |
| Super+F | Toggle the front window between full width and 50% |
| Super+Shift+F | True fullscreen |
| Super+Q | Close the front window |
| Super+1 to 9 | Go to a workspace (each has its own carousel) |
| Super+Shift+1 to 9 | Take the front window to a workspace |
| Super+T / Super+W | Terminal / browser |
| Super+S | `escafil scan` |
| Super+Shift+S | Record a region of the screen |
| Super+X / Super+Z | Lock / suspend |

Clicking any window on the carousel spins it round to the front.

## How it's built

A dendritic flake: every file in `modules/` is a flake-parts module, picked up
automatically by import-tree. Each feature is one file:

| File | What it is |
|---|---|
| `modules/features/base.nix` | Boot, kernel, firmware, network, sound, the user |
| `modules/features/liberated-systemd.nix` | systemd without `birthDate` |
| `modules/features/carousel.nix` | The Wayfire plugin, packaged and loaded |
| `modules/features/dome.nix` | The session: Wayfire, the shell, greetd autologin |
| `modules/features/forms.nix` | Packages acquired with `escafil` |
| `modules/features/escafil.nix` | The operator |
| `modules/features/branding.nix` | What the ship calls itself |
| `modules/flake/hosts.nix` | Every folder in `hosts/` becomes a machine |
| `modules/flake/installer.nix` | The installer ISO |

Each machine has a folder in `hosts/`: its hardware, its user, and its forms
list. The installer writes one for the machine it installs to, and the
installed ship keeps its design in `/etc/0space`.

### Liberated systemd without rebuilds

Patching systemd normally changes the identity of everything built against
it, so Nix would rebuild a large part of the system. Instead, the system
comes from the binary cache as usual and `system.replaceDependencies` swaps
the patched systemd in afterwards. Only systemd itself is compiled, once per
systemd version. The patch only removes code, so the swap is safe. (The
initrd keeps stock systemd; it has no user records.)

## Building the ISO

On a machine with Nix (flakes on):

```
nix build .#iso
```

The ISO (about 3 GB) is in `result/iso/`. It boots straight into the
installer, which asks for a disk, a ship's name, your name and a password.
Almost everything installs from the stick. The few parts made for the machine's
own hardware are fetched from the NixOS cache, so the installer connects first
(with a Wi-Fi step if needed). It's a small download.

Building the ISO compiles systemd once (the liberated version) and downloads
the rest from the NixOS cache.

## Status

Tested, on nixos-unstable (systemd 262, Wayfire 0.10.1, Quickshell 0.3.2):

- The flake evaluates, and the carousel plugin builds as a Nix package.
- The full system builds. Its systemd is the liberated one: `birthDate`
  appears in none of its files, and NixOS's stock systemd is gone from the system.
- The built session runs: Wayfire with the carousel, the shell with the Dome,
  ring floor, names in the script and thought-speak. See `docs/ring-headless-test.png`.
- A machine set up the way the installer writes it builds with only small
  local steps, reusing the liberated systemd, and acquired forms install.
- The ISO builds and boots into the installer.
- escafil and the installer pass shellcheck at its strictest level.

Not yet tested:

- A complete install, start to finish. The test VM couldn't reach the cache
  through the sandbox's network.
- Real hardware: the Framework's Wi-Fi, graphics, suspend and the idle lock.
- The keybindings (they need real input).
- Two other copies of stock systemd's code remain in the system's store:
  plain `systemd` and `systemd-minimal`, which a few packages depend on. They
  don't run the system or its logins. Swapping them too would mean two more
  systemd compiles per systemd version.

## Art

`art/dome.png` is the default Dome. Your own
`~/.local/share/0space/art/dome.png` takes priority over it.
