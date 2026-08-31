//
//  SitePermissionsCoordinatorTests.swift
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

import Foundation
@_spi(Testing) import Persistence
import WebKit
import XCTest
@testable import SitePermissions

@MainActor
final class SitePermissionsCoordinatorTests: XCTestCase {

    func testCaptureStateMapsWebKitStates() {
        XCTAssertEqual(SitePermissionCaptureState(.none), .inactive)
        XCTAssertEqual(SitePermissionCaptureState(.active), .active)
        XCTAssertEqual(SitePermissionCaptureState(.muted), .paused)
    }

    func testWhenStoredDenyExistsThenItWinsWithoutPrompting() throws {
        let harness = try Harness()
        harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
        harness.store.setPersistentDecision(.deny, for: .microphone, at: harness.site)
        var didPrompt = false
        var resolution: SitePermissionResolution?

        harness.coordinator.request(harness.request([.camera, .microphone]), promptHandler: { _, _ in
            didPrompt = true
        }, completion: { resolution = $0 })

        XCTAssertEqual(resolution, .deny(systemBlocks: []))
        XCTAssertFalse(didPrompt)
    }

    func testWhenStoredAllowExistsUnderGlobalNeverThenItStillGrants() throws {
        let harness = try Harness()
        harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
        harness.store.setGlobalDefault(.deny, for: .camera)
        var resolution: SitePermissionResolution?

        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
            XCTFail("Stored Allow must not prompt")
        }, completion: { resolution = $0 })

        XCTAssertEqual(resolution, .grant)
    }

    func testWhenExplicitAskAndNoGlobalDenyExistThenRequestPrompts() throws {
        let harness = try Harness()
        harness.store.resetDecision(for: .camera, at: harness.site)
        var receivedPrompt: SitePermissionPrompt?

        harness.coordinator.request(harness.request([.camera]), promptHandler: { prompt, _ in
            receivedPrompt = prompt
        }, completion: { _ in })

        XCTAssertEqual(receivedPrompt, SitePermissionPrompt(site: harness.site, permissionTypes: [.camera]))
    }

    func testWhenGlobalNeverAppliesToUnresolvedTypeThenCombinedRequestDeclinesSilently() throws {
        let harness = try Harness()
        harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
        harness.store.setGlobalDefault(.deny, for: .microphone)
        var didPrompt = false
        var resolution: SitePermissionResolution?

        harness.coordinator.request(harness.request([.camera, .microphone]), promptHandler: { _, _ in
            didPrompt = true
        }, completion: { resolution = $0 })

        XCTAssertEqual(resolution, .deny(systemBlocks: []))
        XCTAssertFalse(didPrompt)
    }

    func testPermissionQueryMatchesNextRequestAcrossStoredGlobalAndSystemPrecedence() async throws {
        struct Scenario {
            let stored: SitePermissionDecision?
            let global: GlobalSitePermissionDecision
            let system: SystemPermissionAuthorizationState
            let queryState: SitePermissionQueryState
            let expectsPrompt: Bool
            let resolution: SitePermissionResolution
        }
        let scenarios = [
            Scenario(stored: nil, global: .ask, system: .authorized,
                     queryState: .prompt, expectsPrompt: true, resolution: .grant),
            Scenario(stored: .ask, global: .ask, system: .authorized,
                     queryState: .prompt, expectsPrompt: true, resolution: .grant),
            Scenario(stored: nil, global: .deny, system: .authorized,
                     queryState: .denied, expectsPrompt: false, resolution: .deny(systemBlocks: [])),
            Scenario(stored: .deny, global: .ask, system: .authorized,
                     queryState: .denied, expectsPrompt: false, resolution: .deny(systemBlocks: [])),
            Scenario(stored: .allow, global: .deny, system: .authorized,
                     queryState: .granted, expectsPrompt: false, resolution: .grant),
            Scenario(stored: .allow, global: .ask, system: .notDetermined,
                     queryState: .denied, expectsPrompt: false,
                     resolution: .deny(systemBlocks: [.init(permissionType: .location,
                                                              state: .notDetermined,
                                                              timing: .preexisting)])),
            Scenario(stored: .allow, global: .ask, system: .denied,
                     queryState: .denied, expectsPrompt: false,
                     resolution: .deny(systemBlocks: [.init(permissionType: .location,
                                                              state: .denied,
                                                              timing: .preexisting)])),
            Scenario(stored: .allow, global: .ask, system: .restricted,
                     queryState: .denied, expectsPrompt: false,
                     resolution: .deny(systemBlocks: [.init(permissionType: .location,
                                                              state: .restricted,
                                                              timing: .preexisting)])),
            Scenario(stored: .allow, global: .ask, system: .unavailable,
                     queryState: .denied, expectsPrompt: false,
                     resolution: .deny(systemBlocks: [.init(permissionType: .location,
                                                              state: .unavailable,
                                                              timing: .preexisting)]))
        ]

        for scenario in scenarios {
            let harness = try Harness()
            harness.store.setGlobalDefault(scenario.global, for: .location)
            switch scenario.stored {
            case .ask?:
                harness.store.resetDecision(for: .location, at: harness.site)
            case let decision?:
                harness.store.setPersistentDecision(decision, for: .location, at: harness.site)
            case nil:
                break
            }
            harness.systemStates[.location] = scenario.system

            XCTAssertEqual(
                harness.coordinator.queryState(for: .location, context: harness.context),
                scenario.queryState
            )

            var didPrompt = false
            let requestCompleted = expectation(description: "Request matching \(scenario.queryState) query completes")
            harness.coordinator.request(harness.request([.location]), promptHandler: { _, respond in
                didPrompt = true
                respond(.allowOnce)
            }, completion: { resolution in
                XCTAssertEqual(resolution, scenario.resolution)
                requestCompleted.fulfill()
            })

            await fulfillment(of: [requestCompleted], timeout: 1)
            XCTAssertEqual(didPrompt, scenario.expectsPrompt)
        }
    }

    func testPermissionQueryTransitionTableCoversEverySourceAndSystemState() async throws {
        enum SourceState: CaseIterable, Equatable {
            case noDecision
            case storedAsk
            case storedAllow
            case storedDeny
            case globalNever
            case allowOnce
            case denyOnce
        }

        let systemStates: [SystemPermissionAuthorizationState] = [
            .notDetermined,
            .authorized,
            .denied,
            .restricted,
            .unavailable
        ]
        for sourceState in SourceState.allCases {
            for systemState in systemStates {
                let harness = try Harness()
                switch sourceState {
                case .noDecision:
                    break
                case .storedAsk:
                    harness.store.resetDecision(for: .location, at: harness.site)
                case .storedAllow:
                    harness.store.setPersistentDecision(.allow, for: .location, at: harness.site)
                case .storedDeny:
                    harness.store.setPersistentDecision(.deny, for: .location, at: harness.site)
                case .globalNever:
                    harness.store.setGlobalDefault(.deny, for: .location)
                case .allowOnce, .denyOnce:
                    let activated = expectation(description: "Activate \(sourceState)")
                    harness.coordinator.request(harness.request([.location]), promptHandler: { _, respond in
                        respond(sourceState == .allowOnce ? .allowOnce : .denyOnce)
                    }, completion: { _ in activated.fulfill() })
                    await fulfillment(of: [activated], timeout: 1)
                }
                harness.systemStates[.location] = systemState

                let expectedState: SitePermissionQueryState
                switch sourceState {
                case .storedDeny, .globalNever, .denyOnce:
                    expectedState = .denied
                case .storedAllow, .allowOnce:
                    expectedState = systemState == .authorized ? .granted : .denied
                case .noDecision, .storedAsk:
                    expectedState = .prompt
                }

                XCTAssertEqual(
                    harness.coordinator.queryState(for: .location, context: harness.context),
                    expectedState,
                    "Unexpected query state for \(sourceState), OS \(systemState)"
                )

                var promptCount = 0
                var resolution: SitePermissionResolution?
                harness.coordinator.request(harness.request([.location]), promptHandler: { _, respond in
                    promptCount += 1
                    respond(.denyOnce)
                }, completion: { resolution = $0 })

                switch expectedState {
                case .prompt:
                    XCTAssertEqual(promptCount, 1, "Expected one prompt for \(sourceState), OS \(systemState)")
                    XCTAssertEqual(resolution, .deny(systemBlocks: []))
                case .granted:
                    XCTAssertEqual(promptCount, 0, "Granted state must not prompt for \(sourceState), OS \(systemState)")
                    XCTAssertEqual(resolution, .grant)
                case .denied:
                    XCTAssertEqual(promptCount, 0, "Denied state must not prompt for \(sourceState), OS \(systemState)")
                    guard case .some(.deny) = resolution else {
                        XCTFail("Expected denial for \(sourceState), OS \(systemState); got \(String(describing: resolution))")
                        continue
                    }
                }
            }
        }
    }

    func testManagerDenyWhilePromptIsPendingWinsWithoutBeingOverwritten() throws {
        let harness = try Harness()
        var respond: ((SitePermissionPromptDecision) -> Void)?
        var resolution: SitePermissionResolution?
        harness.coordinator.request(harness.request([.location]), promptHandler: { _, promptResponse in
            respond = promptResponse
        }, completion: { resolution = $0 })

        harness.store.setPersistentDecision(.deny, for: .location, at: harness.site)
        respond?(.allowWhileUsingSite)

        XCTAssertEqual(resolution, .deny(systemBlocks: []))
        XCTAssertEqual(harness.store.decision(for: .location, at: harness.site), .deny)
    }

    func testPermissionQueryAndRequestBothRejectStaleContext() throws {
        let harness = try Harness()
        let staleContext = harness.context
        harness.context = harness.context(changingNavigationGenerationTo: 2)
        var didPrompt = false
        var didComplete = false

        XCTAssertEqual(harness.coordinator.queryState(for: .location, context: staleContext), .denied)
        harness.coordinator.request(
            SitePermissionRequest(context: staleContext, permissionTypes: [.location]),
            promptHandler: { _, _ in didPrompt = true },
            completion: { _ in didComplete = true }
        )

        XCTAssertFalse(didPrompt)
        XCTAssertFalse(didComplete)
    }

    func testPermissionQueryMatchesNextRequestForActivePageDecision() async throws {
        let cases: [(SitePermissionPromptDecision, SitePermissionQueryState, SitePermissionResolution)] = [
            (.denyOnce, .denied, .deny(systemBlocks: [])),
            (.allowOnce, .granted, .grant)
        ]

        for (decision, queryState, expectedResolution) in cases {
            let harness = try Harness()
            let initialRequestCompleted = expectation(description: "Activate \(decision)")
            harness.coordinator.request(harness.request([.location]), promptHandler: { _, respond in
                respond(decision)
            }, completion: { _ in
                initialRequestCompleted.fulfill()
            })
            await fulfillment(of: [initialRequestCompleted], timeout: 1)

            XCTAssertEqual(harness.coordinator.queryState(for: .location, context: harness.context), queryState)

            var didPrompt = false
            let repeatedRequestCompleted = expectation(description: "Request after \(decision) completes")
            harness.coordinator.request(harness.request([.location]), promptHandler: { _, _ in
                didPrompt = true
            }, completion: { resolution in
                XCTAssertEqual(resolution, expectedResolution)
                repeatedRequestCompleted.fulfill()
            })
            await fulfillment(of: [repeatedRequestCompleted], timeout: 1)
            XCTAssertFalse(didPrompt)
        }
    }

    func testPermissionQueryReturnsImmediatelyWhileFIFOIsBusyAndMatchesNextRequest() async throws {
        let harness = try Harness()
        var cameraResponder: ((SitePermissionPromptDecision) -> Void)?
        var locationResponder: ((SitePermissionPromptDecision) -> Void)?
        var promptedTypes = [Set<SitePermissionType>]()

        harness.coordinator.request(harness.request([.camera]), promptHandler: { prompt, respond in
            promptedTypes.append(prompt.permissionTypes)
            cameraResponder = respond
        }, completion: { _ in })

        XCTAssertEqual(harness.coordinator.queryState(for: .location, context: harness.context), .prompt)
        XCTAssertEqual(promptedTypes, [[.camera]])

        let locationCompleted = expectation(description: "Location request completes after camera request")
        harness.coordinator.request(harness.request([.location]), promptHandler: { prompt, respond in
            promptedTypes.append(prompt.permissionTypes)
            locationResponder = respond
        }, completion: { resolution in
            XCTAssertEqual(resolution, .grant)
            locationCompleted.fulfill()
        })
        XCTAssertEqual(promptedTypes, [[.camera]])

        cameraResponder?(.denyOnce)
        XCTAssertEqual(promptedTypes, [[.camera], [.location]])
        locationResponder?(.allowOnce)
        await fulfillment(of: [locationCompleted], timeout: 1)
    }

    func testWhenCombinedStoredStateIsPartialAllowAndAskThenOneCombinedPromptIsShown() throws {
        let harness = try Harness()
        harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
        var prompts = [SitePermissionPrompt]()

        harness.coordinator.request(harness.request([.camera, .microphone]), promptHandler: { prompt, _ in
            prompts.append(prompt)
        }, completion: { _ in })

        XCTAssertEqual(prompts, [SitePermissionPrompt(site: harness.site, permissionTypes: [.camera, .microphone])])
    }

    func testWhenAllowOnceCaptureEndsThenNextRequestPromptsAgain() async throws {
        let harness = try Harness()
        let firstCompletion = expectation(description: "First request grants")
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { resolution in
            XCTAssertEqual(resolution, .grant)
            firstCompletion.fulfill()
        })
        await fulfillment(of: [firstCompletion], timeout: 1)

        var promptCount = 0
        var automaticResolution: SitePermissionResolution?
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
            promptCount += 1
        }, completion: { automaticResolution = $0 })
        XCTAssertEqual(automaticResolution, .grant)
        XCTAssertEqual(promptCount, 0)

        harness.coordinator.captureDidEnd([.camera])
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
            promptCount += 1
        }, completion: { _ in })
        XCTAssertEqual(promptCount, 1)
        XCTAssertNil(harness.store.decision(for: .camera, at: harness.site))
    }

    func testMediaCaptureObservationTracksInitialAndNewStatesIndependently() throws {
        let harness = try Harness()
        let webView = MediaCaptureWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setCameraCaptureStateForTesting(.active)

        harness.coordinator.observeMediaCapture(in: webView)

        XCTAssertEqual(harness.coordinator.captureState(for: .camera), .active)
        XCTAssertEqual(harness.coordinator.captureState(for: .microphone), .inactive)

        webView.setCameraCaptureStateForTesting(.muted)
        webView.setMicrophoneCaptureStateForTesting(.active)

        XCTAssertEqual(harness.coordinator.captureState(for: .camera), .paused)
        XCTAssertEqual(harness.coordinator.captureState(for: .microphone), .active)

        harness.coordinator.pageDidChange(.navigation)

        XCTAssertEqual(harness.coordinator.captureState(for: .camera), .paused)
        XCTAssertEqual(harness.coordinator.captureState(for: .microphone), .active)
    }

    func testInitialInactiveObservationAndActivePausedTransitionsRetainAllowOnceUntilCaptureEnds() async throws {
        let harness = try Harness()
        let grantCompletion = expectation(description: "Allow Once becomes active")
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { resolution in
            XCTAssertEqual(resolution, .grant)
            grantCompletion.fulfill()
        })
        await fulfillment(of: [grantCompletion], timeout: 1)

        let webView = MediaCaptureWebView(frame: .zero, configuration: WKWebViewConfiguration())
        harness.coordinator.observeMediaCapture(in: webView)

        var resolutionAfterInitialState: SitePermissionResolution?
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
            XCTFail("Initial inactive KVO state must not expire Allow Once")
        }, completion: { resolutionAfterInitialState = $0 })
        XCTAssertEqual(resolutionAfterInitialState, .grant)

        webView.setCameraCaptureStateForTesting(.active)
        webView.setCameraCaptureStateForTesting(.muted)
        webView.setCameraCaptureStateForTesting(.active)

        var resolutionWhileCapturing: SitePermissionResolution?
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
            XCTFail("Active and paused transitions must retain Allow Once")
        }, completion: { resolutionWhileCapturing = $0 })
        XCTAssertEqual(resolutionWhileCapturing, .grant)

        webView.setCameraCaptureStateForTesting(.none)
        var promptCount = 0
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
            promptCount += 1
        }, completion: { _ in })

        XCTAssertEqual(harness.coordinator.captureState(for: .camera), .inactive)
        XCTAssertEqual(promptCount, 1)
    }

    func testCaptureEndExpiresOnlyTheMatchingAllowOncePermission() async throws {
        let harness = try Harness()
        let grantCompletion = expectation(description: "Combined Allow Once becomes active")
        harness.coordinator.request(harness.request([.camera, .microphone]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { resolution in
            XCTAssertEqual(resolution, .grant)
            grantCompletion.fulfill()
        })
        await fulfillment(of: [grantCompletion], timeout: 1)

        let webView = MediaCaptureWebView(frame: .zero, configuration: WKWebViewConfiguration())
        harness.coordinator.observeMediaCapture(in: webView)
        webView.setCameraCaptureStateForTesting(.active)
        webView.setMicrophoneCaptureStateForTesting(.active)
        webView.setCameraCaptureStateForTesting(.muted)
        webView.setCameraCaptureStateForTesting(.none)

        var microphoneResolution: SitePermissionResolution?
        harness.coordinator.request(harness.request([.microphone]), promptHandler: { _, _ in
            XCTFail("Ending camera capture must not expire microphone Allow Once")
        }, completion: { microphoneResolution = $0 })
        XCTAssertEqual(microphoneResolution, .grant)

        var cameraPromptCount = 0
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            cameraPromptCount += 1
            respond(.denyOnce)
        }, completion: { _ in })
        XCTAssertEqual(cameraPromptCount, 1)

        webView.setMicrophoneCaptureStateForTesting(.none)
        var microphonePromptCount = 0
        harness.coordinator.request(harness.request([.microphone]), promptHandler: { _, _ in
            microphonePromptCount += 1
        }, completion: { _ in })

        XCTAssertEqual(harness.coordinator.captureState(for: .microphone), .inactive)
        XCTAssertEqual(microphonePromptCount, 1)
    }

    func testReplacingObservationAndClosingInvalidateOldObservations() throws {
        let harness = try Harness()
        let firstWebView = MediaCaptureWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let replacementWebView = MediaCaptureWebView(frame: .zero, configuration: WKWebViewConfiguration())
        firstWebView.setCameraCaptureStateForTesting(.active)
        replacementWebView.setMicrophoneCaptureStateForTesting(.muted)

        harness.coordinator.observeMediaCapture(in: firstWebView)
        harness.coordinator.observeMediaCapture(in: replacementWebView)

        XCTAssertEqual(harness.coordinator.captureState(for: .camera), .inactive)
        XCTAssertEqual(harness.coordinator.captureState(for: .microphone), .paused)

        firstWebView.setCameraCaptureStateForTesting(.muted)
        firstWebView.setMicrophoneCaptureStateForTesting(.active)

        XCTAssertEqual(harness.coordinator.captureState(for: .camera), .inactive)
        XCTAssertEqual(harness.coordinator.captureState(for: .microphone), .paused)

        replacementWebView.setCameraCaptureStateForTesting(.active)
        XCTAssertEqual(harness.coordinator.captureState(for: .camera), .active)

        harness.coordinator.close()
        harness.coordinator.observeMediaCapture(in: replacementWebView)
        replacementWebView.setCameraCaptureStateForTesting(.muted)
        replacementWebView.setMicrophoneCaptureStateForTesting(.active)

        XCTAssertEqual(harness.coordinator.captureState(for: .camera), .inactive)
        XCTAssertEqual(harness.coordinator.captureState(for: .microphone), .inactive)
    }

    func testWhenActiveAllowOnceAndStoredAllowCoverCombinedRequestThenTheyOverrideGlobalNever() async throws {
        let harness = try Harness()
        let firstCompletion = expectation(description: "Allow Once becomes active")
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { resolution in
            XCTAssertEqual(resolution, .grant)
            firstCompletion.fulfill()
        })
        await fulfillment(of: [firstCompletion], timeout: 1)

        harness.store.setGlobalDefault(.deny, for: .camera)
        harness.store.setPersistentDecision(.allow, for: .microphone, at: harness.site)
        var resolution: SitePermissionResolution?
        harness.coordinator.request(harness.request([.camera, .microphone]), promptHandler: { _, _ in
            XCTFail("Active and stored allows must satisfy the combined request")
        }, completion: { resolution = $0 })

        XCTAssertEqual(resolution, .grant)
    }

    func testWhenDenyOnceIsChosenThenItSuppressesReasksUntilReload() throws {
        let harness = try Harness()
        var firstResolution: SitePermissionResolution?
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            respond(.denyOnce)
        }, completion: { firstResolution = $0 })
        XCTAssertEqual(firstResolution, .deny(systemBlocks: []))

        var promptCount = 0
        var repeatedResolution: SitePermissionResolution?
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
            promptCount += 1
        }, completion: { repeatedResolution = $0 })
        XCTAssertEqual(repeatedResolution, .deny(systemBlocks: []))
        XCTAssertEqual(promptCount, 0)

        harness.coordinator.pageDidChange(.reload)
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
            promptCount += 1
        }, completion: { _ in })
        XCTAssertEqual(promptCount, 1)
    }

    func testWhenSameDocumentNavigationOccursThenPageDecisionSurvives() throws {
        let harness = try Harness()
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            respond(.denyOnce)
        }, completion: { _ in })

        harness.coordinator.pageDidChange(.sameDocumentNavigation)
        var resolution: SitePermissionResolution?
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
            XCTFail("Same-document navigation must preserve the page decision")
        }, completion: { resolution = $0 })

        XCTAssertEqual(resolution, .deny(systemBlocks: []))
    }

    func testWhenSameDocumentNavigationOccursThenAllowOnceSurvives() async throws {
        let harness = try Harness()
        let firstCompletion = expectation(description: "Allow Once becomes active")
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { resolution in
            XCTAssertEqual(resolution, .grant)
            firstCompletion.fulfill()
        })
        await fulfillment(of: [firstCompletion], timeout: 1)

        harness.coordinator.pageDidChange(.sameDocumentNavigation)
        var resolution: SitePermissionResolution?
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
            XCTFail("Same-document navigation must preserve Allow Once")
        }, completion: { resolution = $0 })

        XCTAssertEqual(resolution, .grant)
    }

    func testWhenPageOrProcessEndsThenAllowOnceDoesNotSurvive() async throws {
        for change in [SitePermissionPageChange.reload, .navigation, .webContentProcessReplacement] {
            let harness = try Harness()
            let grantCompletion = expectation(description: "Grant completes before \(change)")
            harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
                respond(.allowOnce)
            }, completion: { resolution in
                XCTAssertEqual(resolution, .grant)
                grantCompletion.fulfill()
            })
            await fulfillment(of: [grantCompletion], timeout: 1)

            harness.coordinator.pageDidChange(change)
            var didPrompt = false
            harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
                didPrompt = true
            }, completion: { _ in })
            XCTAssertTrue(didPrompt)
        }
    }

    func testWhenTabClosesThenCoordinatorIgnoresRequests() throws {
        let harness = try Harness()
        harness.coordinator.close()

        var didRespond = false
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
            didRespond = true
        }, completion: { _ in
            didRespond = true
        })
        XCTAssertFalse(didRespond)
    }

    func testWhenCoordinatorIsRestoredWithSameStoreThenAllowOnceIsNotRestored() async throws {
        let keyValueStore = MockKeyValueStore()
        let originalHarness = try Harness(keyValueStore: keyValueStore)
        let firstCompletion = expectation(description: "Allow Once becomes active")
        originalHarness.coordinator.request(originalHarness.request([.camera]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { resolution in
            XCTAssertEqual(resolution, .grant)
            firstCompletion.fulfill()
        })
        await fulfillment(of: [firstCompletion], timeout: 1)

        let restoredHarness = try Harness(keyValueStore: keyValueStore)
        var didPrompt = false
        restoredHarness.coordinator.request(restoredHarness.request([.camera]), promptHandler: { _, _ in
            didPrompt = true
        }, completion: { _ in })

        XCTAssertTrue(didPrompt)
        XCTAssertNil(restoredHarness.store.decision(for: .camera, at: restoredHarness.site))
    }

    func testWhenTwoPromptsArriveThenSecondWaitsForFirstCompleteFlow() async throws {
        let harness = try Harness()
        var responders = [(SitePermissionPromptDecision) -> Void]()
        var promptedTypes = [Set<SitePermissionType>]()
        let firstCompletion = expectation(description: "First request completes")
        let secondCompletion = expectation(description: "Second request completes")

        let promptHandler: SitePermissionsCoordinator.PromptHandler = { prompt, respond in
            promptedTypes.append(prompt.permissionTypes)
            responders.append(respond)
        }
        harness.coordinator.request(harness.request([.camera]), promptHandler: promptHandler) { resolution in
            XCTAssertEqual(resolution, .grant)
            firstCompletion.fulfill()
        }
        harness.coordinator.request(harness.request([.microphone]), promptHandler: promptHandler) { resolution in
            XCTAssertEqual(resolution, .grant)
            secondCompletion.fulfill()
        }

        XCTAssertEqual(promptedTypes, [[.camera]])
        responders[0](.allowOnce)
        await fulfillment(of: [firstCompletion], timeout: 1)
        XCTAssertEqual(promptedTypes, [[.camera], [.microphone]])
        responders[1](.allowOnce)
        await fulfillment(of: [secondCompletion], timeout: 1)
    }

    func testWhenMediaPermissionsResetThenMediaDismissesBeforeQueuedLocationPrompts() throws {
        let harness = try Harness()
        var events = [String]()
        var respondToMedia: ((SitePermissionPromptDecision) -> Void)?
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            events.append("media prompt")
            respondToMedia = respond
        }, completion: { _ in
            XCTFail("The caller resolves canceled media bridge replies")
        })
        harness.coordinator.request(harness.request([.location]), promptHandler: { _, respond in
            events.append("location prompt")
            respond(.denyOnce)
        }, completion: { resolution in
            XCTAssertEqual(resolution, .deny(systemBlocks: []))
            events.append("location completion")
        })

        harness.coordinator.resetMediaPermissions {
            events.append("media dismissal")
        }

        XCTAssertEqual(events, ["media prompt", "media dismissal", "location prompt", "location completion"])
        try XCTUnwrap(respondToMedia)(.neverAllow)
        XCTAssertNil(harness.store.decision(for: .camera, at: harness.site))
    }

    func testWhenMediaPermissionsResetThenActiveLocationAndItsSessionGrantSurvive() async throws {
        let harness = try Harness()
        var respondToLocation: ((SitePermissionPromptDecision) -> Void)?
        let locationCompleted = expectation(description: "Location completes after media rollback")
        harness.coordinator.request(harness.request([.location]), promptHandler: { _, respond in
            respondToLocation = respond
        }, completion: { resolution in
            XCTAssertEqual(resolution, .grant)
            locationCompleted.fulfill()
        })
        harness.coordinator.request(harness.request([.camera, .microphone]), promptHandler: { _, _ in
            XCTFail("Queued media requests must be discarded")
        }, completion: { _ in
            XCTFail("The caller resolves canceled media bridge replies")
        })

        harness.coordinator.resetMediaPermissions {
            XCTFail("The active location prompt must remain visible")
        }
        try XCTUnwrap(respondToLocation)(.allowOnce)
        await fulfillment(of: [locationCompleted], timeout: 1)

        harness.coordinator.resetMediaPermissions {
            XCTFail("No media presentation remains")
        }
        XCTAssertEqual(harness.coordinator.queryState(for: .location, context: harness.context), .granted)
        var nextLocationResolution: SitePermissionResolution?
        harness.coordinator.request(harness.request([.location]), promptHandler: { _, _ in
            XCTFail("The location session grant must survive media rollback")
        }, completion: { nextLocationResolution = $0 })
        XCTAssertEqual(nextLocationResolution, .grant)
        XCTAssertNil(harness.store.decision(for: .location, at: harness.site))
    }

    func testWhenFirstQueuedRequestChoosesNeverAllowThenSecondIsSilentlyDenied() throws {
        let harness = try Harness()
        var responders = [(SitePermissionPromptDecision) -> Void]()
        var resolutions = [SitePermissionResolution]()
        let promptHandler: SitePermissionsCoordinator.PromptHandler = { _, respond in
            responders.append(respond)
        }

        harness.coordinator.request(harness.request([.camera]), promptHandler: promptHandler) { resolutions.append($0) }
        harness.coordinator.request(harness.request([.camera]), promptHandler: promptHandler) { resolutions.append($0) }
        responders[0](.neverAllow)

        XCTAssertEqual(responders.count, 1)
        XCTAssertEqual(resolutions, [.deny(systemBlocks: []), .deny(systemBlocks: [])])
        XCTAssertEqual(harness.store.decision(for: .camera, at: harness.site), .deny)
    }

    func testWhenFirstQueuedRequestChoosesAllowWhileUsingSiteThenSecondUsesStoredAllow() async throws {
        let harness = try Harness()
        var responders = [(SitePermissionPromptDecision) -> Void]()
        var resolutions = [SitePermissionResolution]()
        let promptHandler: SitePermissionsCoordinator.PromptHandler = { _, respond in
            responders.append(respond)
        }
        let completions = expectation(description: "Both requests complete")
        completions.expectedFulfillmentCount = 2

        harness.coordinator.request(harness.request([.camera]), promptHandler: promptHandler) { resolution in
            resolutions.append(resolution)
            completions.fulfill()
        }
        harness.coordinator.request(harness.request([.camera]), promptHandler: promptHandler) { resolution in
            resolutions.append(resolution)
            completions.fulfill()
        }
        responders[0](.allowWhileUsingSite)
        await fulfillment(of: [completions], timeout: 1)

        XCTAssertEqual(responders.count, 1)
        XCTAssertEqual(resolutions, [.grant, .grant])
        XCTAssertEqual(harness.store.decision(for: .camera, at: harness.site), .allow)
    }

    func testWhenFirstQueuedRequestChoosesPageDecisionThenSecondUsesItWithoutPrompting() async throws {
        let cases: [(SitePermissionPromptDecision, SitePermissionResolution)] = [
            (.denyOnce, .deny(systemBlocks: [])),
            (.allowOnce, .grant)
        ]

        for (decision, expectedResolution) in cases {
            let harness = try Harness()
            var responders = [(SitePermissionPromptDecision) -> Void]()
            var resolutions = [SitePermissionResolution]()
            let completions = expectation(description: "Both \(decision) requests complete")
            completions.expectedFulfillmentCount = 2
            let promptHandler: SitePermissionsCoordinator.PromptHandler = { _, respond in
                responders.append(respond)
            }

            for _ in 0..<2 {
                harness.coordinator.request(harness.request([.camera]), promptHandler: promptHandler) { resolution in
                    resolutions.append(resolution)
                    completions.fulfill()
                }
            }
            responders[0](decision)
            await fulfillment(of: [completions], timeout: 1)

            XCTAssertEqual(responders.count, 1)
            XCTAssertEqual(resolutions, [expectedResolution, expectedResolution])
        }
    }

    func testWhenAnyContextFieldChangesBeforePromptResponseThenWorkIsDropped() throws {
        let baseline = try Harness.makeContext()
        let anotherSite = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://other.example")!))
        let changedContexts = [
            SitePermissionRequestContext(tabID: "other-tab",
                                         topLevelSite: baseline.topLevelSite,
                                         requestingFrameID: baseline.requestingFrameID,
                                         webContentProcessGeneration: baseline.webContentProcessGeneration,
                                         navigationGeneration: baseline.navigationGeneration),
            SitePermissionRequestContext(tabID: baseline.tabID,
                                         topLevelSite: anotherSite,
                                         requestingFrameID: baseline.requestingFrameID,
                                         webContentProcessGeneration: baseline.webContentProcessGeneration,
                                         navigationGeneration: baseline.navigationGeneration),
            SitePermissionRequestContext(tabID: baseline.tabID,
                                         topLevelSite: baseline.topLevelSite,
                                         requestingFrameID: 99,
                                         webContentProcessGeneration: baseline.webContentProcessGeneration,
                                         navigationGeneration: baseline.navigationGeneration),
            SitePermissionRequestContext(tabID: baseline.tabID,
                                         topLevelSite: baseline.topLevelSite,
                                         requestingFrameID: baseline.requestingFrameID,
                                         webContentProcessGeneration: 2,
                                         navigationGeneration: baseline.navigationGeneration),
            SitePermissionRequestContext(tabID: baseline.tabID,
                                         topLevelSite: baseline.topLevelSite,
                                         requestingFrameID: baseline.requestingFrameID,
                                         webContentProcessGeneration: baseline.webContentProcessGeneration,
                                         navigationGeneration: 2)
        ]

        for changedContext in changedContexts {
            let harness = try Harness(context: baseline)
            var responder: ((SitePermissionPromptDecision) -> Void)?
            var resolution: SitePermissionResolution?
            harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
                responder = respond
            }, completion: { resolution = $0 })

            harness.context = changedContext
            responder?(.allowWhileUsingSite)

            XCTAssertNil(resolution)
            XCTAssertNil(harness.store.decision(for: .camera, at: baseline.topLevelSite))
        }
    }

    func testWhenNavigationOccursDuringOSRequestThenLateResultIsDroppedButCommittedAllowRemains() async throws {
        let harness = try Harness()
        harness.systemStates[.camera] = .notDetermined
        let authorizationStarted = expectation(description: "OS authorization starts")
        let staleCompletion = expectation(description: "Stale work does not complete")
        staleCompletion.isInverted = true
        var authorizationContinuation: CheckedContinuation<SystemPermissionAuthorizationState, Never>?
        harness.authorizationRequester = { _ in
            authorizationStarted.fulfill()
            return await withCheckedContinuation { authorizationContinuation = $0 }
        }
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            respond(.allowWhileUsingSite)
        }, completion: { _ in staleCompletion.fulfill() })

        XCTAssertEqual(harness.store.decision(for: .camera, at: harness.site), .allow)
        await fulfillment(of: [authorizationStarted], timeout: 1)
        harness.context = harness.context(changingNavigationGenerationTo: 2)
        authorizationContinuation?.resume(returning: .authorized)
        await fulfillment(of: [staleCompletion], timeout: 0.1)

        XCTAssertEqual(harness.store.decision(for: .camera, at: harness.site), .allow)
    }

    func testWhenCombinedOSStatesDifferThenEveryTypeIsClassifiedSeparately() throws {
        let harness = try Harness()
        harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
        harness.store.setPersistentDecision(.allow, for: .microphone, at: harness.site)
        harness.systemStates[.camera] = .restricted
        harness.systemStates[.microphone] = .unavailable
        var recovery: SitePermissionRecovery?
        harness.recoveryHandler = { receivedRecovery, completion in
            recovery = receivedRecovery
            completion()
        }
        var resolution: SitePermissionResolution?

        harness.coordinator.request(harness.request([.camera, .microphone]), promptHandler: { _, _ in
            XCTFail("Stored decisions must not prompt")
        }, completion: { resolution = $0 })

        XCTAssertEqual(resolution, .deny(systemBlocks: [
            SitePermissionSystemBlock(permissionType: .camera, state: .restricted, timing: .preexisting),
            SitePermissionSystemBlock(permissionType: .microphone, state: .unavailable, timing: .preexisting)
        ]))
        XCTAssertEqual(recovery, .reminder(permissionTypes: [.camera, .microphone]))
    }

    func testWhenStoredAllowHasUndeterminedSystemStateThenItDoesNotRequestAuthorization() throws {
        let harness = try Harness()
        harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
        harness.systemStates[.camera] = .notDetermined
        harness.authorizationRequester = { _ in
            XCTFail("Automatic Allow must not trigger the OS prompt")
            return .authorized
        }
        harness.recoveryHandler = { _, completion in
            XCTFail("A preexisting notDetermined state has no recovery UI")
            completion()
        }
        var resolution: SitePermissionResolution?

        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
            XCTFail("Stored Allow must not show another site prompt")
        }, completion: { resolution = $0 })

        XCTAssertEqual(resolution, .deny(systemBlocks: [
            SitePermissionSystemBlock(permissionType: .camera, state: .notDetermined, timing: .preexisting)
        ]))
    }

    func testWhenFreshSystemRequestIsDeniedThenRecoveryMarksItAsAfterRequest() async throws {
        let harness = try Harness()
        harness.systemStates[.camera] = .notDetermined
        harness.authorizationRequester = { permissionType in
            XCTAssertEqual(permissionType, .camera)
            return .denied
        }
        var recovery: SitePermissionRecovery?
        harness.recoveryHandler = { receivedRecovery, completion in
            recovery = receivedRecovery
            completion()
        }
        let completion = expectation(description: "Request completes")

        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { resolution in
            XCTAssertEqual(resolution, .deny(systemBlocks: [
                SitePermissionSystemBlock(permissionType: .camera, state: .denied, timing: .afterRequest)
            ]))
            completion.fulfill()
        })

        await fulfillment(of: [completion], timeout: 1)
        XCTAssertEqual(recovery, .toast(permissionTypes: [.camera]))
    }

    func testWhenPersistentAllowIsFollowedBySystemDenialThenAllowRemainsStored() async throws {
        let harness = try Harness()
        harness.systemStates[.camera] = .notDetermined
        harness.authorizationRequester = { _ in .denied }
        let completion = expectation(description: "Request completes")

        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            respond(.allowWhileUsingSite)
        }, completion: { resolution in
            XCTAssertEqual(resolution, .deny(systemBlocks: [
                SitePermissionSystemBlock(permissionType: .camera, state: .denied, timing: .afterRequest)
            ]))
            completion.fulfill()
        })

        await fulfillment(of: [completion], timeout: 1)
        XCTAssertEqual(harness.store.decision(for: .camera, at: harness.site), .allow)
    }

    func testWhenFreshCombinedRequestNeedsSystemAuthorizationThenEachTypeIsRequestedSeparately() async throws {
        let harness = try Harness()
        harness.systemStates[.camera] = .notDetermined
        harness.systemStates[.microphone] = .notDetermined
        var requestedTypes = [SitePermissionType]()
        harness.authorizationRequester = { permissionType in
            requestedTypes.append(permissionType)
            return permissionType == .camera ? .denied : .authorized
        }
        var recovery: SitePermissionRecovery?
        harness.recoveryHandler = { receivedRecovery, completion in
            recovery = receivedRecovery
            completion()
        }
        let completion = expectation(description: "Combined request completes")

        harness.coordinator.request(harness.request([.camera, .microphone]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { resolution in
            XCTAssertEqual(resolution, .deny(systemBlocks: [
                SitePermissionSystemBlock(permissionType: .camera, state: .denied, timing: .afterRequest)
            ]))
            completion.fulfill()
        })

        await fulfillment(of: [completion], timeout: 1)
        XCTAssertEqual(requestedTypes, [.camera, .microphone])
        XCTAssertEqual(recovery, .toast(permissionTypes: [.camera]))
    }

    func testWhenCombinedSiteAllowFindsAnyPreexistingBlockThenNoSystemPermissionIsRequested() async throws {
        let harness = try Harness()
        harness.systemStates[.camera] = .denied
        harness.systemStates[.microphone] = .notDetermined
        harness.authorizationRequester = { _ in
            XCTFail("A combined request that is already blocked must not consume another OS prompt")
            return .authorized
        }
        var recovery: SitePermissionRecovery?
        harness.recoveryHandler = { receivedRecovery, completion in
            recovery = receivedRecovery
            completion()
        }
        let completion = expectation(description: "Combined request completes")

        harness.coordinator.request(harness.request([.camera, .microphone]), promptHandler: { _, respond in
            respond(.allowWhileUsingSite)
        }, completion: { resolution in
            XCTAssertEqual(resolution, .deny(systemBlocks: [
                SitePermissionSystemBlock(permissionType: .camera, state: .denied, timing: .preexisting)
            ]))
            completion.fulfill()
        })

        await fulfillment(of: [completion], timeout: 1)
        XCTAssertEqual(recovery, .reminder(permissionTypes: [.camera]))
        XCTAssertEqual(harness.store.decision(for: .camera, at: harness.site), .allow)
        XCTAssertEqual(harness.store.decision(for: .microphone, at: harness.site), .allow)
    }

    func testWhenFreshCombinedSystemRequestsBothFailThenOneCombinedToastIsShown() async throws {
        let harness = try Harness()
        harness.systemStates[.camera] = .notDetermined
        harness.systemStates[.microphone] = .notDetermined
        var requestedTypes = [SitePermissionType]()
        harness.authorizationRequester = { permissionType in
            requestedTypes.append(permissionType)
            return .denied
        }
        var recoveries = [SitePermissionRecovery]()
        harness.recoveryHandler = { recovery, completion in
            recoveries.append(recovery)
            completion()
        }
        let completion = expectation(description: "Combined request completes")

        harness.coordinator.request(harness.request([.camera, .microphone]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { resolution in
            XCTAssertEqual(resolution, .deny(systemBlocks: [
                SitePermissionSystemBlock(permissionType: .camera, state: .denied, timing: .afterRequest),
                SitePermissionSystemBlock(permissionType: .microphone, state: .denied, timing: .afterRequest)
            ]))
            completion.fulfill()
        })

        await fulfillment(of: [completion], timeout: 1)
        XCTAssertEqual(requestedTypes, [.camera, .microphone])
        XCTAssertEqual(recoveries, [.toast(permissionTypes: [.camera, .microphone])])
    }

    func testWhenStoredAllowIsSystemDeniedThenResolutionPrecedesRecoveryAndNextRequestWaits() throws {
        let harness = try Harness()
        harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
        harness.systemStates[.camera] = .denied
        var events = [String]()
        var receivedRecovery: SitePermissionRecovery?
        var finishRecovery: (() -> Void)?
        harness.recoveryHandler = { recovery, completion in
            events.append("recovery")
            receivedRecovery = recovery
            finishRecovery = completion
        }

        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
            XCTFail("Stored Allow must not show another site prompt")
        }, completion: { resolution in
            events.append("resolution")
            XCTAssertEqual(resolution, .deny(systemBlocks: [
                SitePermissionSystemBlock(permissionType: .camera, state: .denied, timing: .preexisting)
            ]))
        })

        var secondPrompt: SitePermissionPrompt?
        harness.coordinator.request(harness.request([.microphone]), promptHandler: { prompt, _ in
            events.append("nextPrompt")
            secondPrompt = prompt
        }, completion: { _ in })

        XCTAssertEqual(events, ["resolution", "recovery"])
        XCTAssertEqual(receivedRecovery, .reminder(permissionTypes: [.camera]))
        XCTAssertNil(secondPrompt)

        finishRecovery?()

        XCTAssertEqual(events, ["resolution", "recovery", "nextPrompt"])
        XCTAssertEqual(secondPrompt, SitePermissionPrompt(site: harness.site, permissionTypes: [.microphone]))
    }

    func testWhenCompletionReleasesRequestContextThenRecoveryRetainsFIFOUnlessPageResets() throws {
        for resetsPage in [false, true] {
            let harness = try Harness()
            harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
            var currentContext: SitePermissionRequestContext? = harness.context
            var events = [String]()
            var finishRecovery: (() -> Void)?
            let coordinator = SitePermissionsCoordinator(
                store: harness.store,
                isFireMode: false,
                currentContext: { _, _ in currentContext },
                authorizationState: { _ in .denied },
                requestAuthorization: { _ in
                    XCTFail("Stored Allow must not request system authorization")
                    return .denied
                },
                recoveryHandler: { recovery, completion in
                    XCTAssertEqual(recovery, .reminder(permissionTypes: [.camera]))
                    events.append("recovery")
                    finishRecovery = completion
                }
            )

            coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
                XCTFail("Stored Allow must not show a site prompt")
            }, completion: { resolution in
                XCTAssertEqual(resolution, .deny(systemBlocks: [
                    SitePermissionSystemBlock(permissionType: .camera, state: .denied, timing: .preexisting)
                ]))
                events.append("resolution")
                // App bridge completion removes its pending request and therefore its context.
                currentContext = nil
                if resetsPage {
                    coordinator.pageDidChange(.navigation)
                }
            })

            XCTAssertEqual(events, resetsPage ? ["resolution"] : ["resolution", "recovery"])
            currentContext = harness.context
            coordinator.request(harness.request([.microphone]), promptHandler: { _, _ in
                events.append("nextPrompt")
            }, completion: { _ in })

            if resetsPage {
                XCTAssertNil(finishRecovery)
                XCTAssertEqual(events, ["resolution", "nextPrompt"])
            } else {
                XCTAssertEqual(events, ["resolution", "recovery"])
                try XCTUnwrap(finishRecovery)()
                XCTAssertEqual(events, ["resolution", "recovery", "nextPrompt"])
            }
        }
    }

    func testWhenIndividualSystemPromptCompletesThenExactlyOneResultEventIsEmitted() async throws {
        let scenarios: [(SitePermissionType, SystemPermissionAuthorizationState, SitePermissionsEvent.SystemPromptResult)] = [
            (.camera, .authorized, .granted),
            (.microphone, .denied, .denied)
        ]

        for (permissionType, finalState, expectedResult) in scenarios {
            let harness = try Harness()
            harness.systemStates[permissionType] = .notDetermined
            var requestedTypes = [SitePermissionType]()
            harness.authorizationRequester = { requestedType in
                requestedTypes.append(requestedType)
                return finalState
            }
            var events = [SitePermissionsEvent]()
            let eventFired = expectation(description: "System prompt result fires for \(permissionType)")
            harness.eventHandler = { event in
                events.append(event)
                eventFired.fulfill()
            }
            let requestCompleted = expectation(description: "Request completes for \(permissionType)")

            harness.coordinator.request(harness.request([permissionType]), promptHandler: { _, respond in
                respond(.allowOnce)
            }, completion: { _ in
                requestCompleted.fulfill()
            })

            await fulfillment(of: [eventFired, requestCompleted], timeout: 1)
            XCTAssertEqual(requestedTypes, [permissionType])
            XCTAssertEqual(events, [.permissionSystemPromptResult(type: permissionType, result: expectedResult)])
        }
    }

    func testWhenCombinedSystemPromptsCompleteThenEachTypeEmitsItsOwnResultEvent() async throws {
        let harness = try Harness()
        harness.systemStates[.camera] = .notDetermined
        harness.systemStates[.microphone] = .notDetermined
        var requestedTypes = [SitePermissionType]()
        harness.authorizationRequester = { permissionType in
            requestedTypes.append(permissionType)
            return permissionType == .camera ? .denied : .authorized
        }
        var events = [SitePermissionsEvent]()
        let eventsFired = expectation(description: "Both system prompt results fire")
        eventsFired.expectedFulfillmentCount = 2
        harness.eventHandler = { event in
            events.append(event)
            eventsFired.fulfill()
        }
        let requestCompleted = expectation(description: "Combined request completes")

        harness.coordinator.request(harness.request([.camera, .microphone]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { _ in
            requestCompleted.fulfill()
        })

        await fulfillment(of: [eventsFired, requestCompleted], timeout: 1)
        XCTAssertEqual(requestedTypes, [.camera, .microphone])
        XCTAssertEqual(events, [
            .permissionSystemPromptResult(type: .camera, result: .denied),
            .permissionSystemPromptResult(type: .microphone, result: .granted)
        ])
    }

    func testWhenCombinedRequestHasPreexistingDenialThenNoSystemPromptResultEventIsEmitted() async throws {
        let harness = try Harness()
        harness.systemStates[.camera] = .denied
        harness.systemStates[.microphone] = .notDetermined
        var requestedTypes = [SitePermissionType]()
        harness.authorizationRequester = { permissionType in
            requestedTypes.append(permissionType)
            return .authorized
        }
        var events = [SitePermissionsEvent]()
        harness.eventHandler = { events.append($0) }
        let requestCompleted = expectation(description: "Pre-blocked combined request completes")

        harness.coordinator.request(harness.request([.camera, .microphone]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { _ in
            requestCompleted.fulfill()
        })

        await fulfillment(of: [requestCompleted], timeout: 1)
        XCTAssertTrue(requestedTypes.isEmpty)
        XCTAssertTrue(events.isEmpty)
    }

    func testWhenContextBecomesStaleWhileSystemPromptIsOpenThenResultEventStillFires() async throws {
        let harness = try Harness()
        harness.systemStates[.camera] = .notDetermined
        let authorizationStarted = expectation(description: "OS authorization starts")
        var authorizationContinuation: CheckedContinuation<SystemPermissionAuthorizationState, Never>?
        harness.authorizationRequester = { _ in
            authorizationStarted.fulfill()
            return await withCheckedContinuation { authorizationContinuation = $0 }
        }
        var events = [SitePermissionsEvent]()
        let eventFired = expectation(description: "System prompt result fires")
        harness.eventHandler = { event in
            events.append(event)
            eventFired.fulfill()
        }
        let staleRequestCompleted = expectation(description: "Stale WebKit request does not complete")
        staleRequestCompleted.isInverted = true

        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { _ in
            staleRequestCompleted.fulfill()
        })

        await fulfillment(of: [authorizationStarted], timeout: 1)
        harness.context = harness.context(changingNavigationGenerationTo: 2)
        authorizationContinuation?.resume(returning: .denied)

        await fulfillment(of: [eventFired], timeout: 1)
        await fulfillment(of: [staleRequestCompleted], timeout: 0.1)
        XCTAssertEqual(events, [.permissionSystemPromptResult(type: .camera, result: .denied)])
    }

    func testWhenFreshCombinedRequestHasPreexistingBlockThenUndeterminedTypesAreNotRequested() async throws {
        let harness = try Harness()
        harness.systemStates[.camera] = .denied
        harness.systemStates[.microphone] = .notDetermined
        var requestedTypes = [SitePermissionType]()
        harness.authorizationRequester = { permissionType in
            requestedTypes.append(permissionType)
            return .authorized
        }
        let completion = expectation(description: "Combined request completes")

        harness.coordinator.request(harness.request([.camera, .microphone]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { resolution in
            XCTAssertEqual(resolution, .deny(systemBlocks: [
                SitePermissionSystemBlock(permissionType: .camera, state: .denied, timing: .preexisting)
            ]))
            completion.fulfill()
        })

        await fulfillment(of: [completion], timeout: 1)
        XCTAssertTrue(requestedTypes.isEmpty)
    }

    func testWhenFireModeUserChoosesPersistentOptionsThenOnlyMemoryChanges() async throws {
        let harness = try Harness(isFireMode: true)
        harness.store.setGlobalDefault(.deny, for: .microphone)
        harness.store.setPersistentDecision(.allow, for: .location, at: harness.site)

        var globalResolution: SitePermissionResolution?
        harness.coordinator.request(harness.request([.microphone]), promptHandler: { _, _ in
            XCTFail("Fire mode must read the global default")
        }, completion: { globalResolution = $0 })
        XCTAssertEqual(globalResolution, .deny(systemBlocks: []))

        var storedResolution: SitePermissionResolution?
        harness.coordinator.request(harness.request([.location]), promptHandler: { _, _ in
            XCTFail("Fire mode must read the stored site decision")
        }, completion: { storedResolution = $0 })
        XCTAssertEqual(storedResolution, .grant)

        let grantCompletion = expectation(description: "Memory grant completes")
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            respond(.allowWhileUsingSite)
        }, completion: { resolution in
            XCTAssertEqual(resolution, .grant)
            grantCompletion.fulfill()
        })
        await fulfillment(of: [grantCompletion], timeout: 1)
        XCTAssertNil(harness.store.decision(for: .camera, at: harness.site))

        harness.coordinator.captureDidEnd([.camera])
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            respond(.neverAllow)
        }, completion: { _ in })
        XCTAssertNil(harness.store.decision(for: .camera, at: harness.site))

        var resolution: SitePermissionResolution?
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in
            XCTFail("Fire-mode Never must suppress for this page")
        }, completion: { resolution = $0 })
        XCTAssertEqual(resolution, .deny(systemBlocks: []))
    }
}

