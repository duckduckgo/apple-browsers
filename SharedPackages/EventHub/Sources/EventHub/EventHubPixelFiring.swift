import Foundation

/// A fired telemetry pixel: the bare governed config name (e.g. `webTelemetry_adwalls_day`) with no
/// platform suffix — per the Tech Design, the platform-specific `EventHubPixelFiring` conformance is
/// responsible for the suffix (iOS `_ios_phone`/`_ios_tablet`, macOS `_macos`), not `EventHub` itself.
public struct FiredPixel: Equatable, Sendable {
    public let name: String
    public let parameters: [String: String]

    public init(name: String, parameters: [String: String]) {
        self.name = name
        self.parameters = parameters
    }
}

/// Injected pixel-firing seam. Both iOS and macOS app targets provide a `PixelKit`-based conformance
/// (out of scope for this package) that appends their platform suffix before firing.
public protocol EventHubPixelFiring {
    func enqueueFirePixel(named name: String, parameters: [String: String])
}
