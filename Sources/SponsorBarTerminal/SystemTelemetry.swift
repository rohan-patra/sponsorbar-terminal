import CoreGraphics
import Foundation

struct SystemTelemetry: Sendable {
  let awake: Bool
  let unlocked: Bool
  let activeWithinSeconds: Double

  static func capture() -> SystemTelemetry {
    let anyInput = CGEventType(rawValue: UInt32.max) ?? .null
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    let locked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    return SystemTelemetry(
      awake: CGDisplayIsAsleep(CGMainDisplayID()) == 0,
      unlocked: !locked,
      activeWithinSeconds: CGEventSource.secondsSinceLastEventType(
        .combinedSessionState,
        eventType: anyInput
      )
    )
  }
}
