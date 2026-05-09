# cnpg-plv8

[plv8](https://plv8.github.io/) packaged as a [CloudNativePG ImageVolume
extension image](https://cloudnative-pg.io/docs/devel/imagevolume_extensions/),
so any CNPG cluster on PostgreSQL 18+ can mount it without rebuilding the
operand image.

The shared library statically links V8, so the extension drops in without
adding any libv8 / libnode runtime dependency to the postgres pod.

## Requirements

- CloudNativePG with the `ImageVolume` feature
- Kubernetes **1.35+** (default), or 1.33–1.34 with the `ImageVolume` feature
  gate enabled
- Container runtime: containerd v2.1.0+ or CRI-O v1.31+
- PostgreSQL **18+** (extension uses `extension_control_path`)

## Image

`ghcr.io/athalabs/cnpg-plv8`

| Tag | Mutability | Use for |
| --- | --- | --- |
| `18-trixie` | mutable, latest plv8 for PG 18 / trixie | manual pinning |
| `18-trixie-3.2.4` | mutable, latest build of plv8 3.2.4 for PG 18 / trixie | manual pinning |
| `18-trixie-3.2.4-YYYYMMDDhhmm` | immutable | Flux `ImagePolicy` (`numerical` ordering on the timestamp suffix) |

**Architectures:** `linux/amd64` only by default. See [build notes](#build-notes)
below for the rationale and how to add arm64.

## Use it in a CNPG `Cluster`

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: example-db
  namespace: tenant-a9
spec:
  imageName: ghcr.io/athalabs/cnpg-postgres-batteries-included:18-3-standard-trixie
  instances: 3
  storage:
    size: 8Gi
  postgresql:
    extensions:
      - name: plv8
        image:
          reference: ghcr.io/athalabs/cnpg-plv8:18-trixie
```

Then in your database:

```sql
CREATE EXTENSION plv8;

-- Quick check
DO $$
  var x = plv8.execute("select 'hello from v8' as msg");
  plv8.elog(NOTICE, x[0].msg);
$$ LANGUAGE plv8;
```

## Image layout

This image follows the [CNPG ImageVolume contract](https://cloudnative-pg.io/docs/devel/imagevolume_extensions/):

```
/share/extension/plv8.control
/share/extension/plv8--*.sql
/lib/plv8-*.so
/licenses/plv8/LICENSE
```

The volume is mounted read-only at `/extensions/plv8/` in the postgres pod, and
CNPG points `extension_control_path` and `dynamic_library_path` at it.

## Build notes

- plv8 isn't packaged in PGDG, so the builder stage clones
  [`plv8/plv8`](https://github.com/plv8/plv8) at the SHA pinned in
  [`docker-bake.hcl`](docker-bake.hcl) (`plv8Ref` variable) and runs the
  default `make` target against PostgreSQL 18 server-dev headers.
- We ship from r3.2 HEAD rather than the v3.2.4 tag because v3.2.4
  (2025-07-05) predates the PG18-final compatibility fix
  ([`Use PG_MODULE_MAGIC_EXT in PostgreSQL 18 and later`](https://github.com/plv8/plv8/commit/b40812ecbb7fa1c52a89d47dd71be8c3247ca06f),
  2026-05-07). The `:18-trixie-3.2.4*` image tags reflect plv8's hardcoded
  internal `PLV8_VERSION`, but the code is post-3.2.4.
- The default `make` target builds V8 from source via the
  [`bnoordhuis/v8-cmake`](https://github.com/bnoordhuis/v8-cmake) submodule
  and statically links it into `plv8.so`. This produces a self-contained
  extension (no runtime libv8 dependency in the postgres pod) but is **slow**:
  the V8 build is the dominant cost.
- **arm64 is disabled by default.** Under QEMU emulation the V8 build
  routinely exceeds the 6-hour GitHub Actions job limit. To enable arm64, run
  builds on a self-hosted arm64 runner (or accept the long emulated build) and
  add `linux/arm64` to `platforms` in `docker-bake.hcl`.

## Building locally

```bash
docker buildx bake

# Push to your own registry
registry=ghcr.io/yourname/cnpg-plv8 docker buildx bake --push

# Build a different plv8 ref (any tag, branch, or SHA in plv8/plv8)
docker buildx bake --set '*.args.PLV8_REF=v3.2.4'
```

## License

[Apache 2.0](LICENSE) for this packaging. plv8 itself is licensed under the
[PostgreSQL License](https://github.com/plv8/plv8/blob/master/LICENSE);
the extension's `LICENSE` ships at `/licenses/plv8/LICENSE` inside the image.
