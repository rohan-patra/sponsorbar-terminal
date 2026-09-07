import Foundation

struct EligibilityEnvelope: Encodable, Sendable {
  let deviceId: String
  let sessionId: String
  let appVersion: String
  let locale: String
  let country: String
  let displayClass: String
  let awake: Bool
  let unlocked: Bool
  let activeWithinSeconds: Double
  let statusItemRendered: Bool
  let geometryValid: Bool
  let occlusionVisible: Bool
  let menuBarPresented: Bool
  let monotonicSeconds: Double
  let previousCampaignId: String?
  let runCompletedMinutes: Int?
}

struct Creative: Decodable, Sendable {
  let id: String?
  let companyName: String
  let slogan: String
  let destinationUrl: URL?
  let logoUrl: URL?
  let backgroundColor: String?
  let foregroundColor: String?
  let sloganColor: String?

  private enum CodingKeys: String, CodingKey {
    case id, companyName, slogan, destinationUrl, logoUrl
    case backgroundColor, foregroundColor, sloganColor
  }

  init(
    id: String? = nil,
    companyName: String,
    slogan: String,
    destinationUrl: URL? = nil,
    logoUrl: URL? = nil,
    backgroundColor: String? = nil,
    foregroundColor: String? = nil,
    sloganColor: String? = nil
  ) {
    self.id = id
    self.companyName = companyName
    self.slogan = slogan
    self.destinationUrl = destinationUrl
    self.logoUrl = logoUrl
    self.backgroundColor = backgroundColor
    self.foregroundColor = foregroundColor
    self.sloganColor = sloganColor
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decodeIfPresent(String.self, forKey: .id)
    companyName = try values.decode(String.self, forKey: .companyName)
    slogan = try values.decode(String.self, forKey: .slogan)
    destinationUrl = try values.decodeIfPresent(URL.self, forKey: .destinationUrl)
    logoUrl = try values.decodeIfPresent(URL.self, forKey: .logoUrl)
    backgroundColor = try values.decodeIfPresent(String.self, forKey: .backgroundColor)
    foregroundColor = try values.decodeIfPresent(String.self, forKey: .foregroundColor)
    sloganColor = try values.decodeIfPresent(String.self, forKey: .sloganColor)
  }
}

struct CreativeLease: Decodable, Sendable {
  let runId: String
  let minuteId: String
  let campaignId: String
  let creative: Creative
  let startedAt: Date
  let minuteExpiresAt: Date
  let runTargetMinutes: Int
  let signature: String
}

struct DeliveryResponse: Decodable, Sendable {
  let status: String
  let lease: CreativeLease?
  let reasons: [String]
  let retryAfterSeconds: Int

  private enum CodingKeys: String, CodingKey {
    case status, lease, reasons, retryAfterSeconds
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    status = try values.decode(String.self, forKey: .status)
    lease = try values.decodeIfPresent(CreativeLease.self, forKey: .lease)
    reasons = try values.decodeIfPresent([String].self, forKey: .reasons) ?? []
    retryAfterSeconds =
      try values.decodeIfPresent(Int.self, forKey: .retryAfterSeconds)
      ?? (status == "ineligible" ? 15 : 30)
  }
}

struct CompletionRequest: Encodable, Sendable {
  let minuteId: String
  let signature: String
  let completionKey: String
  let monotonicSeconds: Double
}

struct Balance: Decodable, Sendable {
  let pendingMicroUsd: Int?
  let availableMicroUsd: Int?
  let heldMicroUsd: Int?
  let paidMicroUsd: Int?
}

struct DeviceStatus: Decodable, Sendable {
  let earningActive: Bool?
  let payoutSetupRequired: Bool?
  let earningHoldReason: String?
  let balance: Balance?
  let minimumClientVersion: String?

  var allowsEarning: Bool {
    earningActive != false && payoutSetupRequired != true && earningHoldReason == nil
  }
}

struct CompletionResponse: Decodable, Sendable {
  let status: String
  let payable: Bool?
  let creditedMicroUsd: Int?
  let pendingUntil: Date?
  let balance: Balance?
}

struct PairingStartRequest: Encodable, Sendable {
  let deviceName: String
}

struct PairingStartResponse: Decodable, Sendable {
  let code: String
  let verificationUrl: URL
  let expiresInSeconds: Int
}

struct PairingExchangeRequest: Encodable, Sendable {
  let code: String
  let deviceName: String
  let devicePublicKey: String
  let deviceKeyProof: String
  let deviceCheckToken: String
}

struct PairingAccount: Decodable, Sendable {
  let displayName: String?
}

struct PairingExchangeResponse: Decodable, Sendable {
  let status: String
  let deviceId: String?
  let deviceToken: String?
  let account: PairingAccount?
}

struct DeviceCredentials: Sendable {
  let deviceId: String
  let token: String
}
