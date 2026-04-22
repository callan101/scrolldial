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

    private var menu: NSMenu!
    private var manualModeToggle: ToggleSwitch!
    private var devicesMenuItem: NSMenuItem!
    private var deviceSubmenu: NSMenu!
    private var deviceMenuItems: [NSMenuItem] = []
    private var allDevicesItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        lastCommitted = SmoothDialSettings.storedSensitivity()
        SmoothDialSettings.loadSavedSensitivityIntoState()
        if SmoothDialDebug.isEnabled {
            SmoothDialDebug.log("debug logging on (stderr)")
        }

        HIDDeviceManager.shared.enumerate()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let iconPath = Bundle.main.path(forResource: "MenuIcon", ofType: "png"),
               let icon = NSImage(contentsOfFile: iconPath) {
                icon.isTemplate = true
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "dial.low", accessibilityDescription: "SmoothDial")
                button.image?.isTemplate = true
            }
        }

        menu = NSMenu()
        menu.delegate = self

        let sliderView = makeSliderView()
        let sliderItem = NSMenuItem()
        sliderItem.view = sliderView
        menu.addItem(sliderItem)
        menu.addItem(NSMenuItem.separator())

        let switchView = makeManualSwitchView()
        let switchItem = NSMenuItem()
        switchItem.view = switchView
        menu.addItem(switchItem)

        devicesMenuItem = NSMenuItem(title: "Devices", action: nil, keyEquivalent: "")
        deviceSubmenu = NSMenu()
        deviceSubmenu.delegate = self
        buildDeviceSubmenuItems()
        devicesMenuItem.submenu = deviceSubmenu
        devicesMenuItem.isEnabled = HIDDeviceManager.shared.isManualMode
        menu.addItem(devicesMenuItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit SmoothDial", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        if !SmoothDialCore.shared.start() {
            promptForAccessibility()
        }
    }

    private func promptForAccessibility() {
        let alert = NSAlert()
        alert.messageText = "SmoothDial needs Accessibility permission"
        alert.informativeText = "Open System Settings, add SmoothDial to Accessibility, then click Retry."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            promptForAccessibility()
        case .alertSecondButtonReturn:
            if !SmoothDialCore.shared.start() {
                promptForAccessibility()
            }
        default:
            NSApp.terminate(nil)
        }
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

    // MARK: - Manual device selection switch

    private func makeManualSwitchView() -> NSView {
        let w: CGFloat = 288
        let h: CGFloat = 30
        let padX: CGFloat = 16
        let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        let label = NSTextField(labelWithString: "Manual device selection")
        label.font = NSFont.systemFont(ofSize: 13)
        label.frame = NSRect(x: padX, y: 6, width: 200, height: 18)

        manualModeToggle = ToggleSwitch(isOn: HIDDeviceManager.shared.isManualMode) { [weak self] isOn in
            HIDDeviceManager.shared.isManualMode = isOn
            self?.devicesMenuItem.isEnabled = isOn
        }
        let tw: CGFloat = 32
        let th: CGFloat = 18
        manualModeToggle.frame = NSRect(x: w - padX - tw, y: (h - th) / 2, width: tw, height: th)

        container.addSubview(label)
        container.addSubview(manualModeToggle)
        return container
    }

    // MARK: - Device submenu

    private func buildDeviceSubmenuItems() {
        let dm = HIDDeviceManager.shared

        allDevicesItem = NSMenuItem(title: "All Devices", action: #selector(toggleAllDevices), keyEquivalent: "")
        allDevicesItem.target = self
        allDevicesItem.state = dm.isAllSelected ? .on : .off
        deviceSubmenu.addItem(allDevicesItem)
        deviceSubmenu.addItem(NSMenuItem.separator())

        for device in dm.devices {
            let item = NSMenuItem(
                title: device.displayName,
                action: #selector(toggleDevice(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device.id
            item.state = dm.isSelected(device) ? .on : .off
            deviceSubmenu.addItem(item)
            deviceMenuItems.append(item)
        }
    }

    private func refreshDeviceCheckmarks() {
        let dm = HIDDeviceManager.shared
        allDevicesItem.state = dm.isAllSelected ? .on : .off
        for item in deviceMenuItems {
            guard let key = item.representedObject as? String,
                  let device = dm.devices.first(where: { $0.id == key }) else { continue }
            item.state = dm.isSelected(device) ? .on : .off
        }
    }

    @objc private func toggleAllDevices() {
        let dm = HIDDeviceManager.shared
        let shouldSelect = !dm.isAllSelected
        for device in dm.devices {
            dm.setSelected(device, selected: shouldSelect)
        }
        refreshDeviceCheckmarks()
    }

    @objc private func toggleDevice(_ sender: NSMenuItem) {
        let dm = HIDDeviceManager.shared
        guard let key = sender.representedObject as? String,
              let device = dm.devices.first(where: { $0.id == key }) else { return }
        dm.setSelected(device, selected: !dm.isSelected(device))
        refreshDeviceCheckmarks()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        SmoothDialCore.shared.stop()
    }
}

extension SmoothDialAppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        if menu === self.menu {
            let manual = HIDDeviceManager.shared.isManualMode
            manualModeToggle.setOn(manual, animated: false)
            devicesMenuItem.isEnabled = manual
        }
        if menu === self.menu || menu === deviceSubmenu {
            refreshDeviceCheckmarks()
        }
    }
}

// MARK: - Custom toggle switch

final class ToggleSwitch: NSView {
    private var isOn: Bool
    private let onChange: (Bool) -> Void
    private let knobInset: CGFloat = 2
    private let animationDuration: TimeInterval = 0.15

    private static let onColor = NSColor.controlAccentColor
    private static let offColor = NSColor.separatorColor

    init(isOn: Bool, onChange: @escaping (Bool) -> Void) {
        self.isOn = isOn
        self.onChange = onChange
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func setOn(_ on: Bool, animated: Bool) {
        guard on != isOn else { return }
        isOn = on
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animationDuration
                ctx.allowsImplicitAnimation = true
                needsDisplay = true
                layoutSubtreeIfNeeded()
            }
        } else {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let trackRect = b
        let radius = trackRect.height / 2

        let trackColor = isOn ? Self.onColor : Self.offColor
        trackColor.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius).fill()

        let knobDiameter = trackRect.height - knobInset * 2
        let knobX = isOn
            ? trackRect.maxX - knobInset - knobDiameter
            : trackRect.minX + knobInset
        let knobRect = NSRect(x: knobX, y: knobInset, width: knobDiameter, height: knobDiameter)

        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
    }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        needsDisplay = true
        onChange(isOn)
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
