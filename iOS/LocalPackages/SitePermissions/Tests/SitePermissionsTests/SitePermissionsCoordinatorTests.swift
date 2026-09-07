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
import XCTest
@testable import SitePermissions

@MainActor
final class SitePermissionsCoordinatorTests: XCTestCase {

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
        harness.systemStates[.camera] = .denied
        harness.systemStates[.microphone] = .restricted
        var resolution: SitePermissionResolution?

        harness.coordinator.request(harness.request([.camera, .microphone]), promptHandler: { _, _ in
            XCTFail("Stored decisions must not prompt")
        }, completion: { resolution = $0 })

        XCTAssertEqual(resolution, .deny(systemBlocks: [
            SitePermissionSystemBlock(permissionType: .camera, state: .denied, timing: .preexisting),
            SitePermissionSystemBlock(permissionType: .microphone, state: .restricted, timing: .preexisting)
        ]))
    }

    func testWhenStoredAllowHasUndeterminedSystemStateThenItDoesNotRequestAuthorization() throws {
        let harness = try Harness()
        harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
        harness.systemStates[.camera] = .notDetermined
        harness.authorizationRequester = { _ in
            XCTFail("Automatic Allow must not trigger the OS prompt")
            return .authorized
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
            return permissionType == .camera ? .authorized : .denied
        }
        let completion = expectation(description: "Combined request completes")

        harness.coordinator.request(harness.request([.camera, .microphone]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { resolution in
            XCTAssertEqual(resolution, .deny(systemBlocks: [
                SitePermissionSystemBlock(permissionType: .microphone, state: .denied, timing: .afterRequest)
            ]))
            completion.fulfill()
        })

        await fulfillment(of: [completion], timeout: 1)
        XCTAssertEqual(requestedTypes, [.camera, .microphone])
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
