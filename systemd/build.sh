#!/usr/bin/bash
# Rebuild Fedora's own systemd with the birthDate user-record field removed.
#
# We start from Fedora's source package (so Fedora's security fixes and
# patches are kept) and add one patch: the birthDate removal, taken from the
# Liberated systemd fork. The rebuilt packages get ".0space" on the end of
# their release, so you can always see which systemd you are running.
#
# Output: RPMs in /rpms. If Fedora's systemd has no birthDate field at all,
# /rpms is left empty and the image keeps Fedora's systemd unchanged.

set -euo pipefail

PATCH=/src/systemd/0space-no-birthdate.patch
mkdir -p /rpms

dnf -y install rpm-build dnf-plugins-core
cd /tmp
dnf -y download --source systemd
rpm -i systemd-*.src.rpm

SPEC="$HOME/rpmbuild/SPECS/systemd.spec"
TARBALL=$(ls "$HOME"/rpmbuild/SOURCES/systemd-*.tar.gz | head -n1)

# (Count rather than grep -q: an early exit would break the pipe under pipefail.)
hits=$(tar -xzOf "$TARBALL" --wildcards '*/src/shared/user-record.c' | grep -c 'birthDate' || true)
if [ "${hits:-0}" -eq 0 ]; then
    echo "< Fedora's systemd carries no birthDate field. Nothing to remove. >"
    exit 0
fi

cp "$PATCH" "$HOME/rpmbuild/SOURCES/0space-no-birthdate.patch"
last=$(grep -n '^Patch[0-9]*:' "$SPEC" | tail -n1 | cut -d: -f1)
sed -i "${last}a Patch:          0space-no-birthdate.patch" "$SPEC"

# Stop here, loudly, if Fedora's sources have moved and the patch no longer fits.
if ! rpmbuild -bp --nodeps "$SPEC" > /tmp/prep.log 2>&1; then
    tail -n 40 /tmp/prep.log
    echo "< The birthDate patch no longer applies to Fedora's systemd. Update systemd/0space-no-birthdate.patch. >" >&2
    exit 1
fi

dnf -y builddep "$SPEC"
rpmbuild -bb --nocheck --without tests --define "dist $(rpm -E %dist).0space" "$SPEC"

cp "$HOME"/rpmbuild/RPMS/*/*.rpm /rpms/
echo "< systemd rebuilt without birthDate: $(ls /rpms | wc -l) packages. >"
