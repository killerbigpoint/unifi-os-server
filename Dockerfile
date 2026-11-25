FROM ghcr.io/clllaur/uosserver:c9603dec9010-multiarch

LABEL org.opencontainers.image.source="https://github.com/killerbigpoint/unifi-os-server"

ENV container="docker"
ENV APP_VERSION="5.1.42"
ENV APP_MODEL="UOSSERVER"
ENV PRODUCT_NAME="UniFi OS Server"

# Pin the Network application release paired with this UniFi OS Server version.
# The release-check workflow updates this value automatically when Ubiquiti
# publishes a newer compatible Network application.
ARG NETWORK_APP_VERSION=10.6.109-36013-1
ENV NETWORK_APP_VERSION=${NETWORK_APP_VERSION}

# The uos CLI needs the firmware version and platform to query Ubiquiti's
# Firmware Update Service. These files are normally created at runtime.
RUN set -eux; \
    echo "UOSSERVER.0000000.${APP_VERSION}.0000000.000000.0000" > /usr/lib/version; \
    if [ ! -s /usr/lib/platform ]; then \
        case "$(dpkg --print-architecture)" in \
            amd64) echo linux-x64 > /usr/lib/platform ;; \
            arm64) echo arm64 > /usr/lib/platform ;; \
            *) echo "linux-$(dpkg --print-architecture)" > /usr/lib/platform ;; \
        esac; \
    fi; \
    mkdir -p /persistent/dpkg /persistent/.config /data /srv /var/lib/unifi

# Install UniFi Network during the image build using Ubiquiti's own uos CLI.
# This handles package retrieval, signing and dependency resolution.
#
# policy-rc.d prevents package scripts from starting services while systemd
# is not running during the image build.
# SKIP_DPKG_CACHE prevents a build-time cache from being baked into the image;
# Home Assistant mounts persistent storage at /persistent at runtime.
# Temporarily remove systemd-cat wrappers from the dpkg hooks because journald
# is not running during docker build, then restore the original hooks.
RUN set -eux; \
    printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; \
    chmod +x /usr/sbin/policy-rc.d; \
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99-bullseye-eol; \
    for HOOK in /etc/dpkg/dpkg.cfg.d/015-ubnt-dpkg-status \
                /etc/dpkg/dpkg.cfg.d/020-ubnt-dpkg-cache; do \
      cp "$HOOK" "$HOOK.original"; \
      sed -i 's|/usr/bin/systemd-cat -t [a-z-]* ||g' "$HOOK"; \
    done; \
    SKIP_DPKG_CACHE=yes /usr/bin/uos runnable install --version "${NETWORK_APP_VERSION}" unifi; \
    for HOOK in /etc/dpkg/dpkg.cfg.d/015-ubnt-dpkg-status \
                /etc/dpkg/dpkg.cfg.d/020-ubnt-dpkg-cache; do \
      mv "$HOOK.original" "$HOOK"; \
    done; \
    rm /etc/apt/apt.conf.d/99-bullseye-eol; \
    rm /usr/sbin/policy-rc.d; \
    rm -rf /var/lib/apt/lists/*

LABEL org.opencontainers.image.network.version="${NETWORK_APP_VERSION}"

STOPSIGNAL SIGRTMIN+3

COPY uos-entrypoint.sh /root/uos-entrypoint.sh

RUN ["chmod", "+x", "/root/uos-entrypoint.sh"]
ENTRYPOINT ["/root/uos-entrypoint.sh"]
