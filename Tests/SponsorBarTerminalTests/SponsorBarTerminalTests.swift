import Foundation
import Testing

@testable import SponsorBarTerminal

@Test func requestCanonicalizationMatchesCapturedProtocol() {
  let canonical = DeviceProofStore.requestCanonicalString(
    method: "post",
    target: "/api/v1/delivery/lease",
    timestamp: "1711234567890",
    nonce: "F47AC10B-58CC-4372-A567-0E02B2C3D479",
    body: Data("{}".utf8)
  )

  #expect(
    canonical == """
      sponsorbar-device-request-v1
      POST
      /api/v1/delivery/lease
      1711234567890
      f47ac10b-58cc-4372-a567-0e02b2c3d479
      44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a
      """)
}

@Test func requestTargetPreservesEncodedQuery() throws {
  let url = try #require(
    URL(string: "https://sponsorbar.io/api/v1/device/status?timeZone=America%2FNew_York"))
  #expect(
    DeviceProofStore.requestTarget(url)
      == "/api/v1/device/status?timeZone=America%2FNew_York"
  )
}

@Test func pairingCanonicalizationHashesTokenText() {
  let canonical = DeviceProofStore.pairingCanonicalString(
    code: "AB12CD34",
    deviceName: "Test Mac",
    publicKey: "PUBLIC",
    deviceCheckToken: "TOKEN"
  )
  #expect(
    canonical == """
      sponsorbar-device-pairing-v1
      AB12CD34
      Test Mac
      PUBLIC
      f98103e9217f099208569d295c1b276f1821348636c268c854bb2a086e0037cd
      """)
}

@Test func requestBodiesUseCapturedCamelCaseKeys() throws {
  let envelope = EligibilityEnvelope(
    deviceId: "device",
    sessionId: "session",
    appVersion: "1.0.11",
    locale: "en_US",
    country: "US",
    displayClass: "standard",
    awake: true,
    unlocked: true,
    activeWithinSeconds: 0,
    statusItemRendered: true,
    geometryValid: true,
    occlusionVisible: true,
    menuBarPresented: true,
    monotonicSeconds: 42,
    previousCampaignId: nil,
    runCompletedMinutes: nil
  )
  let envelopeKeys = try jsonKeys(JSONEncoder().encode(envelope))
  #expect(envelopeKeys.contains("deviceId"))
  #expect(envelopeKeys.contains("activeWithinSeconds"))
  #expect(envelopeKeys.contains("statusItemRendered"))
  #expect(!envelopeKeys.contains("device_id"))

  let completion = CompletionRequest(
    minuteId: "minute",
    signature: "signature",
    completionKey: "key",
    monotonicSeconds: 43
  )
  #expect(
    try jsonKeys(JSONEncoder().encode(completion)) == [
      "minuteId", "signature", "completionKey", "monotonicSeconds",
    ])
}

@Test func deliveryResponsesDefaultMissingFields() throws {
  let decoder = JSONDecoder()
  decoder.keyDecodingStrategy = .convertFromSnakeCase
  let idle = try decoder.decode(
    DeliveryResponse.self,
    from: Data(#"{"status":"idle"}"#.utf8)
  )
  #expect(idle.reasons.isEmpty)
  #expect(idle.retryAfterSeconds == 30)

  let ineligible = try decoder.decode(
    DeliveryResponse.self,
    from: Data(#"{"status":"ineligible"}"#.utf8)
  )
  #expect(ineligible.retryAfterSeconds == 15)
}

@Test func creativeDecodesCapturedNames() throws {
  let data = Data(
    """
    {
      "id": "creative-1",
      "companyName": "Acme",
      "slogan": "Build faster",
      "destinationUrl": "https://example.com",
      "logoUrl": "https://example.com/logo.png",
      "backgroundColor": "#000000",
      "foregroundColor": "#ffffff",
      "sloganColor": "#cccccc"
    }
    """.utf8)
  let creative = try JSONDecoder().decode(Creative.self, from: data)
  #expect(creative.companyName == "Acme")
  #expect(creative.backgroundColor == "#000000")
  #expect(creative.sloganColor == "#cccccc")
}

@Test func configurationExposesOnlyProductionModes() throws {
  let continuous = try Configuration.parse([])
  #expect(continuous.command == .run)
  #expect(!continuous.once)

  let once = try Configuration.parse(["--once"])
  #expect(once.once)
  let pairing = try Configuration.parse(["--pair"])
  #expect(pairing.command == .pair)
  #expect(Configuration.baseURL.absoluteString == "https://sponsorbar.io")

  #expect(throws: ConfigurationError.unknownArgument("--production")) {
    try Configuration.parse(["--production"])
  }
  #expect(throws: ConfigurationError.unknownArgument("--base-url")) {
    try Configuration.parse(["--base-url"])
  }
}

private func jsonKeys(_ data: Data) throws -> Set<String> {
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  return Set(object.keys)
}

@Test func rendererRejectsExpiredLeaseAndCompletesShortVisibleInterval() async throws {
  let renderer = TerminalRenderer(outputIsTTY: true)
  let shutdown = ShutdownController()
  let expired = testLease(expiresAt: Date().addingTimeInterval(-1))
  #expect(
    try await renderer.display(
      lease: expired,
      shutdown: shutdown,
      duration: .milliseconds(5)
    ) == .insufficientWindow)

  let valid = testLease(expiresAt: Date().addingTimeInterval(1))
  #expect(
    try await renderer.display(
      lease: valid,
      shutdown: shutdown,
      duration: .milliseconds(5)
    ) == .completed)
}

private func testLease(expiresAt: Date) -> CreativeLease {
  CreativeLease(
    runId: "run",
    minuteId: "minute",
    campaignId: "campaign",
    creative: Creative(companyName: "Acme", slogan: "Build faster"),
    startedAt: Date(),
    minuteExpiresAt: expiresAt,
    runTargetMinutes: 1,
    signature: "signature"
  )
}
