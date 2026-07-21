import Foundation

/// Computes a pixel's `attributionPeriod`: the start of the interval (of length `periodSeconds`)
/// containing a given period-start timestamp, expressed as UTC epoch seconds.
public enum EventHubAttribution {
    /// Rounds `periodStartMillis` (UTC epoch milliseconds) down to the start of the interval of length
    /// `periodSeconds`, returning UTC epoch seconds: `floor((periodStartMillis / 1000) / periodSeconds) * periodSeconds`.
    public static func startOfIntervalSeconds(periodStartMillis: Int64, periodSeconds: Int64) -> Int64 {
        periodStartMillis / 1000 / periodSeconds * periodSeconds
    }
}
