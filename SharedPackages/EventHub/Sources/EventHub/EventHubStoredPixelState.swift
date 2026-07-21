import Foundation

/// The serialised, persisted form of a single pixel's runtime state. The repository keeps a map of
/// these (keyed by pixel name) under one composite key in the key-value store. Mirrors the fields
/// Android/Windows persist per row: the period window, the params JSON, and a config-snapshot JSON.
public struct EventHubStoredPixelState: Codable, Equatable, Sendable {
    public let periodStartMillis: Int64
    public let periodEndMillis: Int64
    public let paramsJSON: String
    public let configJSON: String

    public init(periodStartMillis: Int64, periodEndMillis: Int64, paramsJSON: String, configJSON: String) {
        self.periodStartMillis = periodStartMillis
        self.periodEndMillis = periodEndMillis
        self.paramsJSON = paramsJSON
        self.configJSON = configJSON
    }
}
