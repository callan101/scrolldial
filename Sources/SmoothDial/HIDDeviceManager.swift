import CoreGraphics
import Foundation
import IOKit
import IOKit.hid

/// Groups all IOHIDDevice entries that share the same VendorID + ProductID
/// (a single physical device often exposes multiple HID interfaces).
struct HIDDeviceGroup: Identifiable {
    let name: String
    let manufacturer: String
    let vendorID: Int
    let productID: Int
    var senderIDs: Set<Int64>

    var id: String { "\(vendorID):\(productID)" }

    var displayName: String {
        if manufacturer.isEmpty || name.localizedCaseInsensitiveContains(manufacturer) {
            return name
        }
        return "\(name) — \(manufacturer)"
    }
}

/// Undocumented CGEventField that carries the IOKit registry entry ID of the
/// HID device that originated the event.  Reliable across macOS 10.12–15+.
let kCGEventSenderID = CGEventField(rawValue: 87)!

/// Enumerates HID devices, tracks which ones the user has selected for smoothing,
/// and persists the selection across launches via UserDefaults.
///
/// Two modes:
/// - **Auto** (default): smooths any device whose name contains "Full Scroll Dial".
/// - **Manual**: smooths only the devices the user explicitly checks.
final class HIDDeviceManager {
    static let shared = HIDDeviceManager()

    private static let selectedDevicesKey = "SmoothDial.selectedDevices"
    private static let manualModeKey = "SmoothDial.manualDeviceSelection"
    private static let autoMatchName = "Full Scroll Dial"

    private(set) var devices: [HIDDeviceGroup] = []

    private var selectedKeys: Set<String> = []

    var isManualMode: Bool {
        didSet {
            UserDefaults.standard.set(isManualMode, forKey: Self.manualModeKey)
            SmoothDialDebug.log("device mode: \(isManualMode ? "MANUAL" : "AUTO")")
            logFilterState()
        }
    }

    /// Sender IDs the event tap should allow through, based on current mode.
    var allowedSenderIDs: Set<Int64> {
        if isManualMode {
            var ids = Set<Int64>()
            for d in devices where selectedKeys.contains(d.id) {
                ids.formUnion(d.senderIDs)
            }
            return ids
        } else {
            return autoDetectedSenderIDs
        }
    }

    /// Sender IDs for devices whose name contains "Full Scroll Dial".
    var autoDetectedSenderIDs: Set<Int64> {
        var ids = Set<Int64>()
        for d in devices where d.name.localizedCaseInsensitiveContains(Self.autoMatchName) {
            ids.formUnion(d.senderIDs)
        }
        return ids
    }

    /// True when every known device is selected (manual mode).
    var isAllSelected: Bool {
        !devices.isEmpty && devices.allSatisfy { selectedKeys.contains($0.id) }
    }

    private init() {
        isManualMode = UserDefaults.standard.bool(forKey: Self.manualModeKey)
        loadDefaults()
    }

    // MARK: - Enumeration

    func enumerate() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            devices = []
            return
        }

        var groups: [String: HIDDeviceGroup] = [:]
        for device in deviceSet {
            let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
            let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
            let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown Device"
            let mfr = IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String ?? ""

            let service = IOHIDDeviceGetService(device)
            let ids = Self.collectRegistryIDs(root: service)

            let key = "\(vid):\(pid)"
            if groups[key] != nil {
                groups[key]!.senderIDs.formUnion(ids)
            } else {
                groups[key] = HIDDeviceGroup(
                    name: name, manufacturer: mfr,
                    vendorID: vid, productID: pid,
                    senderIDs: ids
                )
            }
        }

        devices = groups.values.sorted { a, b in
            if a.name != b.name { return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
            return a.vendorID < b.vendorID
        }

        SmoothDialDebug.log("enumerated \(devices.count) HID device group(s)")
        for d in devices {
            let ids = d.senderIDs.sorted().map { String($0) }.joined(separator: ", ")
            SmoothDialDebug.log("  \(d.displayName)  VID:\(hex(d.vendorID)) PID:\(hex(d.productID))  senderIDs=[\(ids)]")
        }
        logFilterState()
    }

    /// Walk the IOService tree from `root` downward, collecting the registry entry ID
    /// of every node.  The CGEvent senderID can be any of these (typically the
    /// IOHIDEventDriver or IOHIDEventService child, not the device itself).
    private static func collectRegistryIDs(root: io_service_t) -> Set<Int64> {
        var ids = Set<Int64>()
        var entryID: UInt64 = 0
        if IORegistryEntryGetRegistryEntryID(root, &entryID) == KERN_SUCCESS {
            ids.insert(Int64(bitPattern: entryID))
        }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(root, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return ids
        }
        defer { IOObjectRelease(iterator) }
        var child = IOIteratorNext(iterator)
        while child != 0 {
            ids.formUnion(collectRegistryIDs(root: child))
            IOObjectRelease(child)
            child = IOIteratorNext(iterator)
        }
        return ids
    }

    /// Resolve a CGEvent senderID to a human-readable device name (for debug logging).
    func deviceName(forSenderID sid: Int64) -> String {
        for d in devices where d.senderIDs.contains(sid) {
            return d.displayName
        }
        return "unknown(\(sid))"
    }

    private func hex(_ value: Int) -> String {
        String(format: "%04x", value)
    }

    // MARK: - Selection

    func isSelected(_ device: HIDDeviceGroup) -> Bool {
        selectedKeys.contains(device.id)
    }

    func setSelected(_ device: HIDDeviceGroup, selected: Bool) {
        if selected {
            selectedKeys.insert(device.id)
        } else {
            selectedKeys.remove(device.id)
        }
        saveDefaults()
        SmoothDialDebug.log("device \(selected ? "ON" : "OFF"): \(device.displayName) (\(device.id))")
        logFilterState()
    }

    func logFilterState() {
        if !isManualMode {
            let autoDevices = devices.filter { $0.name.localizedCaseInsensitiveContains(Self.autoMatchName) }
            if autoDevices.isEmpty {
                SmoothDialDebug.log("filter: AUTO — no \"\(Self.autoMatchName)\" devices found (smoothing nothing)")
            } else {
                let names = autoDevices.map(\.displayName)
                SmoothDialDebug.log("filter: AUTO — \(names.joined(separator: ", "))")
            }
        } else if selectedKeys.isEmpty {
            SmoothDialDebug.log("filter: MANUAL — no devices selected (smoothing nothing)")
        } else if isAllSelected {
            SmoothDialDebug.log("filter: MANUAL — all devices selected")
        } else {
            let names = devices.filter { selectedKeys.contains($0.id) }.map(\.displayName)
            SmoothDialDebug.log("filter: MANUAL — \(names.count) device(s): \(names.joined(separator: ", "))")
        }
    }

    // MARK: - Persistence

    private func loadDefaults() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.selectedDevicesKey) ?? []
        selectedKeys = Set(saved)
    }

    private func saveDefaults() {
        UserDefaults.standard.set(Array(selectedKeys), forKey: Self.selectedDevicesKey)
    }
}
