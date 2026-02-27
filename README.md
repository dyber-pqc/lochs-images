# Lochs Images

Official FreeBSD jail images for [Lochs](https://lochs.dev) - FreeBSD containers on Linux.

## Image Catalog

### Base Images

| Image | Tag | Size | Description |
|-------|-----|------|-------------|
| `freebsd` | `15.0`, `latest` | ~163MB | Full FreeBSD 15.0-RELEASE base system |
| `freebsd` | `15.0-minimal` | ~148MB | Stripped (no docs, debug symbols, extra locales) |
| `freebsd` | `15.0-rescue` | ~97MB | Bare minimum rescue/recovery environment |
| `freebsd` | `14.2`, `14-stable` | ~160MB | Full FreeBSD 14.2-RELEASE base system |
| `freebsd` | `14.2-minimal` | ~145MB | Stripped FreeBSD 14.2 |

### Application Images

| Image | Version | Base | Ports Package | Status |
|-------|---------|------|---------------|--------|
| `nginx` | 1.26 | `freebsd:15.0-minimal` | `nginx` | Planned |
| `postgresql` | 16, 15 | `freebsd:15.0-minimal` | `postgresql16-server` | Planned |
| `redis` | 7.2 | `freebsd:15.0-minimal` | `redis` | Planned |
| `python` | 3.11 | `freebsd:15.0-minimal` | `python311` | Planned |
| `node` | 22 | `freebsd:15.0-minimal` | `node22` | Planned |
| `go` | 1.22 | `freebsd:15.0-minimal` | `go` | Planned |
| `rust` | 1.77 | `freebsd:15.0-minimal` | `rust` | Planned |

## Quick Start

```bash
# Pull and run a base FreeBSD jail
lochs pull freebsd:15.0-minimal
lochs create myjail --image freebsd:15.0-minimal
lochs start myjail
lochs exec myjail /bin/sh

# Pull and run nginx
lochs pull nginx:1.26
lochs create web --image nginx:1.26 -p 8080:80
lochs start web
```

## Building Images

### Base Images

```bash
# Build all base image variants for FreeBSD 15.0
./build-images.sh 15.0
```

This creates three variants in `output/`:
- `freebsd-15.0-full.txz` - Complete base system
- `freebsd-15.0-minimal.txz` - Stripped (~20% smaller)
- `freebsd-15.0-rescue.txz` - Bare minimum

### Application Images

```bash
# List available images
./build-app-images.sh list

# Build a specific image (requires root for chroot/pkg install)
sudo ./build-app-images.sh nginx

# Build all application images
sudo ./build-app-images.sh all
```

Application images are built on top of `freebsd:15.0-minimal` by:
1. Copying the base filesystem
2. Chrooting into it
3. Running `pkg install` for the required packages
4. Packaging the result as a `.txz`

### Custom Images

Create a `Lochfile` in `images/<name>/`:

```
FROM freebsd:15.0-minimal
LABEL maintainer="you"
LABEL description="My custom image"
LABEL version="1.0"

RUN pkg install -y mypackage
RUN echo 'config here' > /usr/local/etc/mypackage.conf

EXPOSE 8080
CMD ["/usr/local/bin/mypackage"]
```

Then build it:

```bash
sudo ./build-app-images.sh myimage
```

## Registry

The `registry.json` file contains the full image catalog with metadata, download URLs, tags, and version info. Lochs CLI uses this to resolve `lochs pull` requests.

```bash
# The registry is hosted at:
# https://github.com/dyber-pqc/lochs-images/releases
#
# Images are downloaded as GitHub Release assets:
# https://github.com/dyber-pqc/lochs-images/releases/download/v15.0/freebsd-15.0-minimal.txz
```

## Compatibility Matrix

These images are tested with BSDulator's syscall translation layer. Current coverage:

| Software | Static Binary | Dynamic Binary | Full Functionality |
|----------|:------------:|:--------------:|:-----------------:|
| FreeBSD base utils | Yes | Yes | Yes |
| /bin/sh | Yes | Yes | Yes |
| nginx | - | Planned | Planned |
| PostgreSQL | - | Planned | Planned |
| Redis | - | Planned | Planned |
| Python | - | Planned | Planned |
| Node.js | - | Planned | Planned |

**Legend:** Yes = verified working, Planned = Lochfile ready but not yet tested, - = not applicable

## Directory Structure

```
.
├── build-images.sh          # Base image builder
├── build-app-images.sh      # Application image builder
├── registry.json            # Image registry manifest
├── images/
│   ├── freebsd-base/Lochfile
│   ├── nginx/Lochfile
│   ├── postgresql/Lochfile
│   ├── redis/Lochfile
│   ├── python/Lochfile
│   ├── node/Lochfile
│   ├── go/Lochfile
│   └── rust/Lochfile
├── build/                   # Build workspace (gitignored)
└── output/                  # Built images (gitignored)
```

## CI/CD

Images are built automatically via GitHub Actions:
- **Weekly builds**: Every Sunday at midnight (base images for FreeBSD 15.0 and 14.2)
- **On push**: When Lochfiles or build scripts change
- **Manual trigger**: Workflow dispatch with version input
- **Validation**: All Lochfiles and registry.json are validated on every push

## Contributing

To add a new image:
1. Create `images/<name>/Lochfile`
2. Add entry to `registry.json`
3. Test locally with `sudo ./build-app-images.sh <name>`
4. Submit a PR

## License

FreeBSD base system is licensed under the BSD License.
Image packaging scripts and Lochfiles are MIT licensed.
