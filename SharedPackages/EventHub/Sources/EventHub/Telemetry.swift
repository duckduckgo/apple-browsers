import Foundation

/// One configured pixel's period window, config snapshot (frozen at period start so a mid-period
/// config change never mutates a running period), and its parameters.
public final class Telemetry {
    public let name: String
    public private(set) var config: TelemetryPixelConfig
    public private(set) var periodStartMillis: Int64
    public private(set) var periodEndMillis: Int64
    private var parameters: [String: Parameter]

    /// Starts a fresh period from `config`, beginning at `periodStartMillis`.
    public init(config: TelemetryPixelConfig, periodStartMillis: Int64) {
        self.name = config.name
        self.config = config
        self.periodStartMillis = periodStartMillis
        self.periodEndMillis = periodStartMillis + (config.trigger.period?.periodSeconds ?? 0) * 1000
        self.parameters = config.parameters.compactMapValues { ParameterFactory.make($0) }
    }

    /// Rehydrates from persisted state (restart / foreground catch-up).
    public init(restoring persisted: PixelState) {
        self.name = persisted.pixelName
        self.config = persisted.config
        self.periodStartMillis = persisted.periodStartMillis
        self.periodEndMillis = persisted.periodEndMillis
        self.parameters = persisted.config.parameters.compactMapValues { ParameterFactory.make($0) }
        for (paramName, parameter) in parameters {
            if let restored = persisted.params[paramName] {
                parameter.restoreState(restored)
            }
        }
    }

    public func isElapsed(atMillis now: Int64) -> Bool { now >= periodEndMillis }

    /// Routes a matching event to every parameter whose config `source` equals `source`. Returns
    /// `true` if any parameter's state changed.
    @discardableResult
    public func handleEvent(source: String, data: [String: Any]?, tabID: EventHubTabID) -> Bool {
        var changed = false
        for (paramName, paramConfig) in config.parameters where paramConfig.source == source {
            guard let parameter = parameters[paramName] else { continue }
            if parameter.handle(data: data, tabID: tabID) { changed = true }
        }
        return changed
    }

    public func onNavigationStarted(tabID: EventHubTabID) {
        for parameter in parameters.values { parameter.onNavigationStarted(tabID: tabID) }
    }

    public func onTabClosed(tabID: EventHubTabID) {
        for parameter in parameters.values { parameter.onTabClosed(tabID: tabID) }
    }

    public func snapshot() -> PixelState {
        PixelState(pixelName: name, periodStartMillis: periodStartMillis, periodEndMillis: periodEndMillis,
                    config: config, params: parameters.mapValues(\.state))
    }

    /// The query parameters to emit for this pixel, or `nil` if nothing meaningful was measured
    /// (e.g. no counter matched a bucket and no data parameter has a value).
    public func buildPixelParameters() -> [String: String]? {
        var result: [String: String] = [:]
        for (paramName, parameter) in parameters {
            if let value = parameter.queryValue() { result[paramName] = value }
        }
        return result.isEmpty ? nil : result
    }
}
