import DeviceCheck
import Foundation

actor PairingClient {
  private let baseURL: URL
  private let session: URLSession
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(baseURL: URL, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.session = session
    encoder = JSONEncoder()
    decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
  }

  func start(deviceName: String) async throws -> PairingStartResponse {
    try await post(
      "/api/v1/pairing/start",
      body: PairingStartRequest(deviceName: deviceName)
    )
  }

  func exchange(_ request: PairingExchangeRequest) async throws -> PairingExchangeResponse {
    try await post("/api/v1/pairing/exchange", body: request)
  }

  private func post<T: Encodable, R: Decodable>(_ path: String, body: T) async throws -> R {
    let url = baseURL.appendingPathComponent(
      path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    )
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.httpMethod = "POST"
    request.httpBody = try encoder.encode(body)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw APIError.nonHTTPResponse }
    guard (200..<300).contains(http.statusCode) else {
      let decoded = String(data: data, encoding: .utf8) ?? "<non-UTF-8 body>"
      throw APIError.http(status: http.statusCode, body: String(decoded.prefix(500)))
    }
    return try decoder.decode(R.self, from: data)
  }
}

struct PairingCoordinator: Sendable {
  let baseURL: URL
  let keychain: KeychainStore

  func pair() async throws {
    do {
      _ = try keychain.credentials()
      throw PairingError.alreadyPaired
    } catch KeychainError.credentialsMissing {
      // This is the expected state before first pairing.
    }
    let proof = DeviceProofStore(keychain: keychain)
    try proof.prepare()

    let deviceName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    let client = PairingClient(baseURL: baseURL)
    let pairing = try await client.start(deviceName: deviceName)
    print("Pairing code: \(pairing.code)")
    print("Authorize this device at: \(pairing.verificationUrl.absoluteString)")

    // SponsorBar binds one DeviceCheck token into the proof, then reuses that body while polling.
    let deviceCheckToken = try await generateDeviceCheckToken()
    let identity = try proof.pairingIdentity(
      code: pairing.code,
      deviceName: deviceName,
      deviceCheckToken: deviceCheckToken
    )
    let exchangeRequest = PairingExchangeRequest(
      code: pairing.code,
      deviceName: deviceName,
      devicePublicKey: identity.publicKey,
      deviceKeyProof: identity.proof,
      deviceCheckToken: deviceCheckToken
    )

    let deadline = ContinuousClock.now.advanced(
      by: .seconds(pairing.expiresInSeconds)
    )
    while ContinuousClock.now < deadline {
      do {
        let response = try await client.exchange(exchangeRequest)
        if response.status == "paired",
          let deviceId = response.deviceId,
          let deviceToken = response.deviceToken
        {
          try keychain.set(deviceId, for: "device-id")
          try keychain.set(deviceToken, for: "device-token")
          print("Paired successfully as \(response.account?.displayName ?? deviceName).")
          return
        }
      } catch let APIError.http(status, _) where [404, 409, 425].contains(status) {
        // Authorization has not completed yet.
      }
      try await Task.sleep(for: .seconds(2))
    }
    throw PairingError.expired
  }

  private func generateDeviceCheckToken() async throws -> String {
    guard DCDevice.current.isSupported else { throw PairingError.deviceCheckUnavailable }
    let data: Data = try await withCheckedThrowingContinuation { continuation in
      DCDevice.current.generateToken { data, error in
        if let data {
          continuation.resume(returning: data)
        } else {
          continuation.resume(throwing: error ?? PairingError.deviceCheckUnavailable)
        }
      }
    }
    return data.base64EncodedString()
  }
}

enum PairingError: LocalizedError {
  case alreadyPaired
  case deviceCheckUnavailable
  case expired

  var errorDescription: String? {
    switch self {
    case .alreadyPaired:
      return "This Keychain service already contains SponsorBar device credentials."
    case .deviceCheckUnavailable:
      return "Apple DeviceCheck is unavailable for this executable."
    case .expired:
      return "The pairing request expired before authorization completed."
    }
  }
}
