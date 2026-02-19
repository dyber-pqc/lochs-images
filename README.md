# Lochs Images

Official FreeBSD jail images for [Lochs.dev](https://lochs.dev) - FreeBSD jails on Linux.

## Available Images

| Image | Tag | Size | Description |
|-------|-----|------|-------------|
| freebsd | 15.0 | ~180MB | Full FreeBSD 15.0-RELEASE base system |
| freebsd | 15.0-minimal | ~50MB | Stripped FreeBSD (no docs, debug symbols) |
| freebsd | 15.0-rescue | ~15MB | Minimal rescue/recovery environment |
| freebsd | 14.2 | ~180MB | Full FreeBSD 14.2-RELEASE base system |
| freebsd | 14.2-minimal | ~50MB | Stripped FreeBSD 14.2 |
| freebsd | 13.4 | ~170MB | Full FreeBSD 13.4-RELEASE base system |

## Usage

```bash
# Pull an image
lochs pull freebsd:15.0-minimal

# Create a jail from it
lochs create myjail --image freebsd:15.0-minimal

# Start the jail
lochs start myjail
```

## Building Images

To build images yourself:

```bash
cd image-builder
chmod +x build-images.sh
./build-images.sh 15.0
```

This creates:
- `freebsd-15.0-full.txz` - Complete base system
- `freebsd-15.0-minimal.txz` - Stripped down (~70% smaller)
- `freebsd-15.0-rescue.txz` - Bare minimum for recovery

## Image Contents

### Full (`freebsd:15.0`)
Complete FreeBSD base system including:
- All userland utilities
- Documentation and man pages
- Debug symbols
- All locales

### Minimal (`freebsd:15.0-minimal`)
Stripped base system with:
- Core utilities (sh, ls, cat, grep, etc.)
- Essential libraries
- Basic networking tools
- **Removed**: docs, man pages, debug symbols, extra locales, games

### Rescue (`freebsd:15.0-rescue`)
Bare minimum for recovery:
- Static rescue binaries
- Basic shell and file utilities
- Mount/unmount capabilities
- ~15MB total

## Release Process

1. Run `./build-images.sh <version>`
2. Create GitHub release with tag `v<version>`
3. Upload `.txz` files and `SHA256SUMS`
4. Update lochs registry URLs

## License

FreeBSD base system is licensed under the BSD License.
Image packaging scripts are MIT licensed.
