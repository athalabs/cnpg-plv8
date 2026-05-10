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

# Build deps:
#   - clang/lld: V8 is officially built with clang. gcc-14 (trixie's default)
#     mis-resolves `std::remove` against C's `<stdio.h>` `remove(const char*)`
#     in cppgc/stats-collector.h, breaking the build at ~54%. clang-19 is fine.
#   - build-essential: still needed for libstdc++-dev and the PGXS toolchain
#     (plv8 itself + final link); we only force clang for the V8 sub-build.
#   - cmake/git/pkg-config: v8-cmake build, plv8 source fetch.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg \
        build-essential pkg-config cmake git \
        clang lld \
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

# Patch V8 source: cppgc/stats-collector.h calls `std::remove(it,it,val)`
# (the <algorithm> overload) without including <algorithm>. It used to
# compile via transitive includes, but trixie's libstdc++14 dropped that
# transitive chain, so the only `remove` symbol left at that call site is
# C's `remove(const char*)` from <stdio.h> -- the 3-arg call then fails.
# bnoordhuis/v8-cmake's V8 is 11.6 (March 2024) and isn't getting fixes.
RUN sed -i '1i#include <algorithm>' \
    deps/v8-cmake/v8/src/heap/cppgc/stats-collector.h

# Pre-build v8-cmake explicitly with clang. plv8's outer Makefile invokes
# cmake without compiler args, and PGXS (pulled in by plv8) overrides CC/CXX
# in the make environment with the values recorded in pg_config (which on
# Debian/PGDG end up pointing at g++, breaking the cmake C-compiler probe).
# Doing the cmake step ourselves bypasses that orchestration entirely; once
# libv8_libbase.a exists, plv8's make sees the dependency satisfied and
# skips its own cmake invocation.
RUN set -eux; \
    cd deps/v8-cmake; \
    mkdir -p build; \
    cd build; \
    cmake -DCMAKE_C_COMPILER=/usr/bin/clang \
          -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
          -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
          -Denable-fPIC=ON \
          -DCMAKE_BUILD_TYPE=Release \
          ..; \
    make -j"$(nproc)"

# Now build plv8.so itself (PGXS-driven; uses gcc, which is fine -- ABI
# matches the rest of the postgres image). `make install` lays files out
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

# Upstream license (plv8 ships it as `COPYRIGHT`, not `LICENSE`)
COPY --from=builder /src/COPYRIGHT /licenses/plv8/COPYRIGHT

# CNPG mounts the volume read-only; the user is informational.
USER 65532:65532
