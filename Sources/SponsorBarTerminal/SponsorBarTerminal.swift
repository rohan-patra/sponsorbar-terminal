import Foundation

@main
struct SponsorBarTerminal {
  static func main() async {
    do {
      let configuration = try Configuration.parse(Array(CommandLine.arguments.dropFirst()))
      switch configuration.command {
      case .run:
        try await SponsorBarRunner(configuration: configuration).run()
      case .pair:
        try await PairingCoordinator(
          baseURL: Configuration.baseURL,
          keychain: KeychainStore(service: Configuration.keychainService)
        ).pair()
      }
    } catch ConfigurationError.helpRequested {
      print(Configuration.usage)
    } catch let error as ConfigurationError {
      fputs("Error: \(error.localizedDescription)\n\n", stderr)
      fputs(Configuration.usage + "\n", stderr)
      Foundation.exit(EXIT_FAILURE)
    } catch {
      fputs("Error: \(error.localizedDescription)\n", stderr)
      Foundation.exit(EXIT_FAILURE)
    }
  }
}