@MainActor
private final class Harness {

    let store: SitePermissionsStore
    let site: SitePermissionKey
    let isFireMode: Bool
    var context: SitePermissionRequestContext
    var systemStates: [SitePermissionType: SystemPermissionAuthorizationState] = [
        .camera: .authorized,
        .microphone: .authorized,
        .location: .authorized
    ]
    var authorizationRequester: (SitePermissionType) async -> SystemPermissionAuthorizationState = { _ in .authorized }
    var recoveryHandler: SitePermissionsCoordinator.RecoveryHandler = { _, completion in completion() }
    var eventHandler: SitePermissionsCoordinator.EventHandler = { _ in }

    lazy var coordinator = SitePermissionsCoordinator(
        store: store,
        isFireMode: isFireMode,
        currentContext: { [weak self] tabID, frameID in
            guard let self,
                  context.tabID == tabID,
                  context.requestingFrameID == frameID else { return nil }
            return context
        },
        authorizationState: { [weak self] permissionType in
            self?.systemStates[permissionType] ?? .unavailable
        },
        requestAuthorization: { [weak self] permissionType in
            guard let self else { return .unavailable }
            return await authorizationRequester(permissionType)
        },
        recoveryHandler: { [weak self] recovery, completion in
            guard let self else {
                completion()
                return
            }
            recoveryHandler(recovery, completion)
        },
        eventHandler: { [weak self] event in
            self?.eventHandler(event)
        })

