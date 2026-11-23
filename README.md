# 0-Space Linux

> `< Dome integrity nominal. All engines report ready. >`

An Andalite war-cruiser for a desktop. 0-Space is a Universal Blue (bootc)
image built on Fedora, with:

- **The carousel**: a Wayfire plugin of our own. Windows stand on a ring that
  runs back into the screen, seen from slightly above. The front window is full
  size; the others recede round the ring in perspective, smaller, higher and
  dimmer with distance, and squashed side-on round the sides. Rotating spins
  the whole carousel. There are no title bars and no window chrome.
- **Thought-speak**: notifications float at the top of the orbit, `< like this >`.
- **The Dome**: the biosphere you carry with you, as the background. It's a
  full-resolution render (`tools/render-dome.py`):
  a deep night sky with soft nebula, fine stars and two moons, the dome's glass
  rim catching the light, layered hills fading into the distance, and the
  red, blue and pink trees of home at the edges of the screen.
- **The ring floor**: the carousel's ring, drawn in perspective under the
  windows and marked in the script. Every window has its name in the script
  and in plain letters, and corner brackets mark the front window.
- **The script**: an invented alphabet. Every letter is a glyph of its own, so
  the same word always looks the same. Thought-speak, window names and the
  ring's markings are all written in it, with plain English underneath.
- **The morph limit**: at one hour fifty minutes, the ship reminds you to demorph.
- **Liberated systemd**: Fedora's own systemd, rebuilt without the `birthDate`
  user-record field.
- **escafil**: acquire and shed forms (packages). There's no Flatpak.

## Controls

| Keys | Order |
|---|---|
| Super+Left / Super+Right | Spin the carousel: the previous or next window comes round to the front |
| Super+Tab | Stalk-eye overview: every window, evenly round the orbit |
| Super+R | Cycle the centre's width: 33, 50, 67 or 100% |
| Super+F | Toggle the centre between full width and 50% |
| Super+Shift+F | True fullscreen |
| Super+Q | Close the centre window |
| Super+1 to 9 | Go to a workspace (each has its own ring) |
| Super+Shift+1 to 9 | Take the centre window to a workspace |
| Super+T / Super+W | Terminal / browser |
| Super+S | Scan the Dome (`escafil scan`) |
| Super+Shift+S | Record a region of the screen |
| Super+X / Super+Z | Lock / suspend |

Clicking any window on the carousel spins it round to the front.

## escafil

```
escafil acquire <form>   add a package (takes effect after restart)
escafil shed <form>      remove a package you added
escafil forms            list what you've added
escafil jump             fetch the newest 0-Space image
escafil demorph          go back to the previous image
escafil scan             report the state of the Dome
```

## Building

The image builds in three stages (see `Containerfile`):

1. **systemd**: downloads Fedora's systemd source package, adds
   `systemd/0space-no-birthdate.patch`, and rebuilds it. The packages are
   marked `.0space` in their release. If Fedora's sources ever move so that
   the patch no longer fits, the build stops and says so instead of shipping
   systemd unpatched.
2. **ring**: builds the Wayfire plugin against Fedora's own `wayfire-devel`,
   so it always matches the Wayfire in the image.
3. **image**: Universal Blue `base-main`, plus the desktop, the liberated
   systemd and the 0-Space files.

To build the image on the Framework (it compiles systemd, so don't use the EliteBook):

```
just build
```

To build an installer ISO from that image:

```
just iso
```

The systemd stage is the slow part, because it compiles all of systemd (about 25 minutes on two cores). Podman
caches it, so later builds only redo what changed.

## Status

Tested so far, on Fedora 45 (systemd 262.1, Wayfire 0.10.1):

- **systemd:** the birthDate patch applies cleanly to Fedora's systemd 262.1,
  and the full rebuild succeeds. Fedora's stock systemd has `birthDate` in five
  of its files; the 0-Space build has it in none.
- **The image:** it builds on Universal Blue `base-main:45`, every systemd
  package in it is the `.0space` build, and `bootc container lint` passes. The
  only warning left belongs to the base image.
- **The session:** inside the built image, the session starts headless. The
  ring centres new windows, orbits the rest, brings a focused window to the
  centre and keeps a separate ring per workspace. The shell draws the Dome,
  the ring band, the brackets, the window names and thought-speak, and they all
  follow the layout because the plugin publishes the ring's exact shape. See
  `docs/ring-headless-test.png`, taken with Firefox and three terminals at the
  Framework's screen proportions.

Not yet tested:

- Real 3D tilt. The side windows are squashed rather than turned in true
  perspective, because Wayfire's 3D transform needs a GPU and there isn't one
  in the test environment. That can be tried on the Framework.
- The keybindings (they need real input).
- The ISO, and the first boot on the Framework: Wi-Fi, graphics, suspend, autologin.

## Art

Put your art in `/usr/share/0space/art/` in the image, or in
`~/.local/share/0space/art/` for your own copy (yours wins).

- `dome.png`: the Dome background

The image ships with a rendered Dome (`usr/share/0space/art/dome.png`, made by
`tools/render-dome.py`). Your own `~/.local/share/0space/art/dome.png` takes
priority over it. If neither exists, the shell draws a simple Dome itself.

Built on Universal Blue and Fedora. The birthDate removal comes from
[Liberated systemd](https://github.com/Jeffrey-Sardina/systemd).
