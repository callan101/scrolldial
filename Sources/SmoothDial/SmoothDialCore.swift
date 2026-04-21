import AppKit
import CoreGraphics
import Foundation

/// Same rule as legacy `swift run SmoothDial <n>`: **multiplier = n / 100**
/// (e.g. 100 → 1×, 10 → 0.1×, 200 → 2×). One division — this is not “% then ×% again”.
final class SmoothDialState {
    static let shared = SmoothDialState()

    private let lock = NSLock()
    /// Applied to converted point deltas (`out *= multiplier`). Default matches old binary with no CLI args (1×).
    private var multiplier: Double = 1.0

    private init() {}

    func multiplierValue() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return multiplier
    }

    /// `cliArgument` is the same number as `swift run SmoothDial <n>`: **multiplier = n / 100**. Must be **> 0**.
    func setSensitivityCLI(_ cliArgument: Double) {
        guard cliArgument > 0, cliArgument.isFinite else { return }
        lock.lock()
        multiplier = cliArgument / 100.0
        lock.unlock()
    }
}

/// Picks up the same numbers as legacy `swift run SmoothDial <n>`: first non-flag arg, or value after `--`.
private func applyLaunchSensitivityOverride() {
    let args = CommandLine.arguments
    if let idx = args.firstIndex(of: "--"), idx + 1 < args.count,
       let raw = Double(args[idx + 1]), raw > 0 {
        SmoothDialState.shared.setSensitivityCLI(raw)
        return
    }
    guard args.count >= 2 else { return }
    let a = args[1]
    if a == "--debug" || a == "-v" { return }
    if let raw = Double(a), raw > 0 {
        SmoothDialState.shared.setSensitivityCLI(raw)
    }
}

/// Converts discrete dial/wheel scroll events into continuous/precise scroll events.
/// Trackpad events pass through unchanged.
final class SmoothDialCore {
    static let shared = SmoothDialCore()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var started = false

    private var inGesture = false
    private var lastEventTime: CFAbsoluteTime = 0
    private var lastLocation: CGPoint = .zero
    private let gestureTimeout: CFAbsoluteTime = 0.15
    private var endTimer: DispatchSourceTimer?

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        applyLaunchSensitivityOverride()

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let createdTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: smoothDialScrollCallback,
            userInfo: nil
        ) else {
            fputs("SmoothDial: CGEvent tap creation failed (check Accessibility / Input Monitoring).\n", stderr)
            return
        }
        tap = createdTap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: createdTap, enable: true)

        let m = SmoothDialState.shared.multiplierValue()
        SmoothDialDebug.log(
            String(format: "event tap installed (cghid, scrollWheel); CLI scale=%.0f → ×%.3f", m * 100.0, m)
        )
    }

    func stop() {
        endTimer?.cancel()
        endTimer = nil
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap {
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
        started = false
    }

    fileprivate func handleScroll(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        let multiplier = SmoothDialState.shared.multiplierValue()

        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)

        // Trackpad / already-continuous events pass through untouched.
        if phase != 0 || momentum != 0 || isContinuous != 0 {
            return Unmanaged.passUnretained(event)
        }

        let ly = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let lx = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let py = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let px = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let fy = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let fx = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)

        var outY = py + fy
        var outX = px + fx
        if abs(outY) < 1e-9 && abs(outX) < 1e-9 {
            outY = Double(ly)
            outX = Double(lx)
        }

        outX *= multiplier
        outY *= multiplier

        let now = CFAbsoluteTimeGetCurrent()
        let gap = now - lastEventTime
        let scrollPhase: Int64
        if !inGesture || gap > gestureTimeout {
            scrollPhase = 1  // NSEventPhaseBegan
            inGesture = true
            SmoothDialDebug.log(
                String(format: "gesture BEGIN (gap=%.3fs)", gap)
            )
        } else {
            scrollPhase = 2  // NSEventPhaseChanged
        }
        lastEventTime = now
        lastLocation = event.location

        scheduleGestureEnd()

        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: outY)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: outX)

        SmoothDialDebug.log(
            String(
                format: "dial → precise point=(%.2f, %.2f) phase=%lld mult=×%.3f",
                outX, outY, scrollPhase, multiplier
            )
        )

        return Unmanaged.passUnretained(event)
    }

    private func scheduleGestureEnd() {
        endTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + gestureTimeout)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.inGesture else { return }
            self.inGesture = false

            guard let endEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: 0,
                wheel2: 0,
                wheel3: 0
            ) else { return }

            endEvent.location = self.lastLocation
            endEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            endEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)  // NSEventPhaseEnded
            endEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
            endEvent.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
            endEvent.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
            endEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
            endEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
            endEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
            endEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: 0)
            endEvent.post(tap: .cgSessionEventTap)
            SmoothDialDebug.log("posted synthetic scroll phase=ended (gesture boundary)")
        }
        timer.resume()
        endTimer = timer
    }

    fileprivate func reenableTapIfNeeded() {
        guard let tap else { return }
        SmoothDialDebug.log("event tap was disabled (timeout/user); re-enabling")
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

private func smoothDialScrollCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    switch type {
    case .scrollWheel:
        return SmoothDialCore.shared.handleScroll(proxy: proxy, event: event)
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        SmoothDialCore.shared.reenableTapIfNeeded()
        return Unmanaged.passUnretained(event)
    default:
        return Unmanaged.passUnretained(event)
    }
}
