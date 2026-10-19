# Notes for coding agents

Text to Speech is a macOS menu bar app built with Tauri 2: Rust in `src-tauri/`, plain HTML, CSS and JavaScript in `src/` (no framework, no bundler). It reads the selection aloud with one of two engines: Rafael (an HTTP server that answers MP3, made by Fish Audio) or Piper (on device, ONNX Runtime and espeak-ng).

## Layout

| Path | What it is |
| --- | --- |
| `src-tauri/src/lib.rs` | App setup, Tauri commands, the menu bar and the global shortcut |
| `src-tauri/src/selection.rs` | Reads the selection: Cmd + C through System Events, then puts the clipboard back |
| `src-tauri/src/tts.rs` | The internet voice: `POST <server>/speak-timed`, configurable (`server_url`, `TEXT_TO_SPEECH_SERVER`) |
| `src-tauri/src/piper.rs` | The offline voice: download from Hugging Face, synthesis to WAV |
| `src-tauri/src/config.rs`, `permissions.rs` | Settings (`config.json`), Accessibility |
| `src-tauri/src/self_test.rs` | `--self-test <dir>`: both voices end to end, no window |
| `src/i18n.js`, `src-tauri/src/i18n.rs` | The interface in English and Brazilian Portuguese, following the Mac's language (first preferred language `pt…` → Portuguese, anything else → English). Rust decides; the windows ask it (`ui_language`). Permission texts in `src-tauri/lproj/<lang>.lproj/InfoPlist.strings` |
| `src/main.js`, `src/index.html` | The floating player: parts ahead, word highlight, keys |
| `src/reading.js` | Pure logic: how a text becomes parts, word timing, the clock. Tested by `reading.test.js`; the web page at ciromaciel.click uses a copy of it |
| `src/settings.*` | The settings window |
| `scripts/assets.mjs` | Regenerates the icons (committed; a build never needs it) |
| `scripts/release/` | Signed and notarized build, publishing, the one-line installer; used by `.github/workflows/release.yml` |

## Before you say it works

```bash
bun test src
bun run build
"/tmp/tts-target/release/bundle/macos/Text to Speech.app/Contents/MacOS/text-to-speech" --self-test /tmp/tts-check
```

The Rust target is `/tmp/tts-target` (`src-tauri/.cargo/config.toml`), because espeak-ng fails to build on long paths.

## Rules that must hold

- No secret in the app or the repository: the server holds the Fish Audio key.
- Network calls: the configured voice server (text and speed only, Rafael only) and the Piper voice download. Nothing else, and no remote fonts or scripts in `src/`.
- The bundle identifier `click.ciromaciel.text-to-speech` never changes: macOS ties Accessibility to it.
- The version lives in `package.json`; bumping it on `main` is a release.
- Bun, never npm. Code, comments and file names are in English.
- Every user-facing string exists in English and Brazilian Portuguese (`src/i18n.js`, `src-tauri/src/i18n.rs`, `src-tauri/lproj/`); a change that adds text adds both. The voices speak Brazilian Portuguese in both languages: the spoken samples stay in Portuguese.

To see the windows in each language, launch the built app with `--open-settings <tab>` (`shortcut`, `voice`, `player`, `system`) and `-AppleLanguages "(en)"` or `-AppleLanguages "(pt-BR)"`; with `HOME` pointed at an empty folder it leaves your settings alone.
