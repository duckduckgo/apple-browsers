//
//  MediaCapturePermissionRoutingTests.swift
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
import CoreLocation
import ObjectiveC
@_spi(Testing) import Persistence
@testable import SitePermissions
import SwiftUI
import WebKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class TabViewControllerMediaCapturePermissionRoutingTests: XCTestCase {

    func testFlagOnRoutesOrdinaryCaptureTypesUsingCommittedTopLevelSite() {
        let scenarios: [(WKMediaCaptureType, Set<SitePermissionType>)] = [
            (.camera, [.camera]),
            (.microphone, [.microphone]),
            (.cameraAndMicrophone, [.camera, .microphone])
        ]

        for (captureType, expectedPermissionTypes) in scenarios {
            let sut = makeSUT()
            var receivedPrompt: SitePermissionPrompt?
            var decisions = [WKPermissionDecision]()
            sut.sitePermissionsPromptHandlerOverride = { prompt, completion in
                receivedPrompt = prompt
                completion(.denyOnce)
            }

            requestPermission(on: sut,
                              originHost: "requesting-frame.example",
                              captureType: captureType,
                              decisionHandler: { decisions.append($0) })

            XCTAssertEqual(receivedPrompt?.site.host, "top-level.example", "capture type: \(captureType)")
            XCTAssertEqual(receivedPrompt?.permissionTypes, expectedPermissionTypes, "capture type: \(captureType)")
            XCTAssertEqual(decisions, [.deny], "capture type: \(captureType)")
        }
    }

    func testFlagOnPreservesDuckAIHostMatrixWithoutConstructingCoordinator() throws {
        let sut = makeSUT()
        var didRequestDependencies = false
        sut.sitePermissionsDependenciesProvider = {
            didRequestDependencies = true
            return nil
        }

        let hosts = ["duck.ai", "duckduckgo.com", "subdomain.duckduckgo.com"]
        let captureTypes = [WKMediaCaptureType.camera, .microphone, .cameraAndMicrophone]
        let audioStatuses = [AVAuthorizationStatus.notDetermined, .restricted, .denied, .authorized]

        for host in hosts {
            for captureType in captureTypes {
                for audioStatus in audioStatuses {
                    try Phase3AVCaptureAuthorizationStatusStub.withAudioStatus(audioStatus) {
                        var decisions = [WKPermissionDecision]()

                        requestPermission(on: sut,
                                          originHost: host,
                                          captureType: captureType,
                                          decisionHandler: { decisions.append($0) })

                        let consultsAudio = captureType != .camera
                        let expectedDecision: WKPermissionDecision = consultsAudio && audioStatus == .authorized
                            ? .grant
                            : (consultsAudio ? .deny : .prompt)
                        let expectedMediaTypes: [AVMediaType] = consultsAudio ? [.audio] : []
                        let message = "\(host) \(captureType) with audio status \(audioStatus)"
                        XCTAssertEqual(decisions, [expectedDecision], message)
                        XCTAssertEqual(Phase3AVCaptureAuthorizationStatusStub.requestedMediaTypes, expectedMediaTypes, message)
                    }
                }
            }
        }

        XCTAssertFalse(didRequestDependencies)
    }

    func testFlagOffPreservesLegacyRoutingForReplacedWebView() throws {
        let sut = makeSUT(featureEnabled: false)
        let staleWebView = WKWebView()
        var decisions = [WKPermissionDecision]()

        requestPermission(on: sut,
                          webView: staleWebView,
                          originHost: "ordinary.example",
                          captureType: .camera,
                          decisionHandler: { decisions.append($0) })

        try Phase3AVCaptureAuthorizationStatusStub.withAudioStatus(.authorized) {
            requestPermission(on: sut,
                              webView: staleWebView,
                              originHost: "duck.ai",
                              captureType: .microphone,
                              decisionHandler: { decisions.append($0) })
        }

        XCTAssertEqual(decisions, [.prompt, .grant])
    }

    func testFlagOnRejectsRequestBeforeMainFrameCommit() {
        let sut = makeSUT(hasCommittedMainFrame: false)
        var didPrompt = false
        var decisions = [WKPermissionDecision]()
        sut.sitePermissionsPromptHandlerOverride = { _, _ in
            didPrompt = true
        }

        requestPermission(on: sut,
                          originHost: "requesting-frame.example",
                          captureType: .camera,
                          decisionHandler: { decisions.append($0) })

        XCTAssertEqual(decisions, [.deny])
        XCTAssertFalse(didPrompt)
    }

    func testNavigationDrainsPendingRequestExactlyOnceAndIgnoresStaleCallbacks() {
        let sut = makeSUT()
        var promptCompletion: ((SitePermissionPromptDecision) -> Void)?
        var decisions = [WKPermissionDecision]()
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            promptCompletion = completion
        }

        requestPermission(on: sut,
                          originHost: "requesting-frame.example",
                          captureType: .camera,
                          decisionHandler: { decisions.append($0) })
        XCTAssertTrue(decisions.isEmpty)

        sut.webView(WKWebView(), didStartProvisionalNavigation: nil)
        XCTAssertTrue(decisions.isEmpty)

        sut.webView(sut.webView, didStartProvisionalNavigation: nil)
        XCTAssertEqual(decisions, [.deny])

        promptCompletion?(.allowOnce)
        XCTAssertEqual(decisions, [.deny])
    }

    func testFailedProvisionalNavigationReenablesRequestsForCommittedPage() {
        let sut = makeSUT()
        var didPrompt = false
        var decisions = [WKPermissionDecision]()
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            didPrompt = true
            completion(.denyOnce)
        }

        sut.webView(sut.webView, didStartProvisionalNavigation: nil)
        requestPermission(on: sut,
                          originHost: "requesting-frame.example",
                          captureType: .camera,
                          decisionHandler: { decisions.append($0) })
        XCTAssertEqual(decisions, [.deny])
        XCTAssertFalse(didPrompt)

        let downloadHandoffError = NSError(domain: "WebKitErrorDomain", code: 102)
        sut.webView(sut.webView,
                    didFailProvisionalNavigation: nil,
                    withError: downloadHandoffError)
        requestPermission(on: sut,
                          originHost: "requesting-frame.example",
                          captureType: .camera,
                          decisionHandler: { decisions.append($0) })

        XCTAssertTrue(didPrompt)
        XCTAssertEqual(decisions, [.deny, .deny])
    }

    func testStaleProvisionalFailureDoesNotReenableRequestsDuringNewerNavigation() throws {
        let sut = makeSUT()
        let navigationWebView = WKWebView()
        let firstNavigation = try XCTUnwrap(navigationWebView.load(URLRequest(url: URL(string: "https://first.example")!)))
        let secondNavigation = try XCTUnwrap(navigationWebView.load(URLRequest(url: URL(string: "https://second.example")!)))
        var didPrompt = false
        var decisions = [WKPermissionDecision]()
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            didPrompt = true
            completion(.denyOnce)
        }

        sut.webView(sut.webView, didStartProvisionalNavigation: firstNavigation)
        sut.webView(sut.webView, didStartProvisionalNavigation: secondNavigation)

        let downloadHandoffError = NSError(domain: "WebKitErrorDomain", code: 102)
        sut.webView(sut.webView,
                    didFailProvisionalNavigation: firstNavigation,
                    withError: downloadHandoffError)
        requestPermission(on: sut,
                          originHost: "requesting-frame.example",
                          captureType: .camera,
                          decisionHandler: { decisions.append($0) })
        XCTAssertEqual(decisions, [.deny])
        XCTAssertFalse(didPrompt)

        sut.webView(sut.webView,
                    didFailProvisionalNavigation: secondNavigation,
                    withError: downloadHandoffError)
        requestPermission(on: sut,
                          originHost: "requesting-frame.example",
                          captureType: .camera,
                          decisionHandler: { decisions.append($0) })

        XCTAssertTrue(didPrompt)
        XCTAssertEqual(decisions, [.deny, .deny])
        navigationWebView.stopLoading()
    }

    func testClosingTabDrainsPendingRequestExactlyOnceAndRejectsLaterRequests() {
        let sut = makeSUT()
        var promptCompletion: ((SitePermissionPromptDecision) -> Void)?
        var decisions = [WKPermissionDecision]()
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            promptCompletion = completion
        }

        requestPermission(on: sut,
                          originHost: "requesting-frame.example",
                          captureType: .microphone,
                          decisionHandler: { decisions.append($0) })
        XCTAssertTrue(decisions.isEmpty)

        sut.closeSitePermissions()
        XCTAssertEqual(decisions, [.deny])

        promptCompletion?(.allowOnce)
        XCTAssertEqual(decisions, [.deny])

        requestPermission(on: sut,
                          originHost: "requesting-frame.example",
                          captureType: .microphone,
                          decisionHandler: { decisions.append($0) })
        XCTAssertEqual(decisions, [.deny, .deny])
    }

    func testTabDismissalKeepsPendingRequestInItsPerTabFIFO() {
        let sut = makeSUT()
        var promptCompletion: ((SitePermissionPromptDecision) -> Void)?
        var decisions = [WKPermissionDecision]()
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            promptCompletion = completion
        }

        requestPermission(on: sut,
                          originHost: "requesting-frame.example",
                          captureType: .camera,
                          decisionHandler: { decisions.append($0) })

        sut.dismiss()
        XCTAssertTrue(decisions.isEmpty)

        promptCompletion?(.denyOnce)
        XCTAssertEqual(decisions, [.deny])
    }

    func testRequestFromReplacedWebViewIsDeniedWithoutConstructingCoordinator() {
        let sut = makeSUT()
        let staleWebView = WKWebView()
        let origin = MockWKSecurityOrigin.new(host: "requesting-frame.example")
        let frame = WKFrameInfo.mock(isMainFrame: true, securityOrigin: origin, webView: staleWebView)
        var didRequestDependencies = false
        var decisions = [WKPermissionDecision]()
        sut.sitePermissionsDependenciesProvider = {
            didRequestDependencies = true
            return nil
        }

        sut.webView(staleWebView,
                    requestMediaCapturePermissionFor: origin,
                    initiatedByFrame: frame,
                    type: .camera,
                    decisionHandler: { decisions.append($0) })

        XCTAssertEqual(decisions, [.deny])
        XCTAssertFalse(didRequestDependencies)
    }

    func testLinkPreviewRequestIsDeniedWithoutConstructingCoordinator() {
        let sut = makeSUT()
        sut.isLinkPreview = true
        var didRequestDependencies = false
        var decisions = [WKPermissionDecision]()
        sut.sitePermissionsDependenciesProvider = {
            didRequestDependencies = true
            return nil
        }

        requestPermission(on: sut,
                          originHost: "requesting-frame.example",
                          captureType: .camera,
                          decisionHandler: { decisions.append($0) })

        XCTAssertEqual(decisions, [.deny])
        XCTAssertFalse(didRequestDependencies)
    }

    func testPermissionDialogFiresImpressionAndClickEventsAndRoutesSelectedAction() async throws {
        var events = [SitePermissionsEvent]()
        var decisions = [WKPermissionDecision]()
        let decisionExpectation = expectation(description: "WebKit permission resolved")
        let sut = makeSUT(eventHandler: { events.append($0) })

        requestPermission(on: sut,
                          originHost: "requesting-frame.example",
                          captureType: .camera,
                          decisionHandler: {
                              decisions.append($0)
                              decisionExpectation.fulfill()
                          })

        XCTAssertEqual(events, [.permissionDialogImpression(type: .camera)])
        XCTAssertTrue(decisions.isEmpty)

        let dialog = try XCTUnwrap(sut.children.compactMap {
            ($0 as? UIHostingController<SitePermissionDialogView>)?.rootView
        }.first)
        dialog.onAction(.allowOnce)

        await fulfillment(of: [decisionExpectation], timeout: 1)
        XCTAssertEqual(decisions, [.grant])
        XCTAssertEqual(events, [
            .permissionDialogImpression(type: .camera),
            .permissionDialogClick(type: .camera, selection: .allowOnce)
        ])
    }

    func testPreexistingSystemDenialResolvesWebKitBeforeReminderAndSettingsActionUsesInjectedOpener() async throws {
        enum TimelineEntry: Equatable {
            case webKitDenied
            case reminderShown
        }

        var events = [SitePermissionsEvent]()
        var timeline = [TimelineEntry]()
        var settingsOpenCount = 0
        let reminderExpectation = expectation(description: "Case B reminder shown")
        let sut = makeSUT(systemAuthorizationStatus: .denied, eventHandler: { event in
            events.append(event)
            if event == .permissionReminderDialog(type: .camera, action: .shown) {
                timeline.append(.reminderShown)
                reminderExpectation.fulfill()
            }
        })
        sut.sitePermissionsSystemSettingsOpenerOverride = {
            settingsOpenCount += 1
        }

        requestPermission(on: sut,
                          originHost: "requesting-frame.example",
                          captureType: .camera,
                          decisionHandler: { decision in
                              XCTAssertEqual(decision, .deny)
                              timeline.append(.webKitDenied)
                          })

        let dialog = try XCTUnwrap(sut.children.compactMap {
            ($0 as? UIHostingController<SitePermissionDialogView>)?.rootView
        }.first)
        dialog.onAction(.allowWhileUsingSite)

        await fulfillment(of: [reminderExpectation], timeout: 1)
        XCTAssertEqual(timeline, [.webKitDenied, .reminderShown])
        XCTAssertEqual(events, [
            .permissionDialogImpression(type: .camera),
            .permissionDialogClick(type: .camera, selection: .allowAlways),
            .permissionReminderDialog(type: .camera, action: .shown)
        ])

        let reminder = try XCTUnwrap(sut.children.compactMap {
            ($0 as? UIHostingController<PermissionReminderDialogView>)?.rootView
        }.first)
        reminder.onAction(.changePermissions)

        XCTAssertEqual(settingsOpenCount, 1)
        XCTAssertEqual(events, [
            .permissionDialogImpression(type: .camera),
            .permissionDialogClick(type: .camera, selection: .allowAlways),
            .permissionReminderDialog(type: .camera, action: .shown),
            .permissionReminderDialog(type: .camera, action: .settings),
            .permissionSystemSettingsOpened(type: .camera)
        ])
        XCTAssertFalse(sut.children.contains { $0 is UIHostingController<PermissionReminderDialogView> })
    }

    private func makeSUT(featureEnabled: Bool = true,
                         hasCommittedMainFrame: Bool = true,
                         systemAuthorizationStatus: AVAuthorizationStatus = .authorized,
                         eventHandler: @escaping (SitePermissionsEvent) -> Void = { _ in }) -> TabViewController {
        let committedURL = URL(string: "https://top-level.example/path")!
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: featureEnabled ? [.sitePermissions] : [])
        let sut = TabViewController.fake(
            customWebView: { SitePermissionURLWebView(url: committedURL, configuration: $0) },
            featureFlagger: featureFlagger
        )
        let dependencies = SitePermissionsDependencies(
            store: SitePermissionsStore(storage: InMemoryKeyValueStore().keyedStoring()),
            systemPermissionClient: SystemPermissionClient(
                locationManager: CLLocationManager(),
                locationServicesEnabled: { false },
                avAuthorizationStatus: { _ in systemAuthorizationStatus },
                avRequestAccess: { _, completion in completion(true) },
                notificationCenter: NotificationCenter()
            ),
            eventHandler: eventHandler
        )
        sut.sitePermissionsDependenciesProvider = { dependencies }
        if hasCommittedMainFrame {
            sut.webView(sut.webView, didCommit: nil)
        }
        return sut
    }

    private func requestPermission(on sut: TabViewController,
                                   webView: WKWebView? = nil,
                                   originHost: String,
                                   captureType: WKMediaCaptureType,
                                   decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let targetWebView = webView ?? sut.webView!
        let origin = MockWKSecurityOrigin.new(host: originHost)
        let frame = WKFrameInfo.mock(isMainFrame: false,
                                     securityOrigin: origin,
                                     webView: targetWebView,
                                     request: URLRequest(url: URL(string: "https://\(originHost)/frame")!))
        sut.webView(targetWebView,
                    requestMediaCapturePermissionFor: origin,
                    initiatedByFrame: frame,
                    type: captureType,
                    decisionHandler: decisionHandler)
    }
}

