# Third-Party Notices for Bundled cwebp

Utility Suite includes a vendored macOS arm64 build of the `cwebp` command line encoder and the dynamic libraries required by that binary. These files are packaged into `Utility Suite.app/Contents/Resources` so WebP conversion works without a separate Homebrew or system library installation.

Bundled binaries:

- `bin/cwebp`
- `lib/libwebpdemux.2.dylib`
- `lib/libwebp.7.dylib`
- `lib/libsharpyuv.0.dylib`
- `lib/libpng16.16.dylib`
- `lib/libjpeg.8.dylib`
- `lib/libtiff.6.dylib`
- `lib/libzstd.1.dylib`
- `lib/liblzma.5.dylib`

Included components and licenses:

- libwebp / cwebp 1.6.0: see `licenses/libwebp-COPYING.txt`
- libpng: see `licenses/libpng-LICENSE.txt`
- libjpeg-turbo: see `licenses/jpeg-turbo-LICENSE.md`
- LibTIFF: see `licenses/libtiff-LICENSE.md`
- Zstandard: see `licenses/zstd-LICENSE.txt`
- XZ Utils liblzma: see `licenses/xz-COPYING.txt` and `licenses/xz-COPYING.0BSD.txt`

The vendored binary paths were adjusted with `install_name_tool` so the app loads these libraries from its own `Contents/Resources/lib` directory.
