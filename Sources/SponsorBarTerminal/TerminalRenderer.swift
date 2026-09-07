import Darwin
import Foundation

struct TerminalRenderer: Sendable {
  let outputIsTTY: Bool

  init(outputIsTTY: Bool = isatty(STDOUT_FILENO) == 1) {
    self.outputIsTTY = outputIsTTY
  }

  func requireInteractiveTerminal() throws {
    guard outputIsTTY else { throw TerminalError.notInteractive }
  }

  func display(
    lease: CreativeLease,
    shutdown: ShutdownController,
    duration: Duration = .seconds(60)
  ) async throws -> DisplayOutcome {
    let requestedSeconds = duration.timeInterval
    let remaining = lease.minuteExpiresAt.timeIntervalSinceNow
    guard remaining >= requestedSeconds else {
      let serverWindow = lease.minuteExpiresAt.timeIntervalSince(lease.startedAt)
      let remainingText = String(format: "%.1f", remaining)
      let serverWindowText = String(format: "%.1f", serverWindow)
      let requestedText = String(format: "%.1f", requestedSeconds)
      print(
        "Lease has \(remainingText)s left; server window is \(serverWindowText)s; "
          + "need \(requestedText)s."
      )
      return .insufficientWindow
    }

    render(lease)
    let clock = SuspendingClock()
    var visibleDuration = Duration.zero

    while visibleDuration < duration {
      if shutdown.isRequested {
        print("\nProcess exit requested. This impression will not be completed.")
        return .interrupted
      }
      if Date() >= lease.minuteExpiresAt {
        print("\nLease expired before the display interval completed.")
        return .expired
      }

      let tick = min(.seconds(1), duration - visibleDuration)
      try await clock.sleep(for: tick)
      if shutdown.isRequested {
        print("\nProcess exit requested. This impression will not be completed.")
        return .interrupted
      }
      guard Date() < lease.minuteExpiresAt else {
        print("\nLease expired before the display interval completed.")
        return .expired
      }
      visibleDuration += tick
      let seconds = visibleDuration.components.seconds
      print("\rVisible: \(seconds)/\(Int(requestedSeconds)) seconds", terminator: "")
      fflush(stdout)
    }

    print("\rVisible for \(Int(requestedSeconds)) seconds.                         ")
    return .completed
  }

  private func render(_ lease: CreativeLease) {
    let creative = lease.creative
    let width = max(60, creative.companyName.count + 8, creative.slogan.count + 8)
    let rule = String(repeating: "═", count: width - 2)
    print("\n╔\(rule)╗")
    print(center("SPONSORED", width: width))
    print("╠\(rule)╣")
    print(center(creative.companyName, width: width))
    print(center(creative.slogan, width: width))
    if let destination = creative.destinationUrl {
      print(center(destination.absoluteString, width: width))
    }
    print("╚\(rule)╝")
    if let logo = creative.logoUrl {
      print("Logo: \(logo.absoluteString)")
    }
    print("Campaign: \(lease.campaignId)")
  }

  private func center(_ value: String, width: Int) -> String {
    let usable = width - 4
    let clipped = String(value.prefix(usable))
    let padding = max(0, usable - clipped.count)
    let left = padding / 2
    let right = padding - left
    return "║ " + String(repeating: " ", count: left) + clipped
      + String(repeating: " ", count: right) + " ║"
  }
}

final class ShutdownController: @unchecked Sendable {
  private let lock = NSLock()
  private var requested = false
  private var signalSources: [DispatchSourceSignal] = []

  var isRequested: Bool {
    lock.withLock { requested }
  }

  func installSignalHandlers() {
    for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
      signal(signalNumber, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
      source.setEventHandler { [weak self] in
        self?.requestExit(signalNumber)
      }
      source.resume()
      lock.withLock { signalSources.append(source) }
    }
  }

  private func requestExit(_ signalNumber: Int32) {
    let shouldEscalate = lock.withLock {
      if requested { return true }
      requested = true
      return false
    }
    if shouldEscalate {
      signal(signalNumber, SIG_DFL)
      raise(signalNumber)
    }
  }
}

extension Duration {
  fileprivate var timeInterval: TimeInterval {
    let value = components
    return Double(value.seconds) + Double(value.attoseconds) / 1_000_000_000_000_000_000
  }
}

enum DisplayOutcome: Equatable {
  case completed
  case insufficientWindow
  case expired
  case interrupted
}

enum TerminalError: LocalizedError {
  case notInteractive

  var errorDescription: String? {
    "Standard output is not an interactive terminal. Refusing to claim a terminal impression."
  }
}
