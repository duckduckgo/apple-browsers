import Foundation
import ObjectiveC.runtime
import WebKit

// MARK: - WebKit teardown stability for tests
//
// Some WebKit types are not intended to be user-instantiated/subclassed, but our tests sometimes do.
// On macOS, WebKit can crash during teardown when deallocating those objects (e.g. `WKFrameInfo`).
//
// Swizzling `dealloc` to a no-op is consistent with other WebKit test swizzles used in this codebase.

extension WKFrameInfo {

    private static var isSwizzled = false
    private static let originalDealloc = { class_getInstanceMethod(WKFrameInfo.self, NSSelectorFromString("dealloc"))! }()
    private static let swizzledDealloc = { class_getInstanceMethod(WKFrameInfo.self, #selector(swizzled_dealloc))! }()

    static func swizzleDealloc() {
        guard !self.isSwizzled else { return }
        self.isSwizzled = true
        method_exchangeImplementations(originalDealloc, swizzledDealloc)
    }

    @objc
    func swizzled_dealloc() { }
}

