# Empire of Minds — License Strategy

## Goal

Avoid early license choices that block a future commercial release.

## Engine

Initial preferred engine: Godot.

Rationale:

- permissive MIT license
- no revenue share
- suitable for 2D strategy prototyping
- commercially usable
- broad export support

Godot license obligations must be tracked and fulfilled in release packaging.

## Dependency Policy

Preferred dependency licenses:

- MIT
- BSD
- Apache-2.0
- Zlib
- public domain / CC0 where appropriate

Use with caution:

- LGPL
- MPL
- GPL

Avoid unless explicitly approved:

- AGPL
- unclear “free for personal use”
- assets with non-commercial restrictions
- assets with no license
- random web assets without provenance

## Asset Policy

Preferred assets:

- original assets created for the project
- purchased assets with commercial rights
- CC0/public domain assets
- permissively licensed assets with clear attribution requirements

All assets must have:

- source
- license
- author/vendor
- date acquired
- allowed use
- attribution requirement

## Suggested file

The asset register is created when the project first tracks external assets, at the path:

```text
data/ASSET_REGISTER.md
```

Until then, the path is reserved; no file is required in Phase 0 or Phase 1 until assets are added. Follow the IP boundary in [PROJECT_BRIEF.md](PROJECT_BRIEF.md) and [VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md).
