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
import Common
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

    func testWhenLastTabReferenceIsReleasedOnBackgroundQueueThenDeinitRunsOnMainThread() async {
        let didDeinit = expectation(description: "Tab deinitializes on the main thread")
        let retainedTab: Unmanaged<TabViewController> = autoreleasepool {
            let tab = makeSUT()
            // The fake error-page handler retains its delegate, unlike the production handler.
            tab.specialErrorPageNavigationHandler.delegate = nil
            tab.onDeinit {
                XCTAssertTrue(Thread.isMainThread)
                didDeinit.fulfill()
            }
            return .passRetained(tab)
        }

        DispatchQueue.global().async {
            XCTAssertFalse(Thread.isMainThread)
            retainedTab.release()
        }

        await fulfillment(of: [didDeinit], timeout: 3)
    }

    func testFlagOnRoutesOrdinaryCaptureTypesUsingCommittedTopLevelSite() async {
        let scenarios: [(WKMediaCaptureType, Set<SitePermissionType>)] = [
            (.camera, [.camera]),
            (.microphone, [.microphone]),
            (.cameraAndMicrophone, [.camera, .microphone])
        ]

        for (captureType, expectedPermissionTypes) in scenarios {
            let sut = makeSUT()
            var receivedPrompt: SitePermissionPrompt?
            sut.sitePermissionsPromptHandlerOverride = { prompt, completion in
                receivedPrompt = prompt
                completion(.denyOnce)
            }

            let decision = await requestPermissionThroughBridge(on: sut,
                                                                originHost: "top-level.example",
                                                                captureType: captureType)

            XCTAssertEqual(receivedPrompt?.site.host, "top-level.example", "capture type: \(captureType)")
            XCTAssertEqual(receivedPrompt?.permissionTypes, expectedPermissionTypes, "capture type: \(captureType)")
            XCTAssertEqual(decision, .deny, "capture type: \(captureType)")
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

    func testFlagOffInstallsBridgeBeforeContentBlockingAssetsAndHandlesLaterActivation() async {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        // The fake's content-blocking publisher never emits assets.
        let sut = makeSUT(featureFlagger: featureFlagger)
        let scripts = sut.webView.configuration.userContentController.userScripts
        let expectedSource = MediaCaptureUserScript().makeWKUserScriptSync().source
        let mediaCaptureScripts = scripts.filter { $0.source == expectedSource }
        XCTAssertEqual(mediaCaptureScripts.count, 1)
        XCTAssertEqual(mediaCaptureScripts.first?.injectionTime, .atDocumentStart)
        XCTAssertEqual(mediaCaptureScripts.first?.isForMainFrameOnly, false)

        let disabledDecision = await requestPermissionThroughBridge(on: sut,
                                                                     originHost: "top-level.example",
                                                                     captureType: .camera)
        XCTAssertEqual(disabledDecision, .bypass)

        featureFlagger.enabledFeatureFlags = [.sitePermissions]
        featureFlagger.triggerUpdate()
        var didPrompt = false
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            didPrompt = true
            completion(.allowOnce)
        }
        let enabledDecision = await requestPermissionThroughBridge(on: sut,
                                                                    originHost: "top-level.example",
                                                                    captureType: .camera)
        XCTAssertTrue(didPrompt)
        XCTAssertEqual(enabledDecision, .allow)
    }

    func testFlagOnRejectsBridgeRequestBeforeMainFrameCommit() async {
        let sut = makeSUT(hasCommittedMainFrame: false)
        var didPrompt = false
        sut.sitePermissionsPromptHandlerOverride = { _, _ in
            didPrompt = true
        }

        let decision = await requestPermissionThroughBridge(on: sut,
                                                            originHost: "top-level.example",
                                                            captureType: .camera)

        XCTAssertEqual(decision, .deny)
        XCTAssertFalse(didPrompt)
    }

    func testBridgeRejectsUntrustedFrameOriginsWithoutPrompting() async {
        let untrustedOrigins = [
            URL(string: "http://top-level.example")!,
            URL(string: "https://subdomain.top-level.example")!,
            URL(string: "https://top-level.example:444")!,
            URL(string: "https://cross-site.example")!,
            URL(string: "about:blank")!
        ]

        for originURL in untrustedOrigins {
            let sut = makeSUT()
            var didPrompt = false
            sut.sitePermissionsPromptHandlerOverride = { _, completion in
                didPrompt = true
                completion(.denyOnce)
            }

            let decision = await requestPermissionThroughBridge(on: sut,
                                                                originURL: originURL,
                                                                captureType: .camera)

            XCTAssertEqual(decision, .deny, "origin: \(originURL)")
            XCTAssertFalse(didPrompt, "origin: \(originURL)")
        }
    }

    func testBridgeAllowsPotentiallyTrustworthyHTTPOriginsWhenTheyMatchTopLevel() async {
        let origins = [
            URL(string: "http://localhost")!,
            URL(string: "http://subdomain.localhost:8080")!,
            URL(string: "http://127.42.0.1")!,
            URL(string: "http://[::1]")!
        ]

        for originURL in origins {
            let sut = makeSUT(committedURL: originURL)
            var receivedPrompt: SitePermissionPrompt?
            sut.sitePermissionsPromptHandlerOverride = { prompt, completion in
                receivedPrompt = prompt
                completion(.denyOnce)
            }

            let decision = await requestPermissionThroughBridge(on: sut,
                                                                originURL: originURL,
                                                                captureType: .camera)

            XCTAssertEqual(decision, .deny, "origin: \(originURL)")
            XCTAssertEqual(receivedPrompt?.site.host, originURL.host, "origin: \(originURL)")
        }
    }

    func testMainFramePermissionsPolicyHeaderDeniesBeforePrompt() async {
        let sut = makeSUT()
        var didPrompt = false
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            didPrompt = true
            completion(.denyOnce)
        }
        sut.webView(sut.webView, didStartProvisionalNavigation: nil)
        let response = HTTPURLResponse(
            url: URL(string: "https://top-level.example/path")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Permissions-Policy": "camera=(), microphone=(self)"]
        )!
        sut.captureSitePermissionsMediaPolicy(from: response, isForMainFrame: true)
        sut.webView(sut.webView, didCommit: nil)

        let decision = await requestPermissionThroughBridge(on: sut,
                                                            originHost: "top-level.example",
                                                            captureType: .camera)

        XCTAssertEqual(decision, .deny)
        XCTAssertFalse(didPrompt)
    }

    func testFlagOffDismissesPendingPromptAndDrainsBridgeExactlyOnce() async {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions])
        let sut = makeSUT(featureFlagger: featureFlagger)
        let userScript = MediaCaptureUserScript()
        sut.configureSitePermissionsMediaCapture(with: userScript)
        var promptCompletion: ((SitePermissionPromptDecision) -> Void)?
        let promptExpectation = expectation(description: "Site prompt presented")
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            promptCompletion = completion
            promptExpectation.fulfill()
        }
        let requestID = "0123456789abcdef0123456789abcdef:1"
        let originalRequest = makeBridgeRequestTask(on: sut,
                                                    originHost: "top-level.example",
                                                    captureType: .camera,
                                                    requestID: requestID)
        await fulfillment(of: [promptExpectation], timeout: 1)

        featureFlagger.enabledFeatureFlags = []
        featureFlagger.triggerUpdate()
        let originalDecision = await originalRequest.value
        XCTAssertEqual(originalDecision, .bypass)

        promptCompletion?(.denyOnce)
        let flagOffDecision = await requestPermissionThroughBridge(on: sut,
                                                                   originHost: "top-level.example",
                                                                   captureType: .camera)
        XCTAssertEqual(flagOffDecision, .bypass)
        XCTAssertTrue(userScript.delegate === sut)

        featureFlagger.enabledFeatureFlags = [.sitePermissions]
        featureFlagger.triggerUpdate()
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            completion(.denyOnce)
        }
        let replayDecision = await makeBridgeRequestTask(on: sut,
                                                         originHost: "top-level.example",
                                                         captureType: .camera,
                                                         requestID: requestID).value
        XCTAssertEqual(replayDecision, .deny)
    }

    func testFlagOffRetainsExistingDocumentHandlerAcrossNavigationForBackForwardCache() async {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions])
        let sut = makeSUT(featureFlagger: featureFlagger)
        var userScript: MediaCaptureUserScript? = MediaCaptureUserScript()
        weak var retainedUserScript = userScript
        sut.configureSitePermissionsMediaCapture(with: userScript)

        featureFlagger.enabledFeatureFlags = []
        sut.configureSitePermissionsMediaCapture(with: nil)
        userScript = nil
        XCTAssertNotNil(retainedUserScript)
        XCTAssertTrue(retainedUserScript?.delegate === sut)

        sut.webView(sut.webView, didStartProvisionalNavigation: nil)
        sut.webView(sut.webView,
                    didFailProvisionalNavigation: nil,
                    withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost))
        XCTAssertNotNil(retainedUserScript)

        sut.webView(sut.webView, didStartProvisionalNavigation: nil)
        sut.webView(sut.webView, didCommit: nil)
        XCTAssertNotNil(retainedUserScript)
        XCTAssertTrue(retainedUserScript?.delegate === sut)

        sut.closeSitePermissions()
        XCTAssertNil(retainedUserScript)
    }

    func testWebContentProcessTerminationRetainsHandlerForReinjectedNewDocument() async throws {
        let sut = makeSUT()
        var userScript: MediaCaptureUserScript? = MediaCaptureUserScript()
        weak var retainedUserScript = userScript
        sut.configureSitePermissionsMediaCapture(with: userScript)
        userScript = nil

        sut.webViewWebContentProcessDidTerminate(sut.webView)
        sut.webView(sut.webView, didCommit: nil)

        let installedScript = try XCTUnwrap(retainedUserScript)
        let delegate = try XCTUnwrap(installedScript.delegate)
        var didPrompt = false
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            didPrompt = true
            completion(.denyOnce)
        }
        let originURL = URL(string: "https://top-level.example/frame")!
        let origin = MockWKSecurityOrigin.new(url: originURL)
        let frame = WKFrameInfo.mock(isMainFrame: false,
                                     securityOrigin: origin,
                                     webView: sut.webView,
                                     request: URLRequest(url: originURL))
        let decision = await delegate.mediaCaptureUserScript(
            installedScript,
            requestPermissionFor: [.camera],
            requestID: "0123456789abcdef0123456789abcdef:1",
            in: frame,
            webView: sut.webView
        )

        XCTAssertTrue(didPrompt)
        XCTAssertEqual(decision, .deny)
    }

    func testFlagTurningOffWhilePromptIsVisiblePreservesUserDenial() async {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions])
        let sut = makeSUT(featureFlagger: featureFlagger)
        var promptCompletion: ((SitePermissionPromptDecision) -> Void)?
        let promptExpectation = expectation(description: "Site prompt presented")
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            promptCompletion = completion
            promptExpectation.fulfill()
        }
        let request = makeBridgeRequestTask(on: sut,
                                            originHost: "top-level.example",
                                            captureType: .camera)
        await fulfillment(of: [promptExpectation], timeout: 1)

        featureFlagger.enabledFeatureFlags = []
        promptCompletion?(.denyOnce)
        let decision = await request.value

        XCTAssertEqual(decision, .deny)
    }

    func testNavigationDrainsPendingRequestExactlyOnceAndIgnoresStaleCallbacks() async {
        let sut = makeSUT()
        var promptCompletion: ((SitePermissionPromptDecision) -> Void)?
        let promptExpectation = expectation(description: "Site prompt presented")
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            promptCompletion = completion
            promptExpectation.fulfill()
        }

        let request = makeBridgeRequestTask(on: sut,
                                            originHost: "top-level.example",
                                            captureType: .camera)
        await fulfillment(of: [promptExpectation], timeout: 1)

        sut.webView(WKWebView(), didStartProvisionalNavigation: nil)

        sut.webView(sut.webView, didStartProvisionalNavigation: nil)
        let decision = await request.value
        XCTAssertEqual(decision, .deny)

        promptCompletion?(.allowOnce)
    }

    func testFailedProvisionalNavigationReenablesRequestsForCommittedPage() async {
        let sut = makeSUT()
        var didPrompt = false
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            didPrompt = true
            completion(.denyOnce)
        }

        sut.webView(sut.webView, didStartProvisionalNavigation: nil)
        let provisionalDecision = await requestPermissionThroughBridge(on: sut,
                                                                        originHost: "top-level.example",
                                                                        captureType: .camera)
        XCTAssertEqual(provisionalDecision, .deny)
        XCTAssertFalse(didPrompt)

        let downloadHandoffError = NSError(domain: "WebKitErrorDomain", code: 102)
        sut.webView(sut.webView,
                    didFailProvisionalNavigation: nil,
                    withError: downloadHandoffError)
        let decision = await requestPermissionThroughBridge(on: sut,
                                                            originHost: "top-level.example",
                                                            captureType: .camera)

        XCTAssertTrue(didPrompt)
        XCTAssertEqual(decision, .deny)
    }

    func testStaleProvisionalFailureDoesNotReenableRequestsDuringNewerNavigation() async throws {
        let sut = makeSUT()
        let navigationWebView = WKWebView()
        let firstNavigation = try XCTUnwrap(navigationWebView.load(URLRequest(url: URL(string: "https://first.example")!)))
        let secondNavigation = try XCTUnwrap(navigationWebView.load(URLRequest(url: URL(string: "https://second.example")!)))
        var didPrompt = false
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
        let staleFailureDecision = await requestPermissionThroughBridge(on: sut,
                                                                        originHost: "top-level.example",
                                                                        captureType: .camera)
        XCTAssertEqual(staleFailureDecision, .deny)
        XCTAssertFalse(didPrompt)

        sut.webView(sut.webView,
                    didFailProvisionalNavigation: secondNavigation,
                    withError: downloadHandoffError)
        let decision = await requestPermissionThroughBridge(on: sut,
                                                            originHost: "top-level.example",
                                                            captureType: .camera)

        XCTAssertTrue(didPrompt)
        XCTAssertEqual(decision, .deny)
        navigationWebView.stopLoading()
    }

    func testClosingTabDrainsPendingRequestExactlyOnceAndRejectsLaterRequests() async {
        let sut = makeSUT()
        var promptCompletion: ((SitePermissionPromptDecision) -> Void)?
        let promptExpectation = expectation(description: "Site prompt presented")
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            promptCompletion = completion
            promptExpectation.fulfill()
        }

        let request = makeBridgeRequestTask(on: sut,
                                            originHost: "top-level.example",
                                            captureType: .microphone)
        await fulfillment(of: [promptExpectation], timeout: 1)

        sut.closeSitePermissions()
        let decision = await request.value
        XCTAssertEqual(decision, .deny)

        promptCompletion?(.allowOnce)

        let laterDecision = await requestPermissionThroughBridge(on: sut,
                                                                 originHost: "top-level.example",
                                                                 captureType: .microphone)
        XCTAssertEqual(laterDecision, .deny)
    }

    func testTabDismissalKeepsPendingRequestInItsPerTabFIFO() async {
        let sut = makeSUT()
        var promptCompletion: ((SitePermissionPromptDecision) -> Void)?
        let promptExpectation = expectation(description: "Site prompt presented")
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            promptCompletion = completion
            promptExpectation.fulfill()
        }

        let request = makeBridgeRequestTask(on: sut,
                                            originHost: "top-level.example",
                                            captureType: .camera)
        await fulfillment(of: [promptExpectation], timeout: 1)

        sut.dismiss()

        promptCompletion?(.denyOnce)
        let decision = await request.value
        XCTAssertEqual(decision, .deny)
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
                          originHost: "top-level.example",
                          captureType: .camera,
                          decisionHandler: { decisions.append($0) })

        XCTAssertEqual(decisions, [.deny])
        XCTAssertFalse(didRequestDependencies)
    }

    func testPermissionDialogFiresImpressionAndClickEventsAndRoutesSelectedAction() async throws {
        var events = [SitePermissionsEvent]()
        var decisions = [WKPermissionDecision]()
        let decisionExpectation = expectation(description: "WebKit permission resolved")
        let promptExpectation = expectation(description: "Site prompt presented")
        let sut = makeSUT(eventHandler: { event in
            events.append(event)
            if event == .permissionDialogImpression(type: .camera) {
                promptExpectation.fulfill()
            }
        })

        let bridgeRequest = makeBridgeRequestTask(on: sut,
                                                  originHost: "top-level.example",
                                                  captureType: .camera)
        await fulfillment(of: [promptExpectation], timeout: 1)

        XCTAssertEqual(events, [.permissionDialogImpression(type: .camera)])
        XCTAssertTrue(decisions.isEmpty)

        let dialog = try XCTUnwrap(sut.children.compactMap {
            ($0 as? UIHostingController<SitePermissionDialogView>)?.rootView
        }.first)
        dialog.onAction(.allowOnce)

        let bridgeDecision = await bridgeRequest.value
        XCTAssertEqual(bridgeDecision, .allow)
        requestPermission(on: sut,
                          originHost: "top-level.example",
                          captureType: .camera,
                          decisionHandler: {
                              decisions.append($0)
                              decisionExpectation.fulfill()
                          })
        await fulfillment(of: [decisionExpectation], timeout: 1)
        XCTAssertEqual(decisions, [.grant])
        XCTAssertEqual(events, [
            .permissionDialogImpression(type: .camera),
            .permissionDialogClick(type: .camera, selection: .allowOnce)
        ])
    }

    func testPreexistingSystemDenialRejectsBridgeRequestAndSettingsActionUsesInjectedOpener() async throws {
        var events = [SitePermissionsEvent]()
        var settingsOpenCount = 0
        let promptExpectation = expectation(description: "Site prompt presented")
        let reminderExpectation = expectation(description: "Case B reminder shown")
        let sut = makeSUT(systemAuthorizationStatus: .denied, eventHandler: { event in
            events.append(event)
            if event == .permissionDialogImpression(type: .camera) {
                promptExpectation.fulfill()
            }
            if event == .permissionReminderDialog(type: .camera, action: .shown) {
                reminderExpectation.fulfill()
            }
        })
        sut.sitePermissionsSystemSettingsOpenerOverride = {
            settingsOpenCount += 1
        }

        let bridgeRequest = makeBridgeRequestTask(on: sut,
                                                  originHost: "top-level.example",
                                                  captureType: .camera)
        await fulfillment(of: [promptExpectation], timeout: 1)

        let dialog = try XCTUnwrap(sut.children.compactMap {
            ($0 as? UIHostingController<SitePermissionDialogView>)?.rootView
        }.first)
        dialog.onAction(.allowWhileUsingSite)

        let bridgeDecision = await bridgeRequest.value
        XCTAssertEqual(bridgeDecision, .deny)
        await fulfillment(of: [reminderExpectation], timeout: 1)
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

    func testWhenNavigationReplacesFadingToastWithReminderThenCancelDismissesReminder() async throws {
        let originalWindow = UIApplication.shared.firstKeyWindow
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            originalWindow?.makeKey()
        }

        let authorizationState = AVAuthorizationStateBox(status: .notDetermined)
        let sut = makeSUT(
            avAuthorizationStatus: { _ in authorizationState.status },
            avRequestAccess: { _, completion in
                authorizationState.status = .denied
                completion(false)
            }
        )
        defer { sut.closeSitePermissions() }
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            completion(.allowWhileUsingSite)
        }
        let firstDecision = await requestPermissionThroughBridge(on: sut,
                                                                 originHost: "top-level.example",
                                                                 captureType: .camera)
        XCTAssertEqual(firstDecision, .deny)
        let toast = try XCTUnwrap(window.subviews.compactMap { $0 as? ActionMessageView }.first)

        sut.webView(sut.webView, didStartProvisionalNavigation: nil)
        sut.webView(sut.webView,
                    didFailProvisionalNavigation: nil,
                    withError: NSError(domain: "WebKitErrorDomain", code: 102))

        let frame = WKFrameInfo.mock(isMainFrame: true,
                                     securityOrigin: MockWKSecurityOrigin.new(host: "top-level.example"),
                                     webView: sut.webView,
                                     request: URLRequest(url: URL(string: "https://top-level.example/path")!))
        // Stored Allow resolves synchronously, so the new reminder overlaps the old toast's fade.
        let secondDecision = await sut.mediaCaptureUserScript(
            MediaCaptureUserScript(),
            requestPermissionFor: [.camera],
            requestID: "0123456789abcdef0123456789abcdef:2",
            in: frame,
            webView: sut.webView
        )
        XCTAssertEqual(secondDecision, .deny)
        XCTAssertNotNil(toast.superview)
        let reminder = try XCTUnwrap(sut.children.compactMap {
            ($0 as? UIHostingController<PermissionReminderDialogView>)?.rootView
        }.first)
        reminder.onAction(.cancel)

        XCTAssertFalse(sut.children.contains { $0 is UIHostingController<PermissionReminderDialogView> })
    }

    func testSitePromptPrecedesSystemPromptAndPreapprovalIsConsumedOnce() async {
        enum TimelineEntry: Equatable {
            case sitePrompt
            case systemPrompt
        }

        let authorizationState = AVAuthorizationStateBox(status: .notDetermined)
        var timeline = [TimelineEntry]()
        var promptCompletion: ((SitePermissionPromptDecision) -> Void)?
        let promptExpectation = expectation(description: "Site prompt presented")
        let sut = makeSUT(
            avAuthorizationStatus: { _ in authorizationState.status },
            avRequestAccess: { _, completion in
                timeline.append(.systemPrompt)
                authorizationState.status = .authorized
                completion(true)
            }
        )
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            timeline.append(.sitePrompt)
            promptCompletion = completion
            promptExpectation.fulfill()
        }

        let bridgeRequest = makeBridgeRequestTask(on: sut,
                                                  originHost: "top-level.example",
                                                  captureType: .camera)
        await fulfillment(of: [promptExpectation], timeout: 1)
        XCTAssertEqual(timeline, [.sitePrompt])

        promptCompletion?(.allowOnce)
        let bridgeDecision = await bridgeRequest.value

        XCTAssertEqual(bridgeDecision, .allow)
        XCTAssertEqual(timeline, [.sitePrompt, .systemPrompt])

        var decisions = [WKPermissionDecision]()
        requestPermission(on: sut,
                          originHost: "top-level.example",
                          captureType: .camera,
                          decisionHandler: { decisions.append($0) })
        requestPermission(on: sut,
                          originHost: "top-level.example",
                          captureType: .camera,
                          decisionHandler: { decisions.append($0) })

        XCTAssertEqual(decisions, [.grant, .deny])
    }

    func testPreapprovalIsBoundToTrustedFrameOriginAndCaptureType() async {
        let sut = makeSUT()
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            completion(.allowOnce)
        }

        let bridgeDecision = await requestPermissionThroughBridge(on: sut,
                                                                  originHost: "top-level.example",
                                                                  captureType: .camera)
        XCTAssertEqual(bridgeDecision, .allow)

        var decisions = [WKPermissionDecision]()
        requestPermission(on: sut,
                          originHost: "other-frame.example",
                          captureType: .camera,
                          decisionHandler: { decisions.append($0) })
        requestPermission(on: sut,
                          originHost: "top-level.example",
                          captureType: .microphone,
                          decisionHandler: { decisions.append($0) })
        requestPermission(on: sut,
                          originHost: "top-level.example",
                          captureType: .camera,
                          decisionHandler: { decisions.append($0) })

        XCTAssertEqual(decisions, [.deny, .deny, .grant])
    }

    func testMainFramePreapprovalCannotBeConsumedBySameOriginSubframe() async {
        let sut = makeSUT()
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            completion(.allowOnce)
        }

        let bridgeDecision = await makeBridgeRequestTask(on: sut,
                                                         originHost: "top-level.example",
                                                         captureType: .camera,
                                                         isMainFrame: true).value
        XCTAssertEqual(bridgeDecision, .allow)

        var decisions = [WKPermissionDecision]()
        requestPermission(on: sut,
                          originHost: "top-level.example",
                          captureType: .camera,
                          isMainFrame: false,
                          decisionHandler: { decisions.append($0) })
        requestPermission(on: sut,
                          originHost: "top-level.example",
                          captureType: .camera,
                          isMainFrame: true,
                          decisionHandler: { decisions.append($0) })

        XCTAssertEqual(decisions, [.deny, .grant])
    }

    func testUnusedPreapprovalExpiresBeforeNativeDelegateCanConsumeIt() async {
        var uptime: TimeInterval = 100
        let sut = makeSUT()
        sut.sitePermissionsUptimeProvider = { uptime }
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            completion(.allowOnce)
        }

        let bridgeDecision = await requestPermissionThroughBridge(on: sut,
                                                                  originHost: "top-level.example",
                                                                  captureType: .camera)
        XCTAssertEqual(bridgeDecision, .allow)
        uptime += 6

        var decisions = [WKPermissionDecision]()
        requestPermission(on: sut,
                          originHost: "top-level.example",
                          captureType: .camera,
                          decisionHandler: { decisions.append($0) })

        XCTAssertEqual(decisions, [.deny])
    }

    private func makeSUT(featureEnabled: Bool = true,
                         featureFlagger providedFeatureFlagger: MockFeatureFlagger? = nil,
                         hasCommittedMainFrame: Bool = true,
                         committedURL: URL = URL(string: "https://top-level.example/path")!,
                         systemAuthorizationStatus: AVAuthorizationStatus = .authorized,
                         avAuthorizationStatus: ((AVMediaType) -> AVAuthorizationStatus)? = nil,
                         avRequestAccess: ((AVMediaType, @escaping @Sendable (Bool) -> Void) -> Void)? = nil,
                         eventHandler: @escaping (SitePermissionsEvent) -> Void = { _ in }) -> TabViewController {
        let featureFlagger = providedFeatureFlagger
            ?? MockFeatureFlagger(enabledFeatureFlags: featureEnabled ? [.sitePermissions] : [])
        let sut = TabViewController.fake(
            customWebView: { SitePermissionURLWebView(url: committedURL, configuration: $0) },
            featureFlagger: featureFlagger
        )
        let dependencies = SitePermissionsDependencies(
            store: SitePermissionsStore(storage: InMemoryKeyValueStore().keyedStoring()),
            systemPermissionClient: SystemPermissionClient(
                locationManager: CLLocationManager(),
                locationServicesEnabled: { false },
                avAuthorizationStatus: avAuthorizationStatus ?? { _ in systemAuthorizationStatus },
                avRequestAccess: avRequestAccess ?? { _, completion in completion(true) },
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

    private func requestPermissionThroughBridge(on sut: TabViewController,
                                                originHost: String,
                                                captureType: WKMediaCaptureType) async -> MediaCaptureBridgeDecision {
        await makeBridgeRequestTask(on: sut,
                                    originHost: originHost,
                                    captureType: captureType).value
    }

    private func requestPermissionThroughBridge(on sut: TabViewController,
                                                originURL: URL,
                                                captureType: WKMediaCaptureType) async -> MediaCaptureBridgeDecision {
        await makeBridgeRequestTask(on: sut,
                                    originURL: originURL,
                                    captureType: captureType).value
    }

    private func makeBridgeRequestTask(on sut: TabViewController,
                                       webView: WKWebView? = nil,
                                       originHost: String,
                                       captureType: WKMediaCaptureType,
                                       requestID: String? = nil,
                                       isMainFrame: Bool = false) -> Task<MediaCaptureBridgeDecision, Never> {
        makeBridgeRequestTask(on: sut,
                              webView: webView,
                              originURL: URL(string: "https://\(originHost)/frame")!,
                              captureType: captureType,
                              requestID: requestID,
                              isMainFrame: isMainFrame)
    }

    private func makeBridgeRequestTask(on sut: TabViewController,
                                       webView: WKWebView? = nil,
                                       originURL: URL,
                                       captureType: WKMediaCaptureType,
                                       requestID: String? = nil,
                                       isMainFrame: Bool = false) -> Task<MediaCaptureBridgeDecision, Never> {
        let targetWebView = webView ?? sut.webView!
        let origin = MockWKSecurityOrigin.new(url: originURL)
        let frame = WKFrameInfo.mock(isMainFrame: isMainFrame,
                                     securityOrigin: origin,
                                     webView: targetWebView,
                                     request: URLRequest(url: originURL))
        let permissionTypes: Set<SitePermissionType>
        switch captureType {
        case .camera:
            permissionTypes = [.camera]
        case .microphone:
            permissionTypes = [.microphone]
        case .cameraAndMicrophone:
            permissionTypes = [.camera, .microphone]
        @unknown default:
            permissionTypes = []
        }
        let requestID = requestID ?? UUID().uuidString.replacingOccurrences(of: "-", with: "") + ":1"
        return Task { @MainActor in
            await sut.mediaCaptureUserScript(MediaCaptureUserScript(),
                                             requestPermissionFor: permissionTypes,
                                             requestID: requestID,
                                             in: frame,
                                             webView: targetWebView)
        }
    }

    private func requestPermission(on sut: TabViewController,
                                   webView: WKWebView? = nil,
                                   originHost: String,
                                   captureType: WKMediaCaptureType,
                                   isMainFrame: Bool = false,
                                   decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let targetWebView = webView ?? sut.webView!
        let origin = MockWKSecurityOrigin.new(host: originHost)
        let frame = WKFrameInfo.mock(isMainFrame: isMainFrame,
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

private final class AVAuthorizationStateBox: @unchecked Sendable {
    var status: AVAuthorizationStatus

    init(status: AVAuthorizationStatus) {
        self.status = status
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
