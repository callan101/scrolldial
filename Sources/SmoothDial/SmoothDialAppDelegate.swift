// Menu bar UI (BoDial-style AppKit): NSStatusItem + NSMenu + NSSlider in NSMenuItem.view.
// Scroll / CGEvent behavior lives in SmoothDialCore.

import AppKit

private let kSliderMin: Double = 1
private let kSliderMax: Double = 200

final class SmoothDialAppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private var statusItem: NSStatusItem!
    private var valueField: NSTextField!
    private var sensitivitySlider: NSSlider!
    private var updatingControlsFromCode = false
    /// Last successfully applied sensitivity; used to revert bad text input.
    private var lastCommitted: Double = 100

    func applicationDidFinishLaunching(_ notification: Notification) {
        lastCommitted = SmoothDialSettings.storedSensitivity()
        SmoothDialSettings.loadSavedSensitivityIntoState()
        if SmoothDialDebug.isEnabled {
            SmoothDialDebug.log("debug logging on (stderr)")
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "dial.low", accessibilityDescription: "SmoothDial")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let sliderView = makeSliderView()
        let sliderItem = NSMenuItem()
        sliderItem.view = sliderView
        menu.addItem(sliderItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit SmoothDial", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        SmoothDialCore.shared.start()
    }

    private func makeSliderView() -> NSView {
        // Coordinates are bottom-left origin.
        let w: CGFloat = 288
        let h: CGFloat = 58
        let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        let padX: CGFloat = 16
        let innerW = w - padX * 2

        let title = NSTextField(labelWithString: "Sensitivity")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: padX, y: 32, width: innerW, height: 18)

        let label = NSTextField(labelWithString: "Value:")
        label.frame = NSRect(x: padX, y: 8, width: 44, height: 16)
        label.font = NSFont.systemFont(ofSize: 12)

        let initial = lastCommitted
        sensitivitySlider = NSSlider(
            value: pegSliderToValue(initial),
            minValue: kSliderMin,
            maxValue: kSliderMax,
            target: self,
            action: #selector(sliderChanged(_:))
        )
        sensitivitySlider.frame = NSRect(x: 60, y: 6, width: 132, height: 24)
        sensitivitySlider.isContinuous = true

        valueField = NSTextField(string: formatSensitivity(initial))
        valueField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueField.alignment = .right
        valueField.frame = NSRect(x: 198, y: 6, width: 72, height: 22)
        valueField.isEditable = true
        valueField.isSelectable = true
        valueField.delegate = self

        container.addSubview(title)
        container.addSubview(label)
        container.addSubview(sensitivitySlider)
        container.addSubview(valueField)

        return container
    }

    /// Slider only covers 1…200; larger typed values show the knob pegged at 200.
    private func pegSliderToValue(_ v: Double) -> Double {
        min(kSliderMax, max(kSliderMin, v))
    }

    private func formatSensitivity(_ v: Double) -> String {
        let r = v.rounded()
        if v.isFinite, abs(v - r) < 1e-9 { return String(Int(r)) }
        return String(v)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard !updatingControlsFromCode else { return }
        let v = min(kSliderMax, max(kSliderMin, sender.doubleValue.rounded()))
        applySensitivity(v)
    }

    private func applySensitivity(_ value: Double) {
        guard value > 0, value.isFinite else { return }
        lastCommitted = value
        updatingControlsFromCode = true
        sensitivitySlider.doubleValue = pegSliderToValue(value)
        valueField.stringValue = formatSensitivity(value)
        updatingControlsFromCode = false
        UserDefaults.standard.set(value, forKey: SmoothDialSettings.defaultsKey)
        SmoothDialState.shared.setSensitivityCLI(value)
    }

    private func commitValueField() {
        guard !updatingControlsFromCode else { return }
        let trimmed = valueField.stringValue.trimmingCharacters(in: .whitespaces)
        guard let v = Double(trimmed), v.isFinite, v > 0 else {
            valueField.stringValue = formatSensitivity(lastCommitted)
            updatingControlsFromCode = true
            sensitivitySlider.doubleValue = pegSliderToValue(lastCommitted)
            updatingControlsFromCode = false
            return
        }
        applySensitivity(v)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === valueField else { return }
        commitValueField()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === valueField else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitValueField()
            control.window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        SmoothDialCore.shared.stop()
    }
}

enum SmoothDialSettings {
    static let defaultsKey = "SmoothDial.sensitivityPercent"

    static func storedSensitivity() -> Double {
        guard UserDefaults.standard.object(forKey: defaultsKey) != nil else { return 100 }
        let v = UserDefaults.standard.double(forKey: defaultsKey)
        if v > 0, v.isFinite { return v }
        return 100
    }

    static func loadSavedSensitivityIntoState() {
        let n = storedSensitivity()
        SmoothDialState.shared.setSensitivityCLI(n)
    }
}
