import Foundation

actor APIClient {
  private let baseURL: URL
  private let credentials: DeviceCredentials
  private let proof: DeviceProofStore
  private let session: URLSession
  private let encoder: JSONEncoder

  init(
    baseURL: URL,
    credentials: DeviceCredentials,
    proof: DeviceProofStore,
    session: URLSession = .shared
  ) {
    self.baseURL = baseURL
    self.credentials = credentials
    self.proof = proof
    self.session = session
    encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
  }

  func fetchStatus(timeZone: String) async throws -> DeviceStatus {
    var components = URLComponents(
      url: endpoint("/api/v1/device/status"),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = [URLQueryItem(name: "timeZone", value: timeZone)]
    guard let url = components?.url else { throw APIError.invalidURL }
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.httpMethod = "GET"
    try authorize(&request)
    let data = try await perform(request)
    return try Self.decoder.decode(DeviceStatus.self, from: data)
  }

  func lease(_ envelope: EligibilityEnvelope) async throws -> DeliveryResponse {
    try await post("/api/v1/delivery/lease", body: envelope)
  }

  func complete(_ completion: CompletionRequest) async throws -> CompletionResponse {
    try await post("/api/v1/delivery/complete", body: completion)
  }

  private func post<T: Encodable, R: Decodable>(_ path: String, body: T) async throws -> R {
    var request = URLRequest(url: endpoint(path), timeoutInterval: 20)
    request.httpMethod = "POST"
    request.httpBody = try encoder.encode(body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    try authorize(&request)
    let data = try await perform(request)
    return try Self.decoder.decode(R.self, from: data)
  }

  private func authorize(_ request: inout URLRequest) throws {
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
    try proof.sign(&request)
  }

  private func perform(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw APIError.nonHTTPResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      let decoded = String(data: data, encoding: .utf8) ?? "<non-UTF-8 body>"
      throw APIError.http(status: http.statusCode, body: String(decoded.prefix(500)))
    }
    return data
  }

  private func endpoint(_ path: String) -> URL {
    baseURL.appendingPathComponent(
      path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    )
  }

  nonisolated private static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      if let date = try? Date(value, strategy: .iso8601) { return date }
      if let date = try? Date(
        value,
        strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
      ) {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid ISO-8601 date: \(value)"
      )
    }
    return decoder
  }
}

enum APIError: LocalizedError {
  case invalidURL
  case nonHTTPResponse
  case http(status: Int, body: String)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Could not construct the SponsorBar API URL."
    case .nonHTTPResponse:
      return "SponsorBar returned a non-HTTP response."
    case .http(let status, let body):
      return "SponsorBar returned HTTP \(status): \(body)"
    }
  }
}
