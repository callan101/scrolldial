# SmoothDial

Converts discrete scroll dial/wheel events into smooth continuous scrolling on macOS. Menu bar app with sensitivity control and per-device filtering.

## Build & Install

Requires Xcode Command Line Tools and macOS 13+.

```bash
git clone https://github.com/callan101/scrolldial.git
cd scrolldial
./build-app.sh
cp -R build/SmoothDial.app /Applications/
```

On first launch, grant **Accessibility** permission when prompted (or add manually in System Settings > Privacy & Security > Accessibility).

## Features

- **Sensitivity slider** in the menu bar dropdown
- **Auto mode** (default) — automatically smooths devices named "Full Scroll Dial"
- **Manual mode** — toggle on to pick specific HID devices from a submenu
- **Debug logging** — stderr output for every scroll event with before/after details

## Development

```bash
swift run SmoothDial              # run with defaults
swift run SmoothDial 10           # sensitivity override (100 = 1×, 50 = 0.5×, 200 = 2×)
swift run SmoothDial -- --debug   # enable debug logging
```
