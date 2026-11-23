#!/usr/bin/bash
# Runs inside the final image build. Installs the 0-Space desktop, swaps in
# the liberated systemd, and brands the image.

set -euo pipefail

say() { printf '< %s >\n' "$*"; }

# --- The desktop --------------------------------------------------------------
dnf5 -y install --setopt=install_weak_deps=False \
    wayfire \
    quickshell \
    greetd \
    xorg-x11-server-Xwayland \
    xdg-desktop-portal-wlr \
    kitty \
    firefox \
    swaylock \
    grim slurp wl-clipboard \
    libnotify \
    pipewire wireplumber pipewire-pulseaudio \
    NetworkManager-wifi NetworkManager-tui \
    google-noto-sans-fonts google-noto-sans-mono-fonts

# No Flatpak on 0-Space: everything ships in the image or through escafil.
dnf5 -y remove flatpak || true

# --- systemd, liberated -------------------------------------------------------
shopt -s nullglob
rpms=(/tmp/systemd-rpms/*.rpm)
if [ ${#rpms[@]} -gt 0 ]; then
    # Only swap packages the image already has; skip debug and test packages.
    swap=()
    for rpm in "${rpms[@]}"; do
        name=$(rpm -qp --qf '%{NAME}' "$rpm")
        if rpm -q "$name" >/dev/null 2>&1; then
            swap+=("$rpm")
        fi
    done

    dnf5 -y install --allowerasing "${swap[@]}" || dnf5 -y downgrade "${swap[@]}"

    if ! rpm -q systemd | grep -q '\.0space'; then
        say "systemd swap failed: $(rpm -q systemd)" >&2
        exit 1
    fi

    if grep -qs 'birthDate' /usr/lib64/systemd/libsystemd-shared-*.so /usr/lib64/libnss_systemd.so.2 \
        /usr/lib64/security/pam_systemd*.so /usr/bin/homectl; then
        say "birthDate is still present in systemd. Refusing to build." >&2
        exit 1
    fi

    say "systemd is liberated: $(rpm -q systemd)"
else
    say "No liberated systemd packages were built; keeping Fedora's systemd."
fi

# --- Services -----------------------------------------------------------------
systemctl enable greetd.service
systemctl enable 0space-autologin.service
systemctl set-default graphical.target

# --- Identity -----------------------------------------------------------------
# Keep ID=fedora so Fedora tooling still recognises the system; only the names change.
sed -i \
    -e 's/^NAME=.*/NAME="0-Space Linux"/' \
    -e 's/^PRETTY_NAME=.*/PRETTY_NAME="0-Space Linux"/' \
    -e '/^VARIANT=/d' -e '/^VARIANT_ID=/d' \
    /usr/lib/os-release
printf 'VARIANT="Dome ship"\nVARIANT_ID=0space\n' >> /usr/lib/os-release

chmod +x /usr/bin/escafil /usr/bin/0space-session /usr/libexec/0space/autologin

dnf5 clean all
rm -rf /var/log/dnf5.log /var/cache/libdnf5 /var/lib/dnf /var/cache/ldconfig
# Reinstalling systemd regenerates these; each machine makes its own at boot.
rm -f /var/lib/systemd/random-seed /var/lib/systemd/catalog/database
# Package scriptlets leave runtime state in /run; it must not ship in the image.
find /run -mindepth 1 -maxdepth 1 ! -name secrets ! -name .containerenv -exec rm -rf {} + 2>/dev/null || true
say "Dome ship assembled."
