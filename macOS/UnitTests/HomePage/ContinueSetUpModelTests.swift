//
//  ContinueSetUpModelTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Common
import NewTabPage
import PixelKit
import SubscriptionTestingUtilities

@testable import Subscription
@testable import DuckDuckGo_Privacy_Browser

final class ContinueSetUpModelTests: XCTestCase {

    var vm: HomePage.Models.ContinueSetUpModel!
    var capturingDefaultBrowserProvider: CapturingDefaultBrowserProvider!
    var capturingDataImportProvider: CapturingDataImportProvider!
    var tabCollectionVM: TabCollectionViewModel!
    var emailManager: EmailManager!
    var emailStorage: MockEmailStorage!
    var duckPlayerPreferences: DuckPlayerPreferencesPersistor!
    var coookiePopupProtectionPreferences: MockCookiePopupProtectionPreferencesPersistor!
    var privacyConfigManager: MockPrivacyConfigurationManager!
    var dockCustomizer: DockCustomization!
    var userDefaults: UserDefaults! = UserDefaults(suiteName: "\(Bundle.main.bundleIdentifier!).\(AppVersion.runType)")!
    var subscriptionCardVisibilityManager: MockHomePageSubscriptionCardVisibilityManaging!
    var homePageContinueSetUpModelPersisting: MockHomePageContinueSetUpModelPersisting!

    var firedPixels: [(event: PixelKitEvent, includesAppVersionParameter: Bool)] = []

    @MainActor override func setUp() {
        UserDefaultsWrapper<Any>.clearAll()
        userDefaults.set(Date(), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)
        capturingDefaultBrowserProvider = CapturingDefaultBrowserProvider()
        capturingDataImportProvider = CapturingDataImportProvider()
        tabCollectionVM = TabCollectionViewModel(isPopup: false)
        emailStorage = MockEmailStorage()
        emailManager = EmailManager(storage: emailStorage)
        duckPlayerPreferences = DuckPlayerPreferencesPersistorMock()
        privacyConfigManager = MockPrivacyConfigurationManager()
        let config = MockPrivacyConfiguration()
        privacyConfigManager.mockPrivacyConfig = config
        dockCustomizer = DockCustomizerMock()
        subscriptionCardVisibilityManager = MockHomePageSubscriptionCardVisibilityManaging()
        homePageContinueSetUpModelPersisting = MockHomePageContinueSetUpModelPersisting()

        firedPixels = []

        vm = HomePage.Models.ContinueSetUpModel(
            defaultBrowserProvider: capturingDefaultBrowserProvider,
            dockCustomizer: dockCustomizer,
            dataImportProvider: capturingDataImportProvider,
            tabOpener: TabCollectionViewModelTabOpener(tabCollectionViewModel: tabCollectionVM),
            emailManager: emailManager,
            duckPlayerPreferences: duckPlayerPreferences,
            privacyConfigurationManager: privacyConfigManager,
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
            persistor: homePageContinueSetUpModelPersisting,
            pixelHandler: { pixel, includesAppVersionParameter in
                self.firedPixels.append((pixel, includesAppVersionParameter))
            }
        )
    }

    override func tearDown() {
        UserDefaultsWrapper<Any>.clearAll()
        capturingDefaultBrowserProvider = nil
        capturingDataImportProvider = nil
        tabCollectionVM = nil
        emailManager = nil
        emailStorage = nil
        vm = nil
        dockCustomizer = nil
        duckPlayerPreferences = nil
        privacyConfigManager = nil
        userDefaults = nil
        subscriptionCardVisibilityManager = nil
        homePageContinueSetUpModelPersisting = nil
        firedPixels = []
    }

    func testModelReturnsCorrectStrings() {
        XCTAssertEqual(vm.itemsPerRow, HomePage.Models.ContinueSetUpModel.Const.featuresPerRow)
    }

    func testModelReturnsCorrectDimensions() {
        XCTAssertEqual(vm.itemWidth, HomePage.Models.FeaturesGridDimensions.itemWidth)
        XCTAssertEqual(vm.itemHeight, HomePage.Models.FeaturesGridDimensions.itemHeight)
        XCTAssertEqual(vm.horizontalSpacing, HomePage.Models.FeaturesGridDimensions.horizontalSpacing)
        XCTAssertEqual(vm.verticalSpacing, HomePage.Models.FeaturesGridDimensions.verticalSpacing)
        XCTAssertEqual(vm.gridWidth, HomePage.Models.FeaturesGridDimensions.width)
        XCTAssertEqual(vm.itemsPerRow, 2)
    }

