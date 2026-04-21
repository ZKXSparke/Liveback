# JetBrains Mono — Liveback asset bundle

`JetBrainsMono-Regular.woff2` is the only third-party font Liveback ships.
It is used for technical text only (file sizes, elapsed ms, error-code
chips, FIXED counter) per brand §4.

## Source

- Upstream repo: https://github.com/JetBrains/JetBrainsMono
- Release used: `v2.304`
  (https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip)
- Archive path: `fonts/webfonts/JetBrainsMono-Regular.woff2`
- SHA-256: `a9cb1cd82332b23a47e3a1239d25d13c86d16c4220695e34b243effa999f45f2`
- File size: 92,164 bytes

## License

SIL Open Font License 1.1 (OFL). No attribution required in-app, but the
upstream repo is cited above.

## Why WOFF2

`pubspec.yaml` declares the asset path as `.woff2` to match the original
bootstrap choice (brand doc says "~200KB woff2"). Flutter 3.13+ with the
Skia/Impeller text layer loads WOFF2 natively on Android. If a future
Flutter engine drops support, swap to `JetBrainsMono-Regular.ttf` (also in
the upstream release under `fonts/ttf/`, SHA-256:
`<compute at swap time>`) and update `pubspec.yaml`.
