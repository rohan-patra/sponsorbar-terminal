import AppKit
import Foundation

enum Command: Sendable, Equatable {
  case run
  case pair
}

struct Configuration: Sendable {
  static let baseURL = URL(string: "https://sponsorbar.io")!
  static let keychainService = "com.kickbot.sponsorbar"

  let command: Command
  let once: Bool

  static func parse(_ arguments: [String]) throws -> Configuration {
    var command = Command.run
    var once = false

    for argument in arguments {
      switch argument {
      case "--once":
        once = true
      case "--pair":
        command = .pair
      case "--help", "-h":
        throw ConfigurationError.helpRequested
      default:
        throw ConfigurationError.unknownArgument(argument)
      }
    }

    return Configuration(command: command, once: once)
  }

  static let usage = """
    Usage: sponsorbar-terminal [options]

      --pair   Pair this Mac instead of requesting creatives
      --once   Exit after one delivery result or paid minute
      --help   Show this help

    Examples:
      sponsorbar-terminal --pair
      sponsorbar-terminal --once
    """
}

struct SponsorBarRunner: Sendable {
  let configuration: Configuration
  let shutdown = ShutdownController()

  func run() async throws {
    let renderer = TerminalRenderer()
    try renderer.requireInteractiveTerminal()
    try refuseConcurrentSponsorBarApp()

    let keychain = KeychainStore(service: Configuration.keychainService)
    let credentials = try keychain.credentials()
    let proof = DeviceProofStore(keychain: keychain)
    let api = APIClient(
      baseURL: Configuration.baseURL,
      credentials: credentials,
      proof: proof
    )
    shutdown.installSignalHandlers()

    let initialStatus = try await fetchInitialStatus(api)
    let accountPermission = AccountPermission(status: initialStatus)
    try await accountPermission.requireEarningAllowed()
    let statusTask = Task {
      while !Task.isCancelled, !shutdown.isRequested {
        try? await Task.sleep(for: .seconds(30))
        guard !Task.isCancelled else { return }
        do {
          let status = try await api.fetchStatus(timeZone: TimeZone.current.identifier)
          await accountPermission.update(status)
        } catch {
          fputs("Status refresh failed: \(error.localizedDescription)\n", stderr)
        }
      }
    }
    defer { statusTask.cancel() }

    let sessionId = UUID().uuidString.lowercased()
    var previousCampaignId: String?
    var runCompletedMinutes: Int?
    var backoff = 1
    var displayBackoff = 1
    var consecutiveShortLeases = 0

    while !shutdown.isRequested {
      do {
        try refuseConcurrentSponsorBarApp()
        try await accountPermission.requireEarningAllowed()
        let response = try await api.lease(
          eligibilityEnvelope(
            credentials: credentials,
            sessionId: sessionId,
            previousCampaignId: previousCampaignId,
            runCompletedMinutes: runCompletedMinutes
          )
        )
        backoff = 1

        guard let lease = response.lease else {
          displayBackoff = 1
          consecutiveShortLeases = 0
          let reason =
            response.reasons.isEmpty
            ? response.status
            : response.reasons.joined(separator: ", ")
          print("No paid creative: \(reason)")
          if configuration.once { return }
          try await sleep(seconds: response.retryAfterSeconds)
          continue
        }

        let outcome = try await renderer.display(lease: lease, shutdown: shutdown)
        guard outcome == .completed else {
          if outcome == .insufficientWindow {
            consecutiveShortLeases += 1
            if consecutiveShortLeases >= 3 {
              throw DeliveryError.repeatedShortLeases
            }
          } else {
            consecutiveShortLeases = 0
          }
          if configuration.once || shutdown.isRequested { return }
          try await sleep(seconds: displayBackoff)
          displayBackoff = min(displayBackoff * 2, 60)
          continue
        }
        displayBackoff = 1
        consecutiveShortLeases = 0

        try refuseConcurrentSponsorBarApp()
        try await accountPermission.requireEarningAllowed()
        let completion = try await api.complete(
          CompletionRequest(
            minuteId: lease.minuteId,
            signature: lease.signature,
            completionKey: UUID().uuidString,
            monotonicSeconds: ProcessInfo.processInfo.systemUptime
          )
        )
        previousCampaignId = lease.campaignId
        runCompletedMinutes = (runCompletedMinutes ?? 0) + 1
        printCompletion(completion)
        if configuration.once { return }
      } catch let error as AccountPermissionError {
        throw error
      } catch let error as DeliveryError {
        throw error
      } catch let error as ConfigurationError {
        throw error
      } catch {
        fputs("Delivery error: \(error.localizedDescription)\n", stderr)
        if configuration.once { throw error }
        try await sleep(seconds: backoff)
        backoff = min(backoff * 2, 15)
      }
    }
  }

