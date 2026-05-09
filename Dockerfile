# cnpg-plv8: a PL/V8 extension image for CloudNativePG, mounted via the
# `postgresql.extensions` ImageVolume mechanism (CNPG + PG18+).
#
# plv8 is not packaged in PGDG, so we build it from source. The default
# `make` target builds V8 via the bnoordhuis/v8-cmake submodule (CMake
# port of V8) and statically links V8 into plv8.so, so the resulting
# extension has no runtime dependency on libv8/libnode in the postgres pod.
#
# The final stage is `FROM scratch` and ships exactly the layout that CNPG's
# ImageVolume contract requires:
#
#   /share/extension/<files>   -- control + sql files
#   /lib/<files>               -- the .so
#   /licenses/<dir>/copyright  -- license texts

ARG PG_MAJOR=18
# v3.2.4 (2025-07-05) predates the PG18-final fix
# (`Use PG_MODULE_MAGIC_EXT in PostgreSQL 18 and later`, 2026-05-07), so we
# pin to a SHA on the r3.2 branch that includes it.
ARG PLV8_REF=b40812ecbb7fa1c52a89d47dd71be8c3247ca06f

FROM debian:trixie-slim AS builder

ARG PG_MAJOR
ARG PLV8_REF

ENV DEBIAN_FRONTEND=noninteractive

# Build deps (build-essential pulls the trixie-default g++/libstdc++-dev,
# v8-cmake doesn't need depot_tools/gn/ninja so plain cmake is enough)
# plus PGDG for the PG-18 server-dev headers.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg \
        build-essential pkg-config cmake git \
    ; \
    install -d /usr/share/postgresql-common/pgdg; \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        > /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc; \
    . /etc/os-release; \
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        "postgresql-server-dev-${PG_MAJOR}" \
    ; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN set -eux; \
    git init -q .; \
    git remote add origin https://github.com/plv8/plv8.git; \
    git fetch --depth 1 origin "${PLV8_REF}"; \
    git checkout FETCH_HEAD; \
    git submodule update --init --recursive --depth 1

# `make` runs the default `all` target: builds the v8-cmake submodule
# (heavy: V8 from source) then plv8.so. `make install` lays files out
# under DESTDIR using PGXS conventions:
#   $DESTDIR$(pg_config --pkglibdir)  -> /install/usr/lib/postgresql/$PG_MAJOR/lib
#   $DESTDIR$(pg_config --sharedir)   -> /install/usr/share/postgresql/$PG_MAJOR
RUN set -eux; \
    make -j"$(nproc)"; \
    make install DESTDIR=/install


FROM scratch

ARG PG_MAJOR

# Extension SQL + control files
COPY --from=builder /install/usr/share/postgresql/${PG_MAJOR}/extension/ /share/extension/

# Shared library (V8 statically linked, no runtime libv8 needed in pod)
COPY --from=builder /install/usr/lib/postgresql/${PG_MAJOR}/lib/ /lib/

# Upstream license
COPY --from=builder /src/LICENSE /licenses/plv8/LICENSE

# CNPG mounts the volume read-only; the user is informational.
USER 65532:65532
