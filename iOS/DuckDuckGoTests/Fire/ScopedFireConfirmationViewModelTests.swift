//
//  ScopedFireConfirmationViewModelTests.swift
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

import XCTest
import UIKit
import Core
import Persistence
import FeatureFlags_iOS
@testable import DuckDuckGo

@MainActor
final class ScopedFireConfirmationViewModelTests: XCTestCase {
    
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockDownloadManager: SpyDownloadManager!
    private var mockKeyValueStore: MockKeyValueStore!
    private var mockHistoryManager: MockHistoryManager!
    private var mockAppSettings: AppSettingsMock!
    private var mockDataClearingCapability: MockDataClearingCapability!

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
        mockDownloadManager = SpyDownloadManager()
        mockKeyValueStore = MockKeyValueStore()
        mockHistoryManager = MockHistoryManager()
        mockAppSettings = AppSettingsMock()
        mockDataClearingCapability = MockDataClearingCapability()
    }
    
    override func tearDown() {
        mockFeatureFlagger = nil
        mockDownloadManager = nil
        mockKeyValueStore = nil
        mockHistoryManager = nil
        mockAppSettings = nil
        mockDataClearingCapability = nil
        super.tearDown()
    }
    
    // MARK: - Button Action Tests
    
    func testWhenNoTabThenDeleteAllButtonFiresAllScope() {
        // Given
        var capturedRequest: FireRequest?
        let sut = makeSUT(tabViewModel: nil, onConfirm: { request in
            capturedRequest = request
        })
        
        // When
        sut.buttons[0].action()
        
        // Then
        XCTAssertEqual(capturedRequest?.options, .all)
        XCTAssertEqual(capturedRequest?.trigger, .manualFire)
        if case .all = capturedRequest?.scope {
            // Expected scope
        } else {
            XCTFail("Expected scope to be .all")
        }
    }
    
    func testWhenFireModeThenDeleteAllButtonFiresFireModeScope() {
        // Given
        var capturedRequest: FireRequest?
        let sut = makeSUT(tabViewModel: nil, browsingMode: .fire, onConfirm: { request in
            capturedRequest = request
        })
        
        // When
        sut.buttons[0].action()
        
        // Then
        if case .fireMode = capturedRequest?.scope {
            // Expected scope
        } else {
            XCTFail("Expected scope to be .fireMode")
        }
    }
    
    func testWhenNormalTabThenSecondButtonFiresTabScope() {
        // Given
        var capturedRequest: FireRequest?
        let tabViewModel = createTabViewModel()
        let sut = makeSUT(tabViewModel: tabViewModel, onConfirm: { request in
            capturedRequest = request
        })
        
        // When
        XCTAssertEqual(sut.buttons.count, 2)
        sut.buttons[1].action()
        
        // Then
        if case .tab(let vm) = capturedRequest?.scope {
            XCTAssertTrue(vm.tab == tabViewModel.tab)
        } else {
            XCTFail("Expected scope to be .tab")
        }
    }
    
    // MARK: - cancel Tests
    
    func testWhenCancelCalledThenOnCancelIsCalled() {
        // Given
        var cancelCalled = false
        let sut = makeSUT(tabViewModel: nil, onCancel: {
            cancelCalled = true
        })
        
        // When
        sut.cancel()
        
        // Then
        XCTAssertTrue(cancelCalled)
    }
    
    // MARK: - Button Layout Tests
    
    func testWhenNoTabThenSingleDeleteAllButton() {
        // Given
        let sut = makeSUT(tabViewModel: nil)
        
        // Then
        XCTAssertEqual(sut.buttons.count, 1)
        XCTAssertEqual(sut.buttons[0].title, UserText.scopedFireConfirmationDeleteAllButton)
        XCTAssertEqual(sut.buttons[0].style, .primary)
    }
    
    func testWhenNormalTabThenTwoButtonsDeleteAllFirst() {
        // Given
        let sut = makeSUT(tabViewModel: createTabViewModel())
        
        // Then
        XCTAssertEqual(sut.buttons.count, 2)
        XCTAssertEqual(sut.buttons[0].title, UserText.scopedFireConfirmationDeleteAllButton)
        XCTAssertEqual(sut.buttons[0].style, .primary)
        XCTAssertEqual(sut.buttons[1].title, UserText.scopedFireConfirmationDeleteThisTabButton)
        XCTAssertEqual(sut.buttons[1].style, .secondary)
    }
    
    func testWhenLegacyTabThenSingleDeleteAllButton() {
        // Given
        let legacyTab = Tab(supportsTabHistory: false)
        let tabViewModel = TabViewModel(tab: legacyTab, historyManager: mockHistoryManager)
        let sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then
        XCTAssertEqual(sut.buttons.count, 1)
        XCTAssertEqual(sut.buttons[0].title, UserText.scopedFireConfirmationDeleteAllButton)
    }

    // MARK: - DuckAI Onboarding Context Tests

    func testWhenDuckAIOnboardingContextAndAITabThenSingleDeleteChatButtonShown() {
        // Given
        let aiTabViewModel = TabViewModel(tab: createAITab(), historyManager: mockHistoryManager)
        let sut = makeSUT(tabViewModel: aiTabViewModel, fireContext: .duckAIOnboarding)

        // Then
        XCTAssertEqual(sut.buttons.count, 1)
        XCTAssertEqual(sut.buttons[0].title, UserText.contextualChatDeleteConfirmationButton)
        XCTAssertEqual(sut.buttons[0].style, .primary)
    }

    func testWhenDuckAIOnboardingContextAndWebTabThenNoButtonsShown() {
        // Given
        let webTabViewModel = createTabViewModel()
        let sut = makeSUT(tabViewModel: webTabViewModel, fireContext: .duckAIOnboarding)

        // Then
        XCTAssertTrue(sut.buttons.isEmpty)
    }

    func testWhenDuckAIOnboardingContextThenHeaderTitleUsesContextualChatDeleteCopy() {
        // Given
        let sut = makeSUT(tabViewModel: createAITabViewModel(), fireContext: .duckAIOnboarding)

        // Then
        XCTAssertEqual(sut.headerTitle, UserText.contextualChatDeleteConfirmationTitle)
    }

    func testWhenDuckAIOnboardingContextThenNoDeleteAllButton() {
        // Given
        let sut = makeSUT(tabViewModel: createAITabViewModel(), fireContext: .duckAIOnboarding)

        // Then
        XCTAssertFalse(sut.buttons.contains { $0.title == UserText.scopedFireConfirmationDeleteAllButton })
    }

    func testWhenDuckAIOnboardingContextThenSubtitleIsNil() {
        // Given
        let sut = makeSUT(tabViewModel: createAITabViewModel(), fireContext: .duckAIOnboarding)

        // Then
        XCTAssertNil(sut.subtitle)
    }

    func testWhenDuckAIOnboardingContextAndDeleteChatTappedThenRequestUsesAIChatsOption() {
        // Given
        var capturedRequest: FireRequest?
        let aiTabViewModel = createAITabViewModel()
        let sut = makeSUT(tabViewModel: aiTabViewModel, fireContext: .duckAIOnboarding, onConfirm: { request in
            capturedRequest = request
        })

        // When
        sut.buttons[0].action()

        // Then
        XCTAssertNotNil(capturedRequest)
        XCTAssertEqual(capturedRequest?.options, [.aiChats])
        XCTAssertEqual(capturedRequest?.trigger, .manualFire)
        if case .tab(let vm) = capturedRequest?.scope {
            XCTAssertTrue(vm.tab == aiTabViewModel.tab)
        } else {
            XCTFail("Expected scope to be .tab with the correct view model")
        }
    }
    
    // MARK: - subtitle Tests - Ongoing Downloads
    
    func testWhenOngoingDownloadsExistThenSubtitleIsDownloadsWarning() {
        // Given
        let runningDownload = createRunningDownload()
        mockDownloadManager.downloadList = [runningDownload]
        
        // When
        let sut = makeSUT(tabViewModel: createTabViewModel())
        
        // Then
        XCTAssertEqual(sut.subtitle, UserText.scopedFireConfirmationDownloadsWarning)
    }
    
    // MARK: - subtitle Tests - No Tab View Model
    
    func testWhenNoTabViewModelThenSubtitleIsNil() {
        // Given/When
        let sut = makeSUT(tabViewModel: nil)
        
        // Then
        XCTAssertNil(sut.subtitle)
    }
    
    // MARK: - subtitle Tests - Tab Without History Support
    
    func testWhenTabDoesNotSupportTabHistoryThenSubtitleIsNewTabsInfo() {
        // Given
        let legacyTab = Tab(supportsTabHistory: false)
        let tabViewModel = TabViewModel(tab: legacyTab, historyManager: mockHistoryManager)
        
        // When
        let sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then
        XCTAssertEqual(sut.subtitle, UserText.scopedFireConfirmationNewTabsInfo)
    }
    
    // MARK: - subtitle Tests - Fire Mode
    
    func testWhenBrowsingModeIsFireThenSubtitleIsNil() {
        // Given
        let tabViewModel = createTabViewModel()
        
        // When
        let sut = makeSUT(tabViewModel: tabViewModel, browsingMode: .fire)
        
        // Then
        XCTAssertNil(sut.subtitle)
    }
    
    // MARK: - subtitle Tests - AI Tab
    
    func testAITabSubtitle() {
        // Given
        let aiTab = createAITab()
        let tabViewModel = TabViewModel(tab: aiTab, historyManager: mockHistoryManager)
        
        // When ai clearing enabled
        mockAppSettings.autoClearAIChatHistory = true
        var sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then don't show subtitle
        XCTAssertNil(sut.subtitle)

        // When ai clearing disabled
        mockAppSettings.autoClearAIChatHistory = false
        sut = makeSUT(tabViewModel: tabViewModel)

        // Then show subtitle
        XCTAssertEqual(sut.subtitle, UserText.scopedFireConfirmationDeleteThisChatDescription)
    }
    
    // MARK: - subtitle Tests - Web Tab
    
    func testWhenWebTabFirstTimeThenSubtitleIsSignOutWarning() {
        // Given
        let tabViewModel = createTabViewModel()
        
        // When first time
        var sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then show subtitle
        XCTAssertEqual(sut.subtitle, UserText.scopedFireConfirmationSignOutWarning)
        
        // When second time
        sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then show subtitle
        XCTAssertEqual(sut.subtitle, UserText.scopedFireConfirmationSignOutWarning)
        
        // When more than two times
        sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then don't show subtitle
        XCTAssertNil(sut.subtitle)
    }
    
    // MARK: - subtitle Tests - Dax Dialogs (Onboarding)
    
    func testWhenDaxDialogsIsShowingFireDialogThenSubtitleIsNil() {
        // Given
        let mockDaxDialogsManager = MockDaxDialogsManager()
        mockDaxDialogsManager.isShowingFireDialog = true
        let tabViewModel = createTabViewModel()
        
        // When
        let sut = makeSUT(tabViewModel: tabViewModel, fireContext: .default(daxDialogsManager: mockDaxDialogsManager))
        
        // Then - subtitle is nil even though it would normally show sign out warning
        XCTAssertNil(sut.subtitle)
    }
    
    // MARK: - subtitle Tests - Priority
    
    func testWhenOngoingDownloadsExistEvenForAITabThenSubtitleIsDownloadsWarning() {
        // Given
        let runningDownload = createRunningDownload()
        mockDownloadManager.downloadList = [runningDownload]
        let aiTab = createAITab()
        let tabViewModel = TabViewModel(tab: aiTab, historyManager: mockHistoryManager)
        
        // When
        let sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then - downloads warning takes priority over AI description
        XCTAssertEqual(sut.subtitle, UserText.scopedFireConfirmationDownloadsWarning)
    }
    
    func testWhenLegacyTabWithOngoingDownloadsThenSubtitleIsDownloadsWarning() {
        // Given
        let runningDownload = createRunningDownload()
        mockDownloadManager.downloadList = [runningDownload]
        let legacyTab = Tab(supportsTabHistory: false)
        let tabViewModel = TabViewModel(tab: legacyTab, historyManager: mockHistoryManager)
        
        // When
        let sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then - downloads warning takes priority
        XCTAssertEqual(sut.subtitle, UserText.scopedFireConfirmationDownloadsWarning)
    }
    
    // MARK: - Fire Button Refinements Tests

    func testWhenRefinementsEnabledOnAITabThenSingleDeleteChatButton() {
        // Given
        mockDataClearingCapability.isFireButtonRefinementsEnabled = true
        let tabViewModel = TabViewModel(tab: createAITab(), historyManager: mockHistoryManager)

        // When
        let sut = makeSUT(tabViewModel: tabViewModel)

        // Then
        XCTAssertEqual(sut.buttons.count, 1)
        XCTAssertEqual(sut.buttons[0].title, UserText.scopedFireConfirmationDeleteThisChatButton)
        XCTAssertEqual(sut.buttons[0].style, .primary)
        XCTAssertEqual(sut.headerTitle, UserText.contextualChatDeleteConfirmationTitle)
    }

    func testWhenRefinementsDisabledOnAITabThenTwoButtonsDeleteAllFirst() {
        // Given
        mockDataClearingCapability.isFireButtonRefinementsEnabled = false
        let tabViewModel = TabViewModel(tab: createAITab(), historyManager: mockHistoryManager)

        // When
        let sut = makeSUT(tabViewModel: tabViewModel)

        // Then
        XCTAssertEqual(sut.buttons.count, 2)
        XCTAssertEqual(sut.buttons[0].title, UserText.scopedFireConfirmationDeleteAllButton)
        XCTAssertEqual(sut.buttons[0].style, .primary)
    }

    func testWhenRefinementsEnabledOnAITabThenSubtitleIsNil() {
        // Given
        mockDataClearingCapability.isFireButtonRefinementsEnabled = true
        mockAppSettings.autoClearAIChatHistory = false
        let tabViewModel = TabViewModel(tab: createAITab(), historyManager: mockHistoryManager)

        // When
        let sut = makeSUT(tabViewModel: tabViewModel)

        // Then
        XCTAssertNil(sut.subtitle)
    }

    func testWhenRefinementsEnabledOnAITabThenButtonBurnsSingleChat() {
        // Given
        mockDataClearingCapability.isFireButtonRefinementsEnabled = true
        var capturedRequest: FireRequest?
        let tabViewModel = TabViewModel(tab: createAITab(), historyManager: mockHistoryManager)
        let sut = makeSUT(tabViewModel: tabViewModel, onConfirm: { capturedRequest = $0 })

        // When
        sut.buttons[0].action()

        // Then
        if case .tab = capturedRequest?.scope {
            // Expected single tab scope
        } else {
            XCTFail("Expected scope to be .tab for AI-only mode")
        }
    }

    func testWhenRefinementsEnabledOnNormalTabThenDeleteThisTabIsPrimary() {
        // Given
        mockDataClearingCapability.isFireButtonRefinementsEnabled = true

        // When
        let sut = makeSUT(tabViewModel: createTabViewModel())

        // Then
        XCTAssertEqual(sut.buttons.count, 2)
        XCTAssertEqual(sut.buttons[0].title, UserText.scopedFireConfirmationDeleteThisTabButton)
        XCTAssertEqual(sut.buttons[0].style, .primary)
        XCTAssertEqual(sut.buttons[1].title, UserText.scopedFireConfirmationDeleteAllButton)
        XCTAssertEqual(sut.buttons[1].style, .secondary)
    }

    func testWhenRefinementsDisabledOnNormalTabThenDeleteAllIsPrimary() {
        // Given
        mockDataClearingCapability.isFireButtonRefinementsEnabled = false

        // When
        let sut = makeSUT(tabViewModel: createTabViewModel())

        // Then
        XCTAssertEqual(sut.buttons.count, 2)
        XCTAssertEqual(sut.buttons[0].title, UserText.scopedFireConfirmationDeleteAllButton)
        XCTAssertEqual(sut.buttons[0].style, .primary)
        XCTAssertEqual(sut.buttons[1].title, UserText.scopedFireConfirmationDeleteThisTabButton)
        XCTAssertEqual(sut.buttons[1].style, .secondary)
    }

    // MARK: - Single Tab Context Tests

    func testWhenSingleTabContextThenSingleDeleteTabButton() {
        // When
        let sut = makeSUT(tabViewModel: createTabViewModel(), fireContext: .singleTab)

        // Then
        XCTAssertEqual(sut.buttons.count, 1)
        XCTAssertEqual(sut.buttons[0].title, UserText.scopedFireConfirmationDeleteTabButton)
        XCTAssertEqual(sut.buttons[0].style, .primary)
    }

    func testWhenSingleTabContextThenTitleIsSingleTabAlertTitle() {
        // When
        let sut = makeSUT(tabViewModel: createTabViewModel(), fireContext: .singleTab)

        // Then
        XCTAssertEqual(sut.headerTitle, UserText.scopedFireConfirmationAlertSingleTabTitle)
    }

    func testWhenSingleTabContextThenSubtitleIsNil() {
        // When
        let sut = makeSUT(tabViewModel: createTabViewModel(), fireContext: .singleTab)

        // Then
        XCTAssertNil(sut.subtitle)
    }

    func testWhenSingleTabContextButtonTappedThenBurnsTargetTab() {
        // Given
        var capturedRequest: FireRequest?
        let tabViewModel = createTabViewModel()
        let sut = makeSUT(tabViewModel: tabViewModel,
                          fireContext: .singleTab,
                          onConfirm: { capturedRequest = $0 })

        // When
        sut.buttons[0].action()

        // Then
        XCTAssertNotNil(capturedRequest)
        XCTAssertEqual(capturedRequest?.options, .all)
        XCTAssertEqual(capturedRequest?.trigger, .manualFire)
        if case .tab(let vm) = capturedRequest?.scope {
            XCTAssertTrue(vm.tab == tabViewModel.tab)
        } else {
            XCTFail("Expected scope to be .tab with the target view model")
        }
    }

    // MARK: - Single Tab "Delete All" Only Tests

    func testWhenSingleTabThenOnlyDeleteAllShown() {
        // Given
        mockDataClearingCapability.isFireButtonRefinementsEnabled = true

        // When
        let sut = makeSUT(tabViewModel: createTabViewModel(), isSingleTab: true)

        // Then
        XCTAssertEqual(sut.buttons.count, 1)
        XCTAssertEqual(sut.buttons[0].title, UserText.scopedFireConfirmationDeleteAllButton)
        XCTAssertEqual(sut.buttons[0].style, .primary)
    }

    func testWhenSingleTabWithRefinementsDisabledThenOnlyDeleteAllShown() {
        // Given
        mockDataClearingCapability.isFireButtonRefinementsEnabled = false

        // When
        let sut = makeSUT(tabViewModel: createTabViewModel(), isSingleTab: true)

        // Then
        XCTAssertEqual(sut.buttons.count, 1)
        XCTAssertEqual(sut.buttons[0].title, UserText.scopedFireConfirmationDeleteAllButton)
        XCTAssertEqual(sut.buttons[0].style, .primary)
    }

    func testWhenMultipleTabsThenNormalButtons() {
        // Given
        mockDataClearingCapability.isFireButtonRefinementsEnabled = true

        // When
        let sut = makeSUT(tabViewModel: createTabViewModel(), isSingleTab: false)

        // Then
        XCTAssertEqual(sut.buttons.count, 2)
        XCTAssertEqual(sut.buttons[0].title, UserText.scopedFireConfirmationDeleteThisTabButton)
        XCTAssertEqual(sut.buttons[1].title, UserText.scopedFireConfirmationDeleteAllButton)
    }

    func testWhenSingleAITabThenChatConfirmationUnaffected() {
        // Given
        mockDataClearingCapability.isFireButtonRefinementsEnabled = true

        // When
        let sut = makeSUT(tabViewModel: createAITabViewModel(), isSingleTab: true)

        // Then
        XCTAssertEqual(sut.buttons.count, 1)
        XCTAssertEqual(sut.buttons[0].title, UserText.scopedFireConfirmationDeleteThisChatButton)
    }

    func testWhenSingleTabDeleteAllShownThenTitleIsSingular() {
        // Given
        mockDataClearingCapability.isFireButtonRefinementsEnabled = true

        // When
        let sut = makeSUT(tabViewModel: createTabViewModel(), isSingleTab: true)

        // Then
        XCTAssertEqual(sut.headerTitle, UserText.scopedFireConfirmationAlertSingleTabTitle)
    }

    func testWhenSingleTabDeleteAllTappedThenBurnsAll() {
        // Given
        var capturedRequest: FireRequest?
        mockDataClearingCapability.isFireButtonRefinementsEnabled = true
        let sut = makeSUT(tabViewModel: createTabViewModel(),
                          isSingleTab: true,
                          onConfirm: { capturedRequest = $0 })

        // When
        sut.buttons[0].action()

        // Then
        XCTAssertNotNil(capturedRequest)
        XCTAssertEqual(capturedRequest?.options, .all)
        XCTAssertEqual(capturedRequest?.trigger, .manualFire)
        if case .all = capturedRequest?.scope {
            // Expected all-scope burn
        } else {
            XCTFail("Expected scope to be .all")
        }
    }

    func testSwipeToDeleteUsesRemoteFlagWithInternalOnlyDefault() {
        let flag = FeatureFlag.swipeToDelete
        guard case let .remoteReleasable(subfeature) = flag.source else {
            return XCTFail("Expected remote flag")
        }
        XCTAssertEqual(subfeature as? iOSBrowserConfigSubfeature, .swipeToDelete)
        guard case .internalOnly = flag.defaultValue else {
            return XCTFail("Expected internal-only default")
        }
        XCTAssertTrue(flag.supportsLocalOverriding)
    }

    func testSwipeToDeleteFlagChangesOnNextPresentation() {
        let tab = createTabViewModel()
        let disabled = makeSUT(tabViewModel: tab)
        XCTAssertFalse(disabled.buttons.contains { $0.style == .slide })

        mockFeatureFlagger.enabledFeatureFlags = [.swipeToDelete]
        let enabled = makeSUT(tabViewModel: tab)
        let slider = enabled.buttons.first { $0.style == .slide }
        XCTAssertEqual(slider?.title, UserText.scopedFireConfirmationSlideToDeleteAll)
        XCTAssertEqual(slider?.accessibilityIdentifier, "alert.forget-data.confirm")
        XCTAssertTrue(enabled.buttons.filter { $0.accessibilityIdentifier == "Fire.Confirmation.Button.ThisTab" }.allSatisfy { $0.style != .slide })
        XCTAssertFalse(disabled.buttons.contains { $0.style == .slide })

        mockFeatureFlagger.enabledFeatureFlags = []
        XCTAssertFalse(makeSUT(tabViewModel: tab).buttons.contains { $0.style == .slide })
    }

    func testSliderPreservesDeleteAllScopeInBothBrowsingModes() {
        mockFeatureFlagger.enabledFeatureFlags = [.swipeToDelete]
        for mode: BrowsingMode in [.normal, .fire] {
            var request: FireRequest?
            let sut = makeSUT(tabViewModel: nil, isSingleTab: true, browsingMode: mode, onConfirm: { request = $0 })
            let slider = sut.buttons.first { $0.style == .slide }
            XCTAssertNotNil(slider)
            slider?.action()
            XCTAssertEqual(request?.options, .all)
            XCTAssertEqual(request?.trigger, .manualFire)
            switch (mode, request?.scope) {
            case (.normal, .all), (.fire, .fireMode): break
            default: XCTFail("Unexpected delete-all scope")
            }
        }
    }

    func testSwipeToDeleteDoesNotChangeScopedConfirmations() {
        mockFeatureFlagger.enabledFeatureFlags = [.swipeToDelete]
        let contexts: [ScopedFireConfirmationViewModel.FireContext] = [
            .singleTab, .contextualChat(onDelete: {}), .duckAIOnboarding,
            .custom(title: "History", subtitle: "", action: "Delete"),
            .deleteChats(count: 2, onDelete: {})
        ]
        for context in contexts {
            let sut = makeSUT(tabViewModel: createAITabViewModel(), fireContext: context)
            XCTAssertFalse(sut.buttons.contains { $0.style == .slide })
        }
    }

    func testSlideRequiresFullForwardDragAndCompletesOnlyOnce() {
        var state = SlideToDeleteState()
        XCTAssertEqual(state.progress(translation: -20, travel: 200), 0)
        XCTAssertEqual(state.progress(translation: 100, travel: 200), 0.5)
        XCTAssertEqual(state.progress(translation: 300, travel: 200), 1)
        XCTAssertFalse(state.complete(translation: 0, travel: 200))
        XCTAssertFalse(state.complete(translation: -200, travel: 200))
        XCTAssertFalse(state.complete(translation: 188, travel: 200))
        XCTAssertFalse(state.complete(translation: 200, travel: 0))
        XCTAssertFalse(state.isComplete)
        XCTAssertTrue(state.complete(translation: 200, travel: 200))
        XCTAssertTrue(state.isComplete)
        XCTAssertFalse(state.complete(translation: 200, travel: 200))
    }

    func testSlideHapticRearmsWhenMovingBelowCompletionThreshold() {
        var state = SlideToDeleteState()
        XCTAssertFalse(state.updateDrag(translation: -200, travel: 200))
        XCTAssertFalse(state.updateDrag(translation: 200, travel: 0))
        XCTAssertFalse(state.updateDrag(translation: 188, travel: 200))
        XCTAssertTrue(state.updateDrag(translation: 190, travel: 200))
        XCTAssertFalse(state.isComplete)
        XCTAssertFalse(state.updateDrag(translation: 200, travel: 200))
        XCTAssertFalse(state.updateDrag(translation: 189, travel: 200))
        XCTAssertTrue(state.updateDrag(translation: 191, travel: 200))
        XCTAssertFalse(state.updateDrag(translation: 200, travel: 200))
        XCTAssertFalse(state.complete(translation: 100, travel: 200))
        XCTAssertFalse(state.isComplete)
    }

    func testSlideHapticResetsAfterCancelledDrag() {
        var state = SlideToDeleteState()
        XCTAssertTrue(state.updateDrag(translation: 190, travel: 200))
        XCTAssertFalse(state.complete(translation: 100, travel: 200))
        state.resetDrag()
        XCTAssertFalse(state.updateDrag(translation: 188, travel: 200))
        XCTAssertTrue(state.updateDrag(translation: 190, travel: 200))
    }

    func testCompletedSlideDoesNotProvideMoreHaptics() {
        var state = SlideToDeleteState()
        XCTAssertTrue(state.updateDrag(translation: 190, travel: 200))
        XCTAssertTrue(state.complete(translation: 200, travel: 200))
        state.resetDrag()
        XCTAssertFalse(state.updateDrag(translation: 200, travel: 200))
    }

    func testFastSlideRequestsHapticWhenOnlyReleaseReachesThreshold() {
        var state = SlideToDeleteState()
        XCTAssertFalse(state.updateDrag(translation: 150, travel: 200))
        XCTAssertTrue(state.endDrag(translation: 200, travel: 200))
        XCTAssertTrue(state.isComplete)
        XCTAssertFalse(state.shouldShowCompletionLabel)
        XCTAssertFalse(state.endDrag(translation: 200, travel: 200))
    }

    func testReleaseDoesNotRepeatThresholdHaptic() {
        var state = SlideToDeleteState()
        XCTAssertTrue(state.updateDrag(translation: 195, travel: 200))
        XCTAssertFalse(state.endDrag(translation: 200, travel: 200))
        XCTAssertTrue(state.isComplete)
    }

    func testLabelRequiresCurrentHoldAndHidesOnRelease() {
        var state = SlideToDeleteState()
        XCTAssertFalse(state.revealCompletionLabel(for: state.thresholdEntryCount))
        XCTAssertTrue(state.updateDrag(translation: 200, travel: 200))
        let entry = state.thresholdEntryCount
        XCTAssertFalse(state.shouldShowCompletionLabel)
        XCTAssertTrue(state.revealCompletionLabel(for: entry))
        XCTAssertTrue(state.shouldShowCompletionLabel)
        XCTAssertFalse(state.revealCompletionLabel(for: entry))
        XCTAssertFalse(state.endDrag(translation: 200, travel: 200))
        XCTAssertTrue(state.isComplete)
        XCTAssertFalse(state.shouldShowCompletionLabel)
        XCTAssertFalse(state.revealCompletionLabel(for: entry))
    }

    func testMovingBackCancelsLabelAndInvalidatesEarlierHold() {
        var state = SlideToDeleteState()
        XCTAssertTrue(state.updateDrag(translation: 200, travel: 200))
        let firstEntry = state.thresholdEntryCount
        XCTAssertTrue(state.revealCompletionLabel(for: firstEntry))
        XCTAssertFalse(state.updateDrag(translation: 100, travel: 200))
        XCTAssertFalse(state.shouldShowCompletionLabel)
        XCTAssertFalse(state.revealCompletionLabel(for: firstEntry))
        XCTAssertTrue(state.updateDrag(translation: 200, travel: 200))
        XCTAssertFalse(state.revealCompletionLabel(for: firstEntry))
        XCTAssertTrue(state.revealCompletionLabel(for: state.thresholdEntryCount))
        state.resetDrag()
        XCTAssertFalse(state.shouldShowCompletionLabel)
        XCTAssertFalse(state.revealCompletionLabel(for: state.thresholdEntryCount))
    }

    func testSlideFeedbackIsAttachedToControlView() {
        let feedback = SlideToDeleteFeedback()
        XCTAssertFalse(feedback.impact())
        let view = UIView()
        feedback.attach(to: view)
        if #available(iOS 17.5, *) {
            XCTAssertEqual(view.interactions.filter { $0 is UIImpactFeedbackGenerator }.count, 1)
        }
        XCTAssertTrue(feedback.impact())
    }

    func testSlideTouchFeedbackFiresOncePerTouchAndRearmsAfterRelease() {
        let feedback = SlideToDeleteFeedback()
        let view = UIView()
        feedback.attach(to: view)
        XCTAssertTrue(feedback.beginTouch())
        XCTAssertFalse(feedback.beginTouch())
        feedback.endTouch()
        XCTAssertTrue(feedback.beginTouch())
        XCTAssertFalse(feedback.beginTouch())
        feedback.endTouch()
    }

    func testSlideStyleDefaultsToGlassOnlyWhenAvailable() {
        XCTAssertEqual(SlideToDeleteStyle.defaultValue(isGlassAvailable: true), .glass)
        XCTAssertEqual(SlideToDeleteStyle.defaultValue(isGlassAvailable: false), .original)
    }

    func testSlideStyleHonorsOriginalAndFallsBackForUnsupportedGlass() {
        XCTAssertEqual(SlideToDeleteStyle.original.resolved(isGlassAvailable: true), .original)
        XCTAssertEqual(SlideToDeleteStyle.original.resolved(isGlassAvailable: false), .original)
        XCTAssertEqual(SlideToDeleteStyle.glass.resolved(isGlassAvailable: true), .glass)
        XCTAssertEqual(SlideToDeleteStyle.glass.resolved(isGlassAvailable: false), .original)
    }

    // MARK: - Helpers

    private func makeSUT(tabViewModel: TabViewModel?,
                         source: FireRequest.Source = .browsing,
                         fireContext: ScopedFireConfirmationViewModel.FireContext = .default(daxDialogsManager: MockDaxDialogsManager()),
                         isSingleTab: Bool = false,
                         browsingMode: BrowsingMode = .normal,
                         onConfirm: @escaping (FireRequest) -> Void = { _ in },
                         onCancel: @escaping () -> Void = { }) -> ScopedFireConfirmationViewModel {
        return ScopedFireConfirmationViewModel(tabViewModel: tabViewModel,
                                               source: source,
                                               fireContext: fireContext,
                                               isSingleTab: isSingleTab,
                                               downloadManager: mockDownloadManager,
                                               keyValueStore: mockKeyValueStore,
                                               appSettings: mockAppSettings,
                                               dataClearingCapability: mockDataClearingCapability,
                                               featureFlagger: mockFeatureFlagger,
                                               browsingMode: browsingMode,
                                               onConfirm: onConfirm,
                                               onCancel: onCancel)
    }
    
    private func createTabViewModel() -> TabViewModel {
        let tab = Tab()
        return TabViewModel(tab: tab, historyManager: mockHistoryManager)
    }
    
    private func createAITab() -> Tab {
        let aiChatURL = URL(string: "https://duckduckgo.com/?ia=chat")!
        let link = Link(title: "AI Chat", url: aiChatURL)
        return Tab(link: link)
    }

    private func createAITabViewModel() -> TabViewModel {
        let aiTab = createAITab()
        return TabViewModel(tab: aiTab, historyManager: mockHistoryManager)
    }
    
    private func createRunningDownload(temporary: Bool = false) -> Download {
        let mockSession = MockDownloadSession()
        mockSession.isRunning = true
        return Download(url: URL(string: "https://example.com/file.zip")!,
                        filename: "file.zip",
                        mimeType: .unknown,
                        temporary: temporary,
                        downloadSession: mockSession)
    }
}

// MARK: - MockKeyValueStore

private class MockKeyValueStore: KeyValueStoring {
    private var storage: [String: Any] = [:]
    
    func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }
    
    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }
    
    func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }
}
