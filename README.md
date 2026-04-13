# Focus Gremlin

`Focus Gremlin` is a native macOS overlay app that follows the cursor with a sprite-driven goblin and comments on distracting browser sessions. The app is built in SwiftUI/AppKit, runs locally, and can optionally use Ollama for page-aware commentary.

## What you get

- Cursor-following goblin overlay rendered in a transparent `NSPanel`
- Sprite-sheet driven animation system (`idle`, `talking`, `spit`, `final`)
- Viscous slime spit effect with live glass/material backdrop
- Rule-based distraction detection plus optional local LLM / VLM commentary
- Debug, test, release, and desktop-install scripts ready for a cloned repo

## Requirements

- macOS 14 or newer
- Full Xcode installed in `/Applications/Xcode.app`
- Command line tools selected via `xcode-select`
- Optional: `xcodegen` if you want to regenerate `FocusGremlin.xcodeproj` from `project.yml`
- Optional: [Ollama](https://ollama.com) for local text or vision models

## Quick Start

```bash
git clone <your-fork-or-repo-url>
cd FocusGremlin
bash scripts/bootstrap.sh
bash scripts/dev.sh
```

What this does:

1. validates the local Xcode toolchain
2. regenerates `FocusGremlin.xcodeproj` from `project.yml` if `xcodegen` is installed and the project is stale
3. builds a Debug app into `.derivedDataBuild/dev`
4. launches the built app

## Development Workflow

### Start a local debug build

```bash
bash scripts/dev.sh
```

Built app path:

```text
.derivedDataBuild/dev/Build/Products/Debug/FocusGremlin.app
```

### Run tests

```bash
bash scripts/test.sh
```

### Build a release app

```bash
bash scripts/build_release.sh
```

Release bundle path:

```text
.derivedDataBuild/release/Build/Products/Release/FocusGremlin.app
```

### Launch an already built app

```bash
bash scripts/run_built_app.sh debug
bash scripts/run_built_app.sh release
```

You can also pass an explicit `.app` path:

```bash
bash scripts/run_built_app.sh /absolute/path/to/FocusGremlin.app
```

### Copy the release build to the Desktop

```bash
bash scripts/install_to_desktop.sh
```

## Project Structure

```text
FocusGremlin/                 app source
FocusGremlinTests/            unit tests
FocusGremlin.xcodeproj/       generated Xcode project
project.yml                   XcodeGen source of truth
scripts/                      bootstrap/build/test/release helpers
docs/                         optional landing page
```

## App Behavior

- The goblin becomes active in distracting contexts and can react to page changes.
- `idle_2` is reserved for page-reaction beats, then it hands off back to `idle_1`.
- Ambient spits are only triggered during doomscroll-like idle windows, not while a line is already speaking.
- After the `final` sequence, slime stains dissolve instead of popping away instantly.

## Local Models and Smart Mode

The app runs without Ollama, but commentary falls back to local templates.

### Text model example

```bash
ollama serve
ollama pull llama3.2
```

### Vision model example

```bash
ollama pull llava
```

Inside the app:

1. enable the agent
2. enable Smart Mode
3. set the Ollama base URL if needed (`http://127.0.0.1:11434` by default)
4. choose the text and vision models

## macOS Privacy Permissions

The product works best when these permissions are granted to the built app:

| Permission | Why it matters |
| --- | --- |
| Accessibility | active window metadata, browser context, hover inspection |
| Input Monitoring | reliable global scroll monitoring on some systems |
| Screen Recording | Smart Mode vision capture |
| Apple Events / Automation | browser tab title / URL access where supported |

If you rebuild frequently with ad-hoc signing, macOS may ask for these permissions again for the new build.

## Performance Notes

- Sprite playback is handled inside AppKit with a `DispatchSourceTimer`, not a SwiftUI timeline.
- The spit overlay state is split out of the main companion view model to avoid full overlay re-layout on every stain update.
- The spit material uses a single outer goo mask for the optical stack, which avoids repeated mask/compositing passes for every highlight layer.
- Cursor following updates at 24 Hz and reduces spit-panel frame churn when the cursor is stationary.

## Release / Publication Notes

- `project.yml` is the canonical project definition.
- `FocusGremlin.xcodeproj` is committed so the repo is usable without XcodeGen.
- Local build artifacts live under `.derivedDataBuild/` and are gitignored.
- The repository already contains `docs/` plus `vercel.json` for an optional landing page deploy.

## Optional Landing Build

```bash
bash scripts/vercel-build.sh
open dist/index.html
```

## Troubleshooting

- If `bash scripts/dev.sh` fails immediately, open Xcode once and make sure `xcode-select -p` points at `/Applications/Xcode.app/Contents/Developer`.
- If the app launches but does not “see” browser context, re-check Accessibility and Automation permissions.
- If Smart Mode feels blind, make sure Screen Recording is granted and the selected Ollama vision model is installed locally.