    init(isFireMode: Bool = false,
         context: SitePermissionRequestContext? = nil,
         keyValueStore: MockKeyValueStore = MockKeyValueStore()) throws {
        let context = try context ?? Self.makeContext()
        self.context = context
        site = context.topLevelSite
        self.isFireMode = isFireMode
        store = SitePermissionsStore(storage: keyValueStore.keyedStoring())
    }

    func request(_ permissionTypes: Set<SitePermissionType>) -> SitePermissionRequest {
        SitePermissionRequest(context: context, permissionTypes: permissionTypes)
    }

    func context(changingNavigationGenerationTo generation: UInt) -> SitePermissionRequestContext {
        SitePermissionRequestContext(tabID: context.tabID,
                                     topLevelSite: context.topLevelSite,
                                     requestingFrameID: context.requestingFrameID,
                                     webContentProcessGeneration: context.webContentProcessGeneration,
                                     navigationGeneration: generation)
    }

    static func makeContext() throws -> SitePermissionRequestContext {
        let site = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://example.com")!))
        return SitePermissionRequestContext(tabID: "tab-1",
                                            topLevelSite: site,
                                            requestingFrameID: 42,
                                            webContentProcessGeneration: 1,
                                            navigationGeneration: 1)
    }
}

@MainActor
private final class MediaCaptureWebView: WKWebView {

    private var cameraCaptureStateValue = WKMediaCaptureState.none
    private var microphoneCaptureStateValue = WKMediaCaptureState.none

    override var cameraCaptureState: WKMediaCaptureState {
        cameraCaptureStateValue
    }

    override var microphoneCaptureState: WKMediaCaptureState {
        microphoneCaptureStateValue
    }

    func setCameraCaptureStateForTesting(_ state: WKMediaCaptureState) {
        willChangeValue(for: \.cameraCaptureState)
        cameraCaptureStateValue = state
        didChangeValue(for: \.cameraCaptureState)
    }

    func setMicrophoneCaptureStateForTesting(_ state: WKMediaCaptureState) {
        willChangeValue(for: \.microphoneCaptureState)
        microphoneCaptureStateValue = state
        didChangeValue(for: \.microphoneCaptureState)
    }
}