private enum Phase3AVCaptureAuthorizationStatusStub {
    nonisolated(unsafe) private static var audioStatus = AVAuthorizationStatus.notDetermined
    nonisolated(unsafe) private(set) static var requestedMediaTypes = [AVMediaType]()

    static func withAudioStatus(_ status: AVAuthorizationStatus, perform: () -> Void) throws {
        audioStatus = status
        requestedMediaTypes = []

        let originalMethod = try XCTUnwrap(class_getClassMethod(
            AVCaptureDevice.self,
            #selector(AVCaptureDevice.authorizationStatus(for:))
        ))
        let stubMethod = try XCTUnwrap(class_getClassMethod(
            AVCaptureDevice.self,
            #selector(AVCaptureDevice.osp_phase3AuthorizationStatus(for:))
        ))

        method_exchangeImplementations(originalMethod, stubMethod)
        defer {
            method_exchangeImplementations(stubMethod, originalMethod)
            audioStatus = .notDetermined
            requestedMediaTypes = []
        }

        perform()
    }

    static func status(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        requestedMediaTypes.append(mediaType)
        return mediaType == .audio ? audioStatus : .denied
    }
}

private extension AVCaptureDevice {
    @objc class func osp_phase3AuthorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        Phase3AVCaptureAuthorizationStatusStub.status(for: mediaType)
    }
}

private final class SitePermissionURLWebView: WKWebView {
    private let fixedURL: URL

    init(url: URL, configuration: WKWebViewConfiguration) {
        fixedURL = url
        super.init(frame: .zero, configuration: configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var url: URL? {
        fixedURL
    }
}