    @MainActor func testIsMoreOrLessButtonNeededReturnTheExpectedValue() {
        XCTAssertTrue(vm.isMoreOrLessButtonNeeded)

        capturingDefaultBrowserProvider.isDefault = true
        capturingDataImportProvider.didImport = true
        duckPlayerPreferences.youtubeOverlayAnyButtonPressed = true
        subscriptionCardVisibilityManager.shouldShowSubscriptionCard = false

        vm = HomePage.Models.ContinueSetUpModel(
            defaultBrowserProvider: capturingDefaultBrowserProvider,
            dockCustomizer: dockCustomizer,
            dataImportProvider: capturingDataImportProvider,
            tabOpener: TabCollectionViewModelTabOpener(tabCollectionViewModel: tabCollectionVM),
            emailManager: emailManager,
            duckPlayerPreferences: duckPlayerPreferences,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
            persistor: homePageContinueSetUpModelPersisting,
            pixelHandler: { _, _ in }
        )

        XCTAssertFalse(vm.isMoreOrLessButtonNeeded)
    }

    @MainActor func testWhenInitializedForTheFirstTimeTheMatrixHasAllElementsInTheRightOrder() {
        homePageContinueSetUpModelPersisting.isFirstSession = true
        var expectedMatrix = [[HomePage.Models.FeatureType.duckplayer, .emailProtection]]
        vm = HomePage.Models.ContinueSetUpModel(
            defaultBrowserProvider: capturingDefaultBrowserProvider,
            dockCustomizer: dockCustomizer,
            dataImportProvider: capturingDataImportProvider,
            tabOpener: TabCollectionViewModelTabOpener(tabCollectionViewModel: tabCollectionVM),
            emailManager: emailManager,
            duckPlayerPreferences: duckPlayerPreferences,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
            persistor: homePageContinueSetUpModelPersisting
        )

        XCTAssertEqual(vm.visibleFeaturesMatrix, expectedMatrix)

        vm.shouldShowAllFeatures = true

        expectedMatrix = expectedFeatureMatrixWithout(types: [])

        XCTAssertEqual(vm.visibleFeaturesMatrix, expectedMatrix)
    }

    @MainActor func testWhenInitializedNotForTheFirstTimeTheMatrixHasAllElementsInTheRightOrder() {
        homePageContinueSetUpModelPersisting.isFirstSession = false
        vm = HomePage.Models.ContinueSetUpModel.fixture(persistor: homePageContinueSetUpModelPersisting)
        vm.shouldShowAllFeatures = true

        XCTAssertEqual(vm.visibleFeaturesMatrix[0][0], HomePage.Models.FeatureType.defaultBrowser)
        XCTAssertEqual(vm.visibleFeaturesMatrix.reduce([], +).count, HomePage.Models.FeatureType.allCases.count)
    }

    func testWhenTogglingShowAllFeatureThenCorrectElementsAreVisible() {
        let expectedMatrix = expectedFeatureMatrixWithout(types: [])

        vm.shouldShowAllFeatures = true

        XCTAssertTrue(doTheyContainTheSameElements(matrix1: vm.visibleFeaturesMatrix, matrix2: expectedMatrix))

        vm.shouldShowAllFeatures = false

        XCTAssertEqual(vm.visibleFeaturesMatrix.count, 1)
        XCTAssertTrue(vm.visibleFeaturesMatrix[0].count <= vm.itemsPerRow)
    }

