# SmoothDial

Converts discrete scroll dial/wheel events into smooth continuous scrolling on macOS. Menu bar app with a sensitivity slider.

## Build & Install

Requires Xcode (or Xcode Command Line Tools) and macOS 13+.

```bash
git clone https://github.com/callan101/scrolldial.git
cd scrolldial
./build-app.sh
cp -R build/SmoothDial.app /Applications/
```

On first launch, grant Accessibility permission in **System Settings > Privacy & Security > Accessibility**.

## Development

Run directly without building a .app:

```bash
swift run SmoothDial
```

Or with a CLI sensitivity override (100 = 1×, 50 = 0.5×, 200 = 2×):

```bash
swift run SmoothDial 10
```

Enable debug logging:

```bash
swift run SmoothDial -- --debug
```
