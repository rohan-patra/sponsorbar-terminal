import CryptoKit
import Foundation
import Security

final class DeviceProofStore: @unchecked Sendable {
  static let keyAccount = "device-proof-key"

  let keychain: KeychainStore
  private let lock = NSLock()
  private var cachedKey: SecureEnclave.P256.Signing.PrivateKey?

  init(keychain: KeychainStore = KeychainStore()) {
    self.keychain = keychain
  }

  func prepare() throws {
    guard SecureEnclave.isAvailable else {
      throw DeviceProofError.secureEnclaveUnavailable
    }
    if let data = try keychain.data(for: Self.keyAccount) {
      let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)
      lock.withLock { cachedKey = key }
      return
    }
    var accessError: Unmanaged<CFError>?
    guard
      let access = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        [],
        &accessError
      )
    else {
      throw accessError?.takeRetainedValue() ?? DeviceProofError.keyCreationFailed
    }
    let key = try SecureEnclave.P256.Signing.PrivateKey(
      compactRepresentable: true,
      accessControl: access
    )
    try keychain.set(key.dataRepresentation, for: Self.keyAccount)
    lock.withLock { cachedKey = key }
  }

  func sign(_ request: inout URLRequest, now: Date = Date(), nonce: UUID = UUID()) throws {
    guard let method = request.httpMethod, let url = request.url else {
      throw DeviceProofError.invalidRequest
    }
    let timestamp = String(Int64(floor(now.timeIntervalSince1970 * 1_000)))
    let nonceText = nonce.uuidString.lowercased()
    let canonical = Self.requestCanonicalString(
      method: method,
      target: Self.requestTarget(url),
      timestamp: timestamp,
      nonce: nonceText,
      body: request.httpBody ?? Data()
    )
    let signature = try privateKey().signature(for: Data(canonical.utf8))
    request.setValue(timestamp, forHTTPHeaderField: "X-SponsorBar-Timestamp")
    request.setValue(nonceText, forHTTPHeaderField: "X-SponsorBar-Nonce")
    request.setValue(
      signature.derRepresentation.base64EncodedString(),
      forHTTPHeaderField: "X-SponsorBar-Signature"
    )
  }

  func pairingIdentity(
    code: String,
    deviceName: String,
    deviceCheckToken: String
  ) throws -> (publicKey: String, proof: String) {
    let key = try privateKey()
    let publicKey = key.publicKey.x963Representation.base64EncodedString()
    let canonical = Self.pairingCanonicalString(
      code: code,
      deviceName: deviceName,
      publicKey: publicKey,
      deviceCheckToken: deviceCheckToken
    )
    let proof = try key.signature(for: Data(canonical.utf8))
      .derRepresentation.base64EncodedString()
    return (publicKey, proof)
  }

  static func requestCanonicalString(
    method: String,
    target: String,
    timestamp: String,
    nonce: String,
    body: Data
  ) -> String {
    [
      "sponsorbar-device-request-v1",
      method.uppercased(),
      target,
      timestamp,
      nonce.lowercased(),
      sha256Hex(body),
    ].joined(separator: "\n")
  }

  static func pairingCanonicalString(
    code: String,
    deviceName: String,
    publicKey: String,
    deviceCheckToken: String
  ) -> String {
    [
      "sponsorbar-device-pairing-v1",
      code,
      deviceName,
      publicKey,
      sha256Hex(Data(deviceCheckToken.utf8)),
    ].joined(separator: "\n")
  }

  static func requestTarget(_ url: URL) -> String {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url.path
    }
    let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
    return components.percentEncodedPath + query
  }

  static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func privateKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
    guard SecureEnclave.isAvailable else {
      throw DeviceProofError.secureEnclaveUnavailable
    }
    if let cached = lock.withLock({ cachedKey }) { return cached }
    guard let representation = try keychain.data(for: Self.keyAccount) else {
      throw DeviceProofError.keyMissing
    }
    let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: representation)
    lock.withLock { cachedKey = key }
    return key
  }
}

enum DeviceProofError: LocalizedError {
  case secureEnclaveUnavailable
  case keyMissing
  case keyCreationFailed
  case invalidRequest

  var errorDescription: String? {
    switch self {
    case .secureEnclaveUnavailable:
      return "The Secure Enclave is unavailable on this Mac."
    case .keyMissing:
      return "The SponsorBar device proof key is missing from Keychain."
    case .keyCreationFailed:
      return "Could not create Secure Enclave key access control."
    case .invalidRequest:
      return "The request has no HTTP method or URL."
    }
  }
}
