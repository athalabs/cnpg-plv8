// Bake recipe for the cnpg-plv8 ImageVolume extension image.
//
// Why amd64-only by default:
//   plv8's `make static` builds V8 from source. Under QEMU emulation, an arm64
//   build of V8 routinely exceeds the 6-hour GitHub Actions job limit. To
//   build arm64 you'll want a self-hosted arm64 runner; once you have one,
//   add `linux/arm64` to `platforms` below.

variable "registry" {
  default = "ghcr.io/athalabs/cnpg-plv8"
}

variable "revision" {
  default = ""
}

variable "pgMajors" {
  default = ["18"]
}

variable "distros" {
  default = ["trixie"]
}

variable "plv8Version" {
  // Cosmetic version label for image tags. The actual code shipped is
  // determined by `plv8Ref` below.
  default = "3.2.4"
}

variable "plv8Ref" {
  // SHA on the plv8 r3.2 branch that includes the PG18-final fix
  // (`Use PG_MODULE_MAGIC_EXT in PostgreSQL 18 and later`, 2026-05-07).
  // Pin to a SHA for reproducibility; bump as upstream advances.
  default = "b40812ecbb7fa1c52a89d47dd71be8c3247ca06f"
}

variable "platforms" {
  default = ["linux/amd64"]
}

now     = timestamp()
authors = "Atha Labs"
url     = "https://github.com/athalabs/cnpg-plv8"

target "default" {
  matrix = {
    pgMajor = pgMajors
    distro  = distros
  }

  name       = "plv8-${pgMajor}-${distro}"
  dockerfile = "Dockerfile"
  context    = "."
  platforms  = platforms

  args = {
    PG_MAJOR  = pgMajor
    PLV8_REF  = plv8Ref
  }

  tags = [
    "${registry}:${pgMajor}-${distro}",
    "${registry}:${pgMajor}-${distro}-${plv8Version}",
    "${registry}:${pgMajor}-${distro}-${plv8Version}-${formatdate("YYYYMMDDhhmm", now)}",
  ]

  attest = [
    "type=provenance,mode=max",
    "type=sbom",
  ]

  annotations = [
    "index,manifest:org.opencontainers.image.created=${now}",
    "index,manifest:org.opencontainers.image.url=${url}",
    "index,manifest:org.opencontainers.image.source=${url}",
    "index,manifest:org.opencontainers.image.version=${plv8Version}",
    "index,manifest:org.opencontainers.image.revision=${revision}",
    "index,manifest:org.opencontainers.image.vendor=${authors}",
    "index,manifest:org.opencontainers.image.title=plv8 ${plv8Version} for PostgreSQL ${pgMajor} (${distro}) - CNPG ImageVolume",
    "index,manifest:org.opencontainers.image.description=plv8 ${plv8Version} compiled for PostgreSQL ${pgMajor}, packaged as a CloudNativePG ImageVolume extension image",
    "index,manifest:org.opencontainers.image.documentation=${url}",
    "index,manifest:org.opencontainers.image.authors=${authors}",
    "index,manifest:org.opencontainers.image.licenses=PostgreSQL",
  ]

  labels = {
    "org.opencontainers.image.created"       = "${now}"
    "org.opencontainers.image.url"           = "${url}"
    "org.opencontainers.image.source"        = "${url}"
    "org.opencontainers.image.version"       = "${plv8Version}"
    "org.opencontainers.image.revision"      = "${revision}"
    "org.opencontainers.image.vendor"        = "${authors}"
    "org.opencontainers.image.title"         = "plv8 ${plv8Version} for PostgreSQL ${pgMajor} (${distro}) - CNPG ImageVolume"
    "org.opencontainers.image.description"   = "plv8 ${plv8Version} compiled for PostgreSQL ${pgMajor}, packaged as a CloudNativePG ImageVolume extension image"
    "org.opencontainers.image.documentation" = "${url}"
    "org.opencontainers.image.authors"       = "${authors}"
    "org.opencontainers.image.licenses"      = "PostgreSQL"
  }
}