  private func fetchInitialStatus(_ api: APIClient) async throws -> DeviceStatus {
    var lastError: Error?
    for attempt in 1...3 {
      do {
        return try await api.fetchStatus(timeZone: TimeZone.current.identifier)
      } catch {
        lastError = error
        if attempt < 3 { try await sleep(seconds: attempt) }
      }
    }
    throw lastError ?? URLError(.unknown)
  }

  private func eligibilityEnvelope(
    credentials: DeviceCredentials,
    sessionId: String,
    previousCampaignId: String?,
    runCompletedMinutes: Int?
  ) -> EligibilityEnvelope {
    let telemetry = SystemTelemetry.capture()
    return EligibilityEnvelope(
      deviceId: credentials.deviceId,
      sessionId: sessionId,
      appVersion: "1.0.11",
      locale: Locale.current.identifier,
      country: Locale.current.region?.identifier ?? "ZZ",
      displayClass: "standard",
      awake: telemetry.awake,
      unlocked: telemetry.unlocked,
      activeWithinSeconds: telemetry.activeWithinSeconds,
      statusItemRendered: true,
      geometryValid: true,
      occlusionVisible: true,
      menuBarPresented: true,
      monotonicSeconds: ProcessInfo.processInfo.systemUptime,
      previousCampaignId: previousCampaignId,
      runCompletedMinutes: runCompletedMinutes
    )
  }

  private func printCompletion(_ response: CompletionResponse) {
    if response.payable == false {
      print("Completion recorded but marked non-payable: \(response.status)")
    } else if let microUsd = response.creditedMicroUsd {
      print("Completion accepted: \(microUsd) micro-USD credited.")
    } else {
      print("Completion response: \(response.status)")
    }
  }

  private func sleep(seconds: Int) async throws {
    let bounded = max(1, min(seconds, 300))
    try await Task.sleep(for: .seconds(bounded))
  }

  private func refuseConcurrentSponsorBarApp() throws {
    let bundleIdentifiers = ["com.kickbot.sponsorbar", "com.kickbot.sponsorbar-dev"]
    if bundleIdentifiers.contains(where: {
      !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
    }) {
      throw ConfigurationError.sponsorBarAlreadyRunning
    }
  }
}

enum DeliveryError: LocalizedError {
  case repeatedShortLeases

  var errorDescription: String? {
    "Three consecutive leases had less than 60 seconds remaining; stopping to avoid repeated production requests."
  }
}

enum ConfigurationError: LocalizedError, Equatable {
  case helpRequested
  case unknownArgument(String)
  case sponsorBarAlreadyRunning

  var errorDescription: String? {
    switch self {
    case .helpRequested:
      return nil
    case .unknownArgument(let argument):
      return "Unknown argument: \(argument)."
    case .sponsorBarAlreadyRunning:
      return "Quit SponsorBar before using the terminal client."
    }
  }
}

actor AccountPermission {
  private var status: DeviceStatus

  init(status: DeviceStatus) {
    self.status = status
  }

  func update(_ status: DeviceStatus) {
    self.status = status
  }

  func requireEarningAllowed() throws {
    guard status.allowsEarning else {
      throw AccountPermissionError.earningUnavailable(status.earningHoldReason)
    }
  }
}

enum AccountPermissionError: LocalizedError {
  case earningUnavailable(String?)

  var errorDescription: String? {
    switch self {
    case .earningUnavailable(let reason):
      return reason.map { "SponsorBar earning is unavailable: \($0)" }
        ?? "SponsorBar earning is currently unavailable for this account."
    }
  }
}
