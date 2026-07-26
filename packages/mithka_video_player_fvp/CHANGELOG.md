## 0.1.0

- Added explicit, one-time FVP backend registration for every Flutter engine.
- Added typed platform, latency, decoder, size, and advanced libmdk options.
- Added a reusable macOS packaging helper and host integration contract that
  remove MDK's Homebrew and local FFmpeg search paths before final app signing.
- Kept FVP optional so the core player does not force native FVP binaries into
  applications that use only official `video_player` implementations.
- Documented per-engine/process-wide initialization rules and the repository's
  validated `0.37.3+mithka.1` Apple Swift Package Manager override.
