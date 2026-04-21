import Foundation

/// Opt-in stderr logging. Enable with any of:
/// - `SMOOTHDIAL_DEBUG=1` (or `true` / `yes`)
/// - `--debug` or `-v` in the process arguments (e.g. `swift run SmoothDial -- --debug`)
enum SmoothDialDebug {
    static var isEnabled: Bool {
        let env = ProcessInfo.processInfo.environment["SMOOTHDIAL_DEBUG"]?.lowercased()
        if env == "1" || env == "true" || env == "yes" { return true }
        let args = CommandLine.arguments
        return args.contains("--debug") || args.contains("-v")
    }

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        fputs("SmoothDial: \(message())\n", stderr)
        fflush(stderr)
    }
}
