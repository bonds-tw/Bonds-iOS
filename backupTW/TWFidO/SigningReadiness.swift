import Foundation

/// Acceptance flags, not a promise that the external certificate provider is healthy.
struct SigningReadiness: Decodable {
    let version: Int
    let start_enabled: Bool
    let poll_enabled: Bool
    let transports: [String]

    func accepts(_ transport: TWFidOTransport) -> Bool {
        version == 1 && start_enabled && poll_enabled && transports.contains(transport.rawValue)
    }

}
