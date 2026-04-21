import AppKit
import CGEventSupervisor
import CoreGraphics
import Foundation

private let kScrollSubscriber = "ScrollMonitor"

@main
enum ScrollMonitorApp {
    static func main() {
        CGEventSupervisor.shared.subscribe(
            as: kScrollSubscriber,
            to: .cgEvents(.scrollWheel),
            using: { event in
                let lineX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
                let lineY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                let pixelX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
                let pixelY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
                let phaseRaw = event.getIntegerValueField(.scrollWheelEventScrollPhase)
                let momentumRaw = event.getIntegerValueField(.scrollWheelEventMomentumPhase)

                let ts = String(format: "%.3f", CFAbsoluteTimeGetCurrent())
                print(
                    "[\(ts)] lines: (\(lineX), \(lineY))  pixels: (\(fmt(pixelX)), \(fmt(pixelY)))  phase: \(phaseRaw)  momentum: \(momentumRaw)"
                )
                fflush(stdout)
            }
        )

        fputs(
            "Scroll monitor running. Grant Accessibility if prompted, then scroll anywhere.\nCtrl+C to quit.\n",
            stderr
        )
        RunLoop.main.run()
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
