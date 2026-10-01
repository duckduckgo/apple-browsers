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
            switch (oldValue, authorizationStatuses) {
            case (.none, .some), (.some, .none):
                // Capture the real system implementation before installing either mock.
                if oldValue == nil {
                    _ = AVCaptureDevice.systemAuthorizationStatus(for: .audio)
                }
                method_exchangeImplementations(originalAuthorizationStatusForMediaType,
                                               swizzledAuthorizationStatusForMediaType)
                method_exchangeImplementations(originalSystemAuthorizationStatusForMediaType,
                                               swizzledSystemAuthorizationStatusForMediaType)
            default:
                break
            }
        }
    }

    private static let originalAuthorizationStatusForMediaType = {
        class_getClassMethod(AVCaptureDevice.self, #selector(authorizationStatus(for:)))!
    }()
    private static let swizzledAuthorizationStatusForMediaType = {
        class_getClassMethod(AVCaptureDevice.self, #selector(mocked_authorizationStatus(for:)))!
    }()

    private static let originalSystemAuthorizationStatusForMediaType = {
        class_getClassMethod(AVCaptureDevice.self, #selector(systemAuthorizationStatus(for:)))!
    }()
    private static let swizzledSystemAuthorizationStatusForMediaType = {
        class_getClassMethod(AVCaptureDevice.self, #selector(mocked_systemAuthorizationStatus(for:)))!
    }()

}

extension AVCaptureDevice {

    @objc
    static func mocked_authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        AVCaptureDeviceMock.authorizationStatuses?[mediaType] ?? .notDetermined
    }

    @objc
    static func mocked_systemAuthorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        AVCaptureDeviceMock.authorizationStatuses?[mediaType] ?? .notDetermined
    }

}
