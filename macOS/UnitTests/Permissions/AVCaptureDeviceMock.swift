//
//  AVCaptureDeviceMock.swift
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

import AVFoundation
@testable import DuckDuckGo_Privacy_Browser

final class AVCaptureDeviceMock: AVCaptureDevice {

    static var authorizationStatuses: [AVMediaType: AVAuthorizationStatus]? {
        didSet {
            guard (oldValue == nil) != (authorizationStatuses == nil) else { return }
            // The app hook forwards to the system implementation, which now lives under the swizzled selector.
            _=AVCaptureDevice.authorizationStatusSwizzle
            method_exchangeImplementations(systemAuthorizationStatusForMediaType, mockedAuthorizationStatusForMediaType)
        }
    }

    private static let systemAuthorizationStatusForMediaType = {
        class_getClassMethod(AVCaptureDevice.self, #selector(swizzled_authorizationStatus(for:)))!
    }()
    private static let mockedAuthorizationStatusForMediaType = {
        class_getClassMethod(AVCaptureDevice.self, #selector(mocked_authorizationStatus(for:)))!
    }()

}

extension AVCaptureDevice {

    @objc
    static func mocked_authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        AVCaptureDeviceMock.authorizationStatuses?[mediaType] ?? .notDetermined
    }

}
