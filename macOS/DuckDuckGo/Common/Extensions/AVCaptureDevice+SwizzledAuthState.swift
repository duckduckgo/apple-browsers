//
//  AVCaptureDevice+SwizzledAuthState.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import AVFoundation

extension AVCaptureDevice {
    private typealias AuthorizationStatusImplementation = @convention(c) (AnyClass, Selector, NSString) -> AVAuthorizationStatus

    private static var authorizationStatusForMediaType: ((AVMediaType, inout AVAuthorizationStatus) -> Void)?
    private static var authorizationStatusSwizzleID: UUID?
    private static var isSwizzled: Bool { authorizationStatusForMediaType != nil }

    private static let originalAuthorizationStatusForMediaType = {
        class_getClassMethod(AVCaptureDevice.self, #selector(authorizationStatus(for:)))
    }()
    private static let swizzledAuthorizationStatusForMediaType = {
        class_getClassMethod(AVCaptureDevice.self, #selector(swizzled_authorizationStatus(for:)))
    }()
    private static let systemAuthorizationStatusImplementation: AuthorizationStatusImplementation? = {
        guard let originalAuthorizationStatusForMediaType else { return nil }
        return unsafeBitCast(method_getImplementation(originalAuthorizationStatusForMediaType), to: AuthorizationStatusImplementation.self)
    }()

    @discardableResult
    static func swizzleAuthorizationStatusForMediaType(with replacement: @escaping ((AVMediaType, inout AVAuthorizationStatus) -> Void)) -> UUID? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !self.isSwizzled else { return nil }
        guard let originalAuthorizationStatusForMediaType = originalAuthorizationStatusForMediaType,
              let swizzledAuthorizationStatusForMediaType = swizzledAuthorizationStatusForMediaType,
              systemAuthorizationStatusImplementation != nil
        else {
            assertionFailure("Methods not available")
            return nil
        }

        method_exchangeImplementations(originalAuthorizationStatusForMediaType, swizzledAuthorizationStatusForMediaType)
        self.authorizationStatusForMediaType = replacement
        let identifier = UUID()
        authorizationStatusSwizzleID = identifier
        return identifier
    }

    static func restoreAuthorizationStatusForMediaType(ifMatching identifier: UUID? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard self.isSwizzled else { return }
        guard identifier == nil || identifier == authorizationStatusSwizzleID else { return }
        guard let originalAuthorizationStatusForMediaType = originalAuthorizationStatusForMediaType,
              let swizzledAuthorizationStatusForMediaType = swizzledAuthorizationStatusForMediaType
        else {
            assertionFailure("Methods not available")
            return
        }

        method_exchangeImplementations(originalAuthorizationStatusForMediaType, swizzledAuthorizationStatusForMediaType)
        self.authorizationStatusForMediaType = nil
        authorizationStatusSwizzleID = nil
    }

    /// App permission checks must read macOS's actual status while WebKit's preflight is intercepted.
    @objc dynamic
    static func systemAuthorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        guard let systemAuthorizationStatusImplementation else {
            assertionFailure("Authorization status implementation not available")
            return .denied
        }
        // Selector dispatch can race with restoring the hook; this implementation is captured before the first exchange.
        return systemAuthorizationStatusImplementation(self, #selector(authorizationStatus(for:)), mediaType.rawValue as NSString)
    }

    @objc dynamic private static func swizzled_authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        var result = systemAuthorizationStatus(for: mediaType)
        if Thread.isMainThread,
           let authorizationStatusForMediaType = Self.authorizationStatusForMediaType {
            authorizationStatusForMediaType(mediaType, &result)
        }
        return result
    }

}
