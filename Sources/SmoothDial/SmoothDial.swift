import AppKit
import CoreGraphics
import Foundation

/// Converts discrete dial/wheel scroll events into continuous/precise scroll events
/// (the same kind a trackpad produces), so apps see smooth ~1px scrolling instead of
/// coarse ~19px "line" jumps.
///
/// Trackpad events pass through unchanged.

@main
enum SmoothDial {

    /// Sensitivity multiplier parsed from CLI. 100 = 1×, 200 = 2×, 50 = 0.5×.
    private static var sensitivity: Double = 1.0

    private static var inGesture = false
    private static var lastEventTime: CFAbsoluteTime = 0
    private static var lastLocation: CGPoint = .zero
    private static let gestureTimeout: CFAbsoluteTime = 0.15
    private static var endTimer: DispatchSourceTimer?

    static func main() {
        if CommandLine.arguments.count > 1, let raw = Double(CommandLine.arguments[1]), raw > 0 {
            sensitivity = raw / 100.0
        }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollCallback,
            userInfo: nil
        ) else {
            fputs("SmoothDial: CGEvent tap creation failed (check Accessibility / Input Monitoring).\n", stderr)
            exit(1)
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        fputs(
            """
            SmoothDial: sensitivity=\(Int(sensitivity * 100)) (\(String(format: "%.2f", sensitivity))×).
            Discrete dial → continuous/precise. Trackpad passthrough. Ctrl+C to quit.
            Usage: SmoothDial [sensitivity]  (default 100, 200 = 2×, 50 = 0.5×)

            """,
            stderr
        )
        RunLoop.main.run()
    }

    fileprivate static func handleScroll(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)

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

        outX *= sensitivity
        outY *= sensitivity

        let now = CFAbsoluteTimeGetCurrent()
        let scrollPhase: Int64
        if !inGesture || (now - lastEventTime) > gestureTimeout {
            scrollPhase = 1  // NSEventPhaseBegan
            inGesture = true
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

        print("dial → precise: point=(\(fmt(outX)), \(fmt(outY))) phase=\(scrollPhase)")
        fflush(stdout)

        return Unmanaged.passUnretained(event)
    }

    private static func scheduleGestureEnd() {
        endTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + gestureTimeout)
        timer.setEventHandler {
            guard inGesture else { return }
            inGesture = false

            guard let endEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: 0,
                wheel2: 0,
                wheel3: 0
            ) else { return }

            endEvent.location = lastLocation
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

            print("dial → precise: phase=4 (ended)")
            fflush(stdout)
        }
        timer.resume()
        endTimer = timer
    }

    fileprivate static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private func scrollCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    switch type {
    case .scrollWheel:
        return SmoothDial.handleScroll(proxy: proxy, event: event)
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        return Unmanaged.passUnretained(event)
    default:
        return Unmanaged.passUnretained(event)
    }
}
