# 0-Space Linux
#
# Three stages: Fedora's systemd rebuilt without birthDate, the ring plugin
# built against Fedora's Wayfire, then the Universal Blue image that carries
# them both. All three use the same Fedora release, so the ring plugin always
# matches the Wayfire it ships with.

ARG FEDORA_VERSION=45
ARG BASE_IMAGE=ghcr.io/ublue-os/base-main

# --- Stage 1: systemd, liberated -------------------------------------------
FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION} AS systemd-build
COPY systemd/ /src/systemd/
RUN /src/systemd/build.sh

# --- Stage 2: the ring ------------------------------------------------------
FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION} AS ring-build
RUN dnf -y install wayfire-devel glm-devel gcc-c++ meson ninja-build pkgconf && dnf clean all
COPY ring/ /src/ring/
RUN cd /src/ring \
    && meson setup build --prefix=/usr --buildtype=release \
    && ninja -C build \
    && DESTDIR=/out meson install -C build

# --- Stage 3: the Dome ship -------------------------------------------------
FROM ${BASE_IMAGE}:${FEDORA_VERSION}

COPY --from=systemd-build /rpms/ /tmp/systemd-rpms/
COPY --from=ring-build /out/ /
COPY system_files/ /
COPY build_files/ /tmp/build_files/

RUN /tmp/build_files/build.sh \
    && find /tmp /var/tmp -mindepth 1 -delete \
    && bootc container lint
