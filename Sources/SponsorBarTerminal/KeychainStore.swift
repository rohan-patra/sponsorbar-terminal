import Foundation
import Security

struct KeychainStore: Sendable {
  let service: String

  init(service: String = "com.kickbot.sponsorbar") {
    self.service = service
  }

  func data(for account: String) throws -> Data? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess, let data = result as? Data else {
      throw KeychainError.operationFailed(status)
    }
    return data
  }

  func string(for account: String) throws -> String? {
    guard let data = try data(for: account) else { return nil }
    guard let value = String(data: data, encoding: .utf8) else {
      throw KeychainError.invalidUTF8(account)
    }
    return value
  }

  func set(_ data: Data, for account: String) throws {
    let identity: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
    let update: [CFString: Any] = [
      kSecValueData: data,
      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let updateStatus = SecItemUpdate(identity as CFDictionary, update as CFDictionary)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw KeychainError.operationFailed(updateStatus)
    }

    var insert = identity
    insert[kSecValueData] = data
    insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(insert as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw KeychainError.operationFailed(addStatus)
    }
  }

  func set(_ value: String, for account: String) throws {
    try set(Data(value.utf8), for: account)
  }

  func credentials() throws -> DeviceCredentials {
    guard let deviceId = try string(for: "device-id"),
      let token = try string(for: "device-token")
    else {
      throw KeychainError.credentialsMissing(service)
    }
    return DeviceCredentials(deviceId: deviceId, token: token)
  }
}

enum KeychainError: LocalizedError {
  case operationFailed(OSStatus)
  case invalidUTF8(String)
  case credentialsMissing(String)

  var errorDescription: String? {
    switch self {
    case .operationFailed(let status):
      let detail = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
      return "Keychain operation failed (\(status)): \(detail)"
    case .invalidUTF8(let account):
      return "Keychain value \(account) is not valid UTF-8."
    case .credentialsMissing(let service):
      return "No paired device credentials were found in Keychain service \(service)."
    }
  }
}
