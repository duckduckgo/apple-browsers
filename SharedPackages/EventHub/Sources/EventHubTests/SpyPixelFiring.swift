import Foundation
@testable import EventHub

/// Test double for `EventHubPixelFiring`: records every fired pixel. `EventHubFixture` and
/// `EventHubFunctionalTests.Harness` expose this recording as `.fired`/`.count(of:)`.
final class SpyPixelFiring: EventHubPixelFiring {
    private(set) var fired: [FiredPixel] = []

    func enqueueFirePixel(named name: String, parameters: [String: String]) {
        fired.append(FiredPixel(name: name, parameters: parameters))
    }
}
