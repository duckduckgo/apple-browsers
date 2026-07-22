import Foundation

/// A single pixel parameter's runtime behavior. `CounterParameter` owns its counter value, the
/// stop-at-max-bucket logic, and its own per-tab dedup set (native/`.empty`-tab events are never
/// deduped). `DataParameter` owns only its last-seen value.
protocol Parameter: AnyObject {
    /// Processes an event whose source already matched this parameter's config source (or, for an
    /// immediate-trigger's data param, the triggering event itself). Returns `true` if state changed.
    @discardableResult
    func handle(data: [String: Any]?, tabID: EventHubTabID) -> Bool

    /// Clears this parameter's dedup entry for `tabID` if it navigated to a genuinely different URL.
    /// No-op for `DataParameter`.
    func onNavigationStarted(tabID: EventHubTabID)

    /// Clears this parameter's dedup entry for a closed tab. No-op for `DataParameter`.
    func onTabClosed(tabID: EventHubTabID)

    var state: ParamState { get }
    func restoreState(_ state: ParamState)

    /// The value to emit for this parameter when the owning pixel fires, or `nil` if this parameter
    /// has nothing to report (e.g. a counter with no matching bucket).
    func queryValue() -> String?
}

enum ParameterFactory {
    static func make(_ config: TelemetryParameterConfig) -> Parameter? {
        if config.isCounter, let buckets = config.buckets {
            return CounterParameter(buckets: buckets)
        }
        if config.isData {
            return DataParameter(dataKey: config.dataKey)
        }
        return nil
    }
}

final class CounterParameter: Parameter {
    private let buckets: BucketList
    private var value: Int
    private var stopCounting: Bool
    private var dedupSeen: Set<EventHubTabID> = []

    init(buckets: BucketList, initialState: ParamState = ParamState(value: 0)) {
        self.buckets = buckets
        self.value = initialState.value
        self.stopCounting = initialState.stopCounting
    }

    @discardableResult
    func handle(data: [String: Any]?, tabID: EventHubTabID) -> Bool {
        guard !stopCounting else { return false }
        // Native events (tabID == .empty) opt out of dedup: every call is a genuine occurrence.
        if tabID != .empty {
            guard dedupSeen.insert(tabID).inserted else { return false }
        }
        if BucketCounter.shouldStopCounting(value, buckets: buckets) {
            stopCounting = true
        } else {
            value += 1
        }
        return true
    }

    func onNavigationStarted(tabID: EventHubTabID) { dedupSeen.remove(tabID) }
    func onTabClosed(tabID: EventHubTabID) { dedupSeen.remove(tabID) }

    var state: ParamState { ParamState(value: value, stopCounting: stopCounting) }
    func restoreState(_ state: ParamState) { value = state.value; stopCounting = state.stopCounting }

    func queryValue() -> String? { BucketCounter.bucketCount(value, buckets: buckets) }
}

final class DataParameter: Parameter {
    /// RFC 3986 "unreserved" characters (alphanumerics plus `-._~`) are left unescaped; everything
    /// else — including `"`, `{`, `}`, `:`, and space — is percent-encoded. This matches the
    /// compact-JSON-then-percent-encode format the ported `EventHubDataParameterTests` expect once
    /// `DataParameter` is wired into `EventHub` (e.g. `"logged-in"` → `%22logged-in%22`,
    /// `{"a": true}` → `%7B%22a%22%3Atrue%7D`). `CharacterSet.alphanumerics` alone is not enough: it
    /// excludes `-`, which would wrongly turn `logged-in` into `logged%2Din`.
    private static let unreservedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    private let dataKey: String?
    private var lastValue: String?

    init(dataKey: String?, initialState: ParamState = ParamState(value: 0)) {
        self.dataKey = dataKey
        self.lastValue = initialState.lastDataValue
    }

    @discardableResult
    func handle(data: [String: Any]?, tabID: EventHubTabID) -> Bool {
        guard let dataKey, let data, let raw = data[dataKey] else { return false }
        guard let encoded = try? JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]),
              let compact = String(data: encoded, encoding: .utf8) else { return false }
        lastValue = compact.addingPercentEncoding(withAllowedCharacters: Self.unreservedCharacters)
        return true
    }

    func onNavigationStarted(tabID: EventHubTabID) {}
    func onTabClosed(tabID: EventHubTabID) {}

    var state: ParamState { ParamState(value: 0, lastDataValue: lastValue) }
    func restoreState(_ state: ParamState) { lastValue = state.lastDataValue }

    func queryValue() -> String? { lastValue }
}
