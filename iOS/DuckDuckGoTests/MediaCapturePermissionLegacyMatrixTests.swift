//
//  MediaCapturePermissionLegacyMatrixTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import BrowserServicesKitTestsUtils
import ObjectiveC
import WebKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class TabViewControllerMediaCapturePermissionLegacyMatrixTests: XCTestCase {

    func testLegacyPermissionMatrix() throws {
        let sut = TabViewController.fake()

        try assertLegacyMatrix(fallthroughDecision: .prompt) { origin, frame, type, decisionHandler in
            sut.webView(sut.webView,
                        requestMediaCapturePermissionFor: origin,
                        initiatedByFrame: frame,
                        type: type,
                        decisionHandler: decisionHandler)
        }
    }
}

@MainActor
private func assertLegacyMatrix(
    fallthroughDecision: WKPermissionDecision,
    invoke: (WKSecurityOrigin, WKFrameInfo, WKMediaCaptureType, @escaping (WKPermissionDecision) -> Void) -> Void
) throws {
    for scenario in LegacyMediaCaptureScenario.matrix(fallthroughDecision: fallthroughDecision) {
        try AVCaptureAuthorizationStatusStub.withStatuses(audio: scenario.audioStatus, video: scenario.videoStatus) {
            var receivedDecision: WKPermissionDecision?
            let origin = MockWKSecurityOrigin.new(host: scenario.host)
            let frame = WKFrameInfo.mock(isMainFrame: true, securityOrigin: origin)

            invoke(origin, frame, scenario.type) { receivedDecision = $0 }

            XCTAssertEqual(receivedDecision, scenario.expectedDecision, scenario.name)
            XCTAssertEqual(AVCaptureAuthorizationStatusStub.requestedMediaTypes, scenario.expectedRequestedMediaTypes, scenario.name)
        }
    }
}

private struct LegacyMediaCaptureScenario {
    let name: String
    let host: String
    let type: WKMediaCaptureType
    let audioStatus: AVAuthorizationStatus
    let videoStatus: AVAuthorizationStatus
    let expectedDecision: WKPermissionDecision
    let expectedRequestedMediaTypes: [AVMediaType]

    static func matrix(fallthroughDecision: WKPermissionDecision) -> [Self] {
        let audioStatuses = [AVAuthorizationStatus.notDetermined, .restricted, .denied, .authorized]
        let captureTypes = [WKMediaCaptureType.microphone, .camera, .cameraAndMicrophone]
        let cartesianScenarios = ["example.com", "duck.ai"].flatMap { host in
            captureTypes.flatMap { type in
                audioStatuses.map { status in
                    let consultsAudio = host == "duck.ai" && type != .camera
                    return Self(name: "\(host) \(type) with audio status \(status)",
                                host: host,
                                type: type,
                                audioStatus: status,
                                videoStatus: .authorized,
                                expectedDecision: consultsAudio ? (status == .authorized ? .grant : .deny) : fallthroughDecision,
                                expectedRequestedMediaTypes: consultsAudio ? [.audio] : [])
                }
            }
        }

        return cartesianScenarios + [
            Self(name: "duckduckgo.com is a Duck.ai host",
                 host: "duckduckgo.com",
                 type: .microphone,
                 audioStatus: .authorized,
                 videoStatus: .authorized,
                 expectedDecision: .grant,
                 expectedRequestedMediaTypes: [.audio]),
            Self(name: "DuckDuckGo subdomain is a Duck.ai host",
                 host: "subdomain.duckduckgo.com",
                 type: .microphone,
                 audioStatus: .authorized,
                 videoStatus: .authorized,
                 expectedDecision: .grant,
                 expectedRequestedMediaTypes: [.audio]),
            Self(name: "combined capture ignores denied video authorization",
                 host: "duck.ai",
                 type: .cameraAndMicrophone,
                 audioStatus: .authorized,
                 videoStatus: .denied,
                 expectedDecision: .grant,
                 expectedRequestedMediaTypes: [.audio])
        ]
    }
}

private enum AVCaptureAuthorizationStatusStub {
    nonisolated(unsafe) private static var statuses: [AVMediaType: AVAuthorizationStatus] = [:]
    nonisolated(unsafe) private(set) static var requestedMediaTypes: [AVMediaType] = []

    static func withStatuses(audio: AVAuthorizationStatus, video: AVAuthorizationStatus, perform: () -> Void) throws {
        statuses = [.audio: audio, .video: video]
        requestedMediaTypes = []

        let originalMethod = try XCTUnwrap(class_getClassMethod(
            AVCaptureDevice.self,
            #selector(AVCaptureDevice.authorizationStatus(for:))
        ))
        let stubMethod = try XCTUnwrap(class_getClassMethod(
            AVCaptureDevice.self,
            #selector(AVCaptureDevice.osp_authorizationStatus(for:))
        ))

        method_exchangeImplementations(originalMethod, stubMethod)
        defer {
            method_exchangeImplementations(stubMethod, originalMethod)
            statuses = [:]
            requestedMediaTypes = []
        }

        perform()
    }

    static func status(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        requestedMediaTypes.append(mediaType)
        return statuses[mediaType] ?? .notDetermined
    }
}

private extension AVCaptureDevice {
    @objc class func osp_authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        AVCaptureAuthorizationStatusStub.status(for: mediaType)
    }
}
