import AppKit
import CoreGraphics
import Foundation

/// When integer "line" and float "point" both describe the same physical tick, we must not add them.
/// If there is already smooth data (point ± fixed), that carries the motion; otherwise one notch → pixels.
private let pointsPerNotch: Double = 40

@main
enum StripScrollLines {
    static func main() {
        guard installHIDScrollTap() else {
            fputs(
                "StripScrollLines: CGEvent tap creation failed (permissions or system policy).\n",
                stderr
            )
            exit(1)
        }

        fputs(
            """
            StripScrollLines: HID tap. Merges fixed-point into point deltas and clears fixed fields.
            Integer line fields are left as-is (many apps ignore point-only scroll if these are 0).
            stdout: before/after. Ctrl+C to quit.

            """,
            stderr
        )
        RunLoop.main.run()
    }

    private static func installHIDScrollTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollStripCallback,
            userInfo: nil
        ) else {
            return false
        }

        let runLoop = CFRunLoopGetCurrent()
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    fileprivate static func stripLineComponents(_ event: CGEvent) {
        let lx = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let ly = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let px = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let py = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let fx = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let fy = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)

        let outX = mergedAxis(line: lx, point: px, fixed: fx)
        let outY = mergedAxis(line: ly, point: py, fixed: fy)

        let before =
            "before: line=(\(lx), \(ly)) fixed=(\(fmt(fx)), \(fmt(fy))) point=(\(fmt(px)), \(fmt(py))) phase=\(phase) momentum=\(momentum)"
        print(before)

        // Clear legacy fixed-point line representation; fold that motion into point fields above.
        // Keep integer line deltas: zeroing scrollWheelEventDeltaAxis1/2 breaks many stacks (e.g. USB dials).
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: outY)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: outX)

        let after =
            "after:  line=(\(lx), \(ly)) fixed=(0.00, 0.00) point=(\(fmt(outX)), \(fmt(outY)))"
        print(after)
        fflush(stdout)
    }

    /// Prefer combined point+fixed when that already describes motion; otherwise map line notches to pixels.
    private static func mergedAxis(line: Int64, point: Double, fixed: Double) -> Double {
        let smooth = point + fixed
        if abs(smooth) > 1e-9 {
            return smooth
        }
        return Double(line) * pointsPerNotch
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private func scrollStripCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .scrollWheel {
        StripScrollLines.stripLineComponents(event)
    }
    return Unmanaged.passUnretained(event)
}