    @MainActor func testWhenAskedToPerformActionForDefaultBrowserCardThenItPresentsTheDefaultBrowserPrompt() {
        vm.performAction(for: .defaultBrowser)

        XCTAssertTrue(capturingDefaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertFalse(capturingDefaultBrowserProvider.openSystemPreferencesCalled)
    }

    @MainActor func testWhenAskedToPerformActionForDefaultBrowserCardAndDefaultBrowserPromptThrowsThenItOpensSystemPreferences() {
        capturingDefaultBrowserProvider.throwError = true
        vm.performAction(for: .defaultBrowser)

        XCTAssertTrue(capturingDefaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertTrue(capturingDefaultBrowserProvider.openSystemPreferencesCalled)
    }

    @MainActor func testWhenIsDefaultBrowserAndTogglingShowAllFeatureThenCorrectElementsAreVisible() {
        let expectedMatrix = expectedFeatureMatrixWithout(types: [.defaultBrowser])

        capturingDefaultBrowserProvider.isDefault = true
        vm = HomePage.Models.ContinueSetUpModel.fixture(defaultBrowserProvider: capturingDefaultBrowserProvider, persistor: homePageContinueSetUpModelPersisting)

        vm.shouldShowAllFeatures = true

        XCTAssertTrue(doTheyContainTheSameElements(matrix1: vm.visibleFeaturesMatrix, matrix2: expectedMatrix))

        vm.shouldShowAllFeatures = false

        XCTAssertEqual(vm.visibleFeaturesMatrix.count, 1)
        XCTAssertTrue(vm.visibleFeaturesMatrix[0].count <= vm.itemsPerRow)
    }

    @MainActor func testWhenAskedToPerformActionForImportPromptThrowsThenItOpensImportWindow() {
        let numberOfFeatures = HomePage.Models.FeatureType.allCases.count

        vm.shouldShowAllFeatures = true
        XCTAssertEqual(vm.visibleFeaturesMatrix.flatMap { $0 }.count, numberOfFeatures)

        capturingDataImportProvider.didImport = true
        vm.performAction(for: .importBookmarksAndPasswords)

        XCTAssertTrue(capturingDataImportProvider.showImportWindowCalled)
        XCTAssertEqual(vm.visibleFeaturesMatrix.flatMap { $0 }.count, numberOfFeatures - 1)
    }

    @MainActor func testWhenUserHasUsedImportAndTogglingShowAllFeatureThenCorrectElementsAreVisible() {
        let expectedMatrix = expectedFeatureMatrixWithout(types: [.importBookmarksAndPasswords])

        capturingDataImportProvider.didImport = true
        vm = HomePage.Models.ContinueSetUpModel.fixture(dataImportProvider: capturingDataImportProvider, persistor: homePageContinueSetUpModelPersisting)

        vm.shouldShowAllFeatures = true

        XCTAssertTrue(doTheyContainTheSameElements(matrix1: vm.visibleFeaturesMatrix, matrix2: expectedMatrix))

        vm.shouldShowAllFeatures = false

        XCTAssertEqual(vm.visibleFeaturesMatrix.count, 1)
        XCTAssertTrue(vm.visibleFeaturesMatrix[0].count <= vm.itemsPerRow)
    }

    @MainActor func testWhenAskedToPerformActionForEmailProtectionThenItOpensEmailProtectionSite() {
        vm.performAction(for: .emailProtection)

        XCTAssertEqual(tabCollectionVM.tabs[1].url, EmailUrls().emailProtectionLink)
    }

    @MainActor func testWhenUserHasEmailProtectionEnabledThenCorrectElementsAreVisible() {
        let expectedMatrix = expectedFeatureMatrixWithout(types: [.emailProtection])

        emailStorage.isEmailProtectionEnabled = true
        vm = HomePage.Models.ContinueSetUpModel.fixture(emailManager: emailManager, persistor: homePageContinueSetUpModelPersisting)

        vm.shouldShowAllFeatures = true

        XCTAssertTrue(doTheyContainTheSameElements(matrix1: vm.visibleFeaturesMatrix, matrix2: expectedMatrix))

        vm.shouldShowAllFeatures = false

        XCTAssertEqual(vm.visibleFeaturesMatrix.count, 1)
        XCTAssertTrue(vm.visibleFeaturesMatrix[0].count <= vm.itemsPerRow)
    }

    @MainActor func testWhenAskedToPerformActionForDuckPlayerThenItOpensYoutubeVideo() {
        vm.performAction(for: .duckplayer)

        XCTAssertEqual(tabCollectionVM.tabs[1].url, URL(string: vm.duckPlayerURL))
    }

    @MainActor func testWhenUserHasDuckPlayerEnabledAndOverlayButtonNotPressedThenCorrectElementsAreVisible() {
        let expectedMatrix = expectedFeatureMatrixWithout(types: [.duckplayer])

        duckPlayerPreferences.youtubeOverlayAnyButtonPressed = false
        duckPlayerPreferences.duckPlayerModeBool = true
        vm = HomePage.Models.ContinueSetUpModel.fixture(duckPlayerPreferences: duckPlayerPreferences, persistor: homePageContinueSetUpModelPersisting)

        vm.shouldShowAllFeatures = true

        XCTAssertTrue(doTheyContainTheSameElements(matrix1: vm.visibleFeaturesMatrix, matrix2: expectedMatrix))

        vm.shouldShowAllFeatures = false

        XCTAssertEqual(vm.visibleFeaturesMatrix.count, 1)
        XCTAssertTrue(vm.visibleFeaturesMatrix[0].count <= vm.itemsPerRow)
    }

    @MainActor func testWhenUserHasDuckPlayerDisabledAndOverlayButtonNotPressedThenCorrectElementsAreVisible() {
        let expectedMatrix = expectedFeatureMatrixWithout(types: [.duckplayer])

        duckPlayerPreferences.youtubeOverlayAnyButtonPressed = false
        duckPlayerPreferences.duckPlayerModeBool = false
        vm = HomePage.Models.ContinueSetUpModel.fixture(duckPlayerPreferences: duckPlayerPreferences, persistor: homePageContinueSetUpModelPersisting)

        vm.shouldShowAllFeatures = true

        XCTAssertTrue(doTheyContainTheSameElements(matrix1: vm.visibleFeaturesMatrix, matrix2: expectedMatrix))

        vm.shouldShowAllFeatures = false

        XCTAssertEqual(vm.visibleFeaturesMatrix.count, 1)
        XCTAssertTrue(vm.visibleFeaturesMatrix[0].count <= vm.itemsPerRow)
    }

    @MainActor func testWhenUserHasDuckPlayerOnAlwaysAskAndOverlayButtonNotPressedThenCorrectElementsAreVisible() {
        let expectedMatrix = expectedFeatureMatrixWithout(types: [])

        duckPlayerPreferences.youtubeOverlayAnyButtonPressed = false
        duckPlayerPreferences.duckPlayerModeBool = nil
        vm = HomePage.Models.ContinueSetUpModel.fixture(duckPlayerPreferences: duckPlayerPreferences, persistor: homePageContinueSetUpModelPersisting)

        vm.shouldShowAllFeatures = true

        XCTAssertTrue(doTheyContainTheSameElements(matrix1: vm.visibleFeaturesMatrix, matrix2: expectedMatrix))

        vm.shouldShowAllFeatures = false

        XCTAssertEqual(vm.visibleFeaturesMatrix.count, 1)
        XCTAssertTrue(vm.visibleFeaturesMatrix[0].count <= vm.itemsPerRow)
    }

    @MainActor func testWhenUserHasDuckPlayerOnAlwaysAskAndOverlayButtonIsPressedThenCorrectElementsAreVisible() {
        let expectedMatrix = expectedFeatureMatrixWithout(types: [.duckplayer])

        duckPlayerPreferences.youtubeOverlayAnyButtonPressed = true
        duckPlayerPreferences.duckPlayerModeBool = nil
        vm = HomePage.Models.ContinueSetUpModel.fixture(duckPlayerPreferences: duckPlayerPreferences, persistor: homePageContinueSetUpModelPersisting)

        vm.shouldShowAllFeatures = true

        XCTAssertTrue(doTheyContainTheSameElements(matrix1: vm.visibleFeaturesMatrix, matrix2: expectedMatrix))

        vm.shouldShowAllFeatures = false

        XCTAssertEqual(vm.visibleFeaturesMatrix.count, 1)
        XCTAssertTrue(vm.visibleFeaturesMatrix[0].count <= HomePage.Models.ContinueSetUpModel.Const.featuresPerRow)
    }

    @MainActor func testThatWhenAllFeatureInactiveThenVisibleMatrixIsEmpty() {
        capturingDefaultBrowserProvider.isDefault = true
        emailStorage.isEmailProtectionEnabled = true
        duckPlayerPreferences.youtubeOverlayAnyButtonPressed = true
        capturingDataImportProvider.didImport = true
        subscriptionCardVisibilityManager.shouldShowSubscriptionCard = false
        dockCustomizer.addToDock()

        vm = HomePage.Models.ContinueSetUpModel(
            defaultBrowserProvider: capturingDefaultBrowserProvider,
            dockCustomizer: dockCustomizer,
            dataImportProvider: capturingDataImportProvider,
            tabOpener: TabCollectionViewModelTabOpener(tabCollectionViewModel: tabCollectionVM),
            emailManager: emailManager,
            duckPlayerPreferences: duckPlayerPreferences,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
            persistor: homePageContinueSetUpModelPersisting
        )

        XCTAssertEqual(vm.visibleFeaturesMatrix, [[]])
    }

    @MainActor func testDismissedItemsAreRemovedFromVisibleMatrixAndChoicesArePersisted() {
        homePageContinueSetUpModelPersisting.isFirstSession = true
        vm = HomePage.Models.ContinueSetUpModel(
            defaultBrowserProvider: capturingDefaultBrowserProvider,
            dockCustomizer: dockCustomizer,
            dataImportProvider: capturingDataImportProvider,
            tabOpener: TabCollectionViewModelTabOpener(tabCollectionViewModel: tabCollectionVM),
            emailManager: emailManager,
            duckPlayerPreferences: duckPlayerPreferences,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
            persistor: homePageContinueSetUpModelPersisting
        )
        vm.shouldShowAllFeatures = true
        let expectedMatrix = expectedFeatureMatrixWithout(types: [])
        XCTAssertEqual(expectedMatrix, vm.visibleFeaturesMatrix)

        vm.removeItem(for: .defaultBrowser)
        XCTAssertFalse(vm.visibleFeaturesMatrix.flatMap { $0 }.contains(.defaultBrowser))

        vm.removeItem(for: .importBookmarksAndPasswords)
        XCTAssertFalse(vm.visibleFeaturesMatrix.flatMap { $0 }.contains(.importBookmarksAndPasswords))

        vm.removeItem(for: .duckplayer)
        XCTAssertFalse(vm.visibleFeaturesMatrix.flatMap { $0 }.contains(.duckplayer))

        vm.removeItem(for: .emailProtection)
        XCTAssertFalse(vm.visibleFeaturesMatrix.flatMap { $0 }.contains(.emailProtection))

        vm.removeItem(for: .subscription)
        XCTAssertFalse(vm.visibleFeaturesMatrix.flatMap { $0 }.contains(.subscription))

#if !APPSTORE
        vm.removeItem(for: .dock)
        XCTAssertFalse(vm.visibleFeaturesMatrix.flatMap { $0 }.contains(.dock))
#endif

        let vm2 = HomePage.Models.ContinueSetUpModel.fixture(persistor: homePageContinueSetUpModelPersisting, subscriptionCardVisibilityManager: subscriptionCardVisibilityManager)
        XCTAssertTrue(vm2.visibleFeaturesMatrix.flatMap { $0 }.isEmpty)
    }

    @MainActor func testShowAllFeatureUserPreferencesIsPersisted() {
        let vm2 = HomePage.Models.ContinueSetUpModel.fixture(persistor: homePageContinueSetUpModelPersisting)
        vm2.shouldShowAllFeatures = true
        vm.shouldShowAllFeatures = false

        XCTAssertFalse(vm2.shouldShowAllFeatures)
    }

    private func doTheyContainTheSameElements(matrix1: [[HomePage.Models.FeatureType]], matrix2: [[HomePage.Models.FeatureType]]) -> Bool {
        Set(matrix1.flatMap { $0 }) == Set(matrix2.flatMap { $0 })
    }
    private func expectedFeatureMatrixWithout(types: [HomePage.Models.FeatureType]) -> [[HomePage.Models.FeatureType]] {
        var features = HomePage.Models.FeatureType.allCases
        var indexesToRemove: [Int] = []
        for type in types {
            indexesToRemove.append(features.firstIndex(of: type)!)
        }
        indexesToRemove.sort()
        indexesToRemove.reverse()
        for index in indexesToRemove {
            features.remove(at: index)
        }
        return features.chunked(into: HomePage.Models.ContinueSetUpModel.Const.featuresPerRow)
    }

    @MainActor func test_WhenUserDoesntHaveApplicationInTheDock_ThenAddToDockCardIsDisplayed() {
#if !APPSTORE
        let dockCustomizer = DockCustomizerMock()

        let vm = HomePage.Models.ContinueSetUpModel.fixture(persistor: homePageContinueSetUpModelPersisting, dockCustomizer: dockCustomizer)
        vm.shouldShowAllFeatures = true

        XCTAssert(vm.visibleFeaturesMatrix.reduce([], +).contains(HomePage.Models.FeatureType.dock))
#endif
    }

    @MainActor func test_WhenUserHasApplicationInTheDock_ThenAddToDockCardIsNotDisplayed() {
        let dockCustomizer = DockCustomizerMock()
        dockCustomizer.addToDock()

        let vm = HomePage.Models.ContinueSetUpModel.fixture(persistor: homePageContinueSetUpModelPersisting, dockCustomizer: dockCustomizer)
        vm.shouldShowAllFeatures = true

        XCTAssertFalse(vm.visibleFeaturesMatrix.reduce([], +).contains(HomePage.Models.FeatureType.dock))
    }

    @MainActor func testWhenAskedToPerformActionForSubscriptionThenItOpensSubscriptionSite() {
        vm.performAction(for: .subscription)

        let expectedURL = SubscriptionURL.purchaseURLComponentsWithOrigin(SubscriptionFunnelOrigin.newTabPageNextStepsCard.rawValue)?.url

        XCTAssertEqual(tabCollectionVM.tabs[1].url, expectedURL)
    }

    // MARK: - Pixel Tests (Click)

    @MainActor func testWhenAskedToPerformActionForDefaultBrowserThenItFiresPixels() {
        vm.performAction(for: .defaultBrowser)

        XCTAssertEqual(firedPixels.count, 2)

        let expectedGeneralPixel = GeneralPixel.defaultRequestedFromHomepageSetupView
        let expectedNewTabPagePixel = NewTabPagePixel.nextStepsCardClicked(NewTabPageDataModel.CardID.defaultApp.rawValue)
        XCTAssertTrue(firedPixels.contains(where: { $0.event.name == expectedGeneralPixel.name && $0.includesAppVersionParameter == true }))
        XCTAssertTrue(firedPixels.contains(where: { $0.event.name == expectedNewTabPagePixel.name && $0.includesAppVersionParameter == true }))
    }

    @MainActor func testWhenAskedToPerformActionForDockThenItFiresPixels() {
        vm.performAction(for: .dock)

        XCTAssertEqual(firedPixels.count, 2)

        let expectedGeneralPixel = GeneralPixel.userAddedToDockFromNewTabPageCard
        let expectedNewTabPagePixel = NewTabPagePixel.nextStepsCardClicked(NewTabPageDataModel.CardID.addAppToDockMac.rawValue)
        XCTAssertTrue(firedPixels.contains(where: { $0.event.name == expectedGeneralPixel.name && $0.includesAppVersionParameter == false }))
        XCTAssertTrue(firedPixels.contains(where: { $0.event.name == expectedNewTabPagePixel.name && $0.includesAppVersionParameter == true }))
    }

    @MainActor func testWhenAskedToPerformActionForDuckplayerThenItFiresPixel() {
        vm.performAction(for: .duckplayer)

        XCTAssertEqual(firedPixels.count, 1)
        let expectedPixel = NewTabPagePixel.nextStepsCardClicked(NewTabPageDataModel.CardID.duckplayer.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedPixel.name)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    @MainActor func testWhenAskedToPerformActionForEmailProtectionThenItFiresPixel() {
        vm.performAction(for: .emailProtection)

        XCTAssertEqual(firedPixels.count, 1)
        let expectedPixel = NewTabPagePixel.nextStepsCardClicked(NewTabPageDataModel.CardID.emailProtection.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedPixel.name)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    @MainActor func testWhenAskedToPerformActionForImportBookmarksAndPasswordsThenItFiresPixel() {
        vm.performAction(for: .importBookmarksAndPasswords)

        XCTAssertEqual(firedPixels.count, 1)
        let expectedPixel = NewTabPagePixel.nextStepsCardClicked(NewTabPageDataModel.CardID.bringStuff.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedPixel.name)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    @MainActor func testWhenAskedToPerformActionForSubscriptionThenItFiresPixels() {
        vm.performAction(for: .subscription)

        XCTAssertEqual(firedPixels.count, 2)

        let expectedSubscriptionPixel = SubscriptionPixel.subscriptionNewTabPageNextStepsCardClicked
        let expectedNewTabPagePixel = NewTabPagePixel.nextStepsCardClicked(NewTabPageDataModel.CardID.subscription.rawValue)
        XCTAssertTrue(firedPixels.contains(where: { $0.event.name == expectedSubscriptionPixel.name && $0.includesAppVersionParameter == true }))
        XCTAssertTrue(firedPixels.contains(where: { $0.event.name == expectedNewTabPagePixel.name && $0.includesAppVersionParameter == true }))
    }

    // MARK: - Pixel Tests (Dismiss)

    @MainActor func testWhenDismissingDefaultBrowserCardThenItFiresPixel() {
        vm.removeItem(for: .defaultBrowser)

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.event.name, NewTabPagePixel.nextStepsCardDismissed(NewTabPageDataModel.CardID.defaultApp.rawValue).name)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    @MainActor func testWhenDismissingDockCardThenItFiresPixel() {
        vm.removeItem(for: .dock)

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.event.name, NewTabPagePixel.nextStepsCardDismissed(NewTabPageDataModel.CardID.addAppToDockMac.rawValue).name)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    @MainActor func testWhenDismissingDuckplayerCardThenItFiresPixel() {
        vm.removeItem(for: .duckplayer)

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.event.name, NewTabPagePixel.nextStepsCardDismissed(NewTabPageDataModel.CardID.duckplayer.rawValue).name)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    @MainActor func testWhenDismissingEmailProtectionCardThenItFiresPixel() {
        vm.removeItem(for: .emailProtection)

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.event.name, NewTabPagePixel.nextStepsCardDismissed(NewTabPageDataModel.CardID.emailProtection.rawValue).name)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    @MainActor func testWhenDismissingImportBookmarksAndPasswordsCardThenItFiresPixel() {
        vm.removeItem(for: .importBookmarksAndPasswords)

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.event.name, NewTabPagePixel.nextStepsCardDismissed(NewTabPageDataModel.CardID.bringStuff.rawValue).name)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    @MainActor func testWhenDismissingSubscriptionCardThenItFiresPixels() {
        vm.removeItem(for: .subscription)

        XCTAssertEqual(firedPixels.count, 2)

        let expectedSubscriptionPixel = SubscriptionPixel.subscriptionNewTabPageNextStepsCardDismissed
        let expectedNewTabPagePixel = NewTabPagePixel.nextStepsCardDismissed(NewTabPageDataModel.CardID.subscription.rawValue)
        XCTAssertTrue(firedPixels.contains(where: { $0.event.name == expectedSubscriptionPixel.name && $0.includesAppVersionParameter == true }))
        XCTAssertTrue(firedPixels.contains(where: { $0.event.name == expectedNewTabPagePixel.name && $0.includesAppVersionParameter == true }))
    }
}

extension HomePage.Models.ContinueSetUpModel {
    @MainActor static func fixture(
        defaultBrowserProvider: DefaultBrowserProvider = CapturingDefaultBrowserProvider(),
        dataImportProvider: DataImportStatusProviding = CapturingDataImportProvider(),
        emailManager: EmailManager = EmailManager(storage: MockEmailStorage()),
        duckPlayerPreferences: DuckPlayerPreferencesPersistor = DuckPlayerPreferencesPersistorMock(),
        privacyConfig: MockPrivacyConfiguration = MockPrivacyConfiguration(),
        persistor: HomePageContinueSetUpModelPersisting = MockHomePageContinueSetUpModelPersisting(),
        dockCustomizer: DockCustomization = DockCustomizerMock(),
        subscriptionCardVisibilityManager: MockHomePageSubscriptionCardVisibilityManaging = MockHomePageSubscriptionCardVisibilityManaging()
    ) -> HomePage.Models.ContinueSetUpModel {
        privacyConfig.featureSettings = [
            "networkProtection": "disabled"
        ] as! [String: String]
        let manager = MockPrivacyConfigurationManager()
        manager.mockPrivacyConfig = privacyConfig

        return HomePage.Models.ContinueSetUpModel(
            defaultBrowserProvider: defaultBrowserProvider,
            dockCustomizer: dockCustomizer,
            dataImportProvider: dataImportProvider,
            tabOpener: TabCollectionViewModelTabOpener(tabCollectionViewModel: TabCollectionViewModel(isPopup: false)),
            emailManager: emailManager,
            duckPlayerPreferences: duckPlayerPreferences,
            privacyConfigurationManager: manager,
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
            persistor: persistor
        )
    }
}
