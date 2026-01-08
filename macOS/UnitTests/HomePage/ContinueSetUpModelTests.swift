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
import PrivacyConfigTestsUtils
import SubscriptionTestingUtilities

@testable import Subscription
@testable import DuckDuckGo_Privacy_Browser

final class ContinueSetUpModelTests: XCTestCase {

    var vm: HomePage.Models.ContinueSetUpModel!
    var capturingDefaultBrowserProvider: CapturingDefaultBrowserProvider!
    var capturingDataImportProvider: CapturingDataImportProvider!
    var emailManager: EmailManager!
    var emailStorage: MockEmailStorage!
    var duckPlayerPreferences: DuckPlayerPreferencesPersistor!
    var coookiePopupProtectionPreferences: MockCookiePopupProtectionPreferencesPersistor!
    var dockCustomizer: DockCustomization!
    var userDefaults: UserDefaults! = UserDefaults(suiteName: "\(Bundle.main.bundleIdentifier!).\(AppVersion.runType)")!
    var subscriptionCardVisibilityManager: MockHomePageSubscriptionCardVisibilityManaging!
    var homePageContinueSetUpModelPersisting: MockHomePageContinueSetUpModelPersisting!
    var pixelHandler: MockNewTabPageNextStepsCardsPixelHandler!
    var cardActionsHandler: MockNewTabPageNextStepsCardsActionHandler!

    @MainActor override func setUp() {
        UserDefaultsWrapper<Any>.clearAll()
        userDefaults.set(Date(), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)
        capturingDefaultBrowserProvider = CapturingDefaultBrowserProvider()
        capturingDataImportProvider = CapturingDataImportProvider()
        emailStorage = MockEmailStorage()
        emailManager = EmailManager(storage: emailStorage)
        duckPlayerPreferences = DuckPlayerPreferencesPersistorMock()
        dockCustomizer = DockCustomizerMock()
        subscriptionCardVisibilityManager = MockHomePageSubscriptionCardVisibilityManaging()
        homePageContinueSetUpModelPersisting = MockHomePageContinueSetUpModelPersisting()
        pixelHandler = MockNewTabPageNextStepsCardsPixelHandler()
        cardActionsHandler = MockNewTabPageNextStepsCardsActionHandler()

        vm = HomePage.Models.ContinueSetUpModel(
            defaultBrowserProvider: capturingDefaultBrowserProvider,
            dockCustomizer: dockCustomizer,
            dataImportProvider: capturingDataImportProvider,
            emailManager: emailManager,
            duckPlayerPreferences: duckPlayerPreferences,
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
            persistor: homePageContinueSetUpModelPersisting,
            pixelHandler: pixelHandler,
            cardActionsHandler: cardActionsHandler
        )
    }

    override func tearDown() {
        UserDefaultsWrapper<Any>.clearAll()
        capturingDefaultBrowserProvider = nil
        capturingDataImportProvider = nil
        emailManager = nil
        emailStorage = nil
        vm = nil
        dockCustomizer = nil
        duckPlayerPreferences = nil
        userDefaults = nil
        subscriptionCardVisibilityManager = nil
        homePageContinueSetUpModelPersisting = nil
        pixelHandler = nil
        cardActionsHandler = nil
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
            emailManager: emailManager,
            duckPlayerPreferences: duckPlayerPreferences,
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
            persistor: homePageContinueSetUpModelPersisting,
            pixelHandler: pixelHandler,
            cardActionsHandler: cardActionsHandler
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
            emailManager: emailManager,
            duckPlayerPreferences: duckPlayerPreferences,
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
            persistor: homePageContinueSetUpModelPersisting,
            pixelHandler: pixelHandler,
            cardActionsHandler: cardActionsHandler
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
            emailManager: emailManager,
            duckPlayerPreferences: duckPlayerPreferences,
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
            persistor: homePageContinueSetUpModelPersisting,
            pixelHandler: pixelHandler,
            cardActionsHandler: cardActionsHandler
        )

        XCTAssertEqual(vm.visibleFeaturesMatrix, [[]])
    }

    @MainActor func testDismissedItemsAreRemovedFromVisibleMatrixAndChoicesArePersisted() {
        homePageContinueSetUpModelPersisting.isFirstSession = true
        vm = HomePage.Models.ContinueSetUpModel(
            defaultBrowserProvider: capturingDefaultBrowserProvider,
            dockCustomizer: dockCustomizer,
            dataImportProvider: capturingDataImportProvider,
            emailManager: emailManager,
            duckPlayerPreferences: duckPlayerPreferences,
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
            persistor: homePageContinueSetUpModelPersisting,
            pixelHandler: pixelHandler,
            cardActionsHandler: cardActionsHandler
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

    // MARK: Card actions

    @MainActor func testWhenAskedToPerformActionForDefaultBrowserCardThenItHandlesCardAction() {
        vm.performAction(for: .defaultBrowser)

        XCTAssertEqual(cardActionsHandler.cardActionsPerformed, [.defaultApp])
    }

    @MainActor func testWhenAskedToPerformActionForDockThenItHandlesCardAction() {
        vm.performAction(for: .dock)

        XCTAssertEqual(cardActionsHandler.cardActionsPerformed, [.addAppToDockMac])
    }

    @MainActor func testWhenAskedToPerformActionForImportPromptThrowsThenItHandlesCardActionAndRefreshesMatrix() {
        let numberOfFeatures = HomePage.Models.FeatureType.allCases.count

        vm.shouldShowAllFeatures = true
        XCTAssertEqual(vm.visibleFeaturesMatrix.flatMap { $0 }.count, numberOfFeatures)

        capturingDataImportProvider.didImport = true
        vm.performAction(for: .importBookmarksAndPasswords)

        XCTAssertEqual(cardActionsHandler.cardActionsPerformed, [.bringStuff])
        XCTAssertEqual(vm.visibleFeaturesMatrix.flatMap { $0 }.count, numberOfFeatures - 1)
    }

    @MainActor func testWhenAskedToPerformActionForDuckPlayerThenItHandlesCardAction() {
        vm.performAction(for: .duckplayer)

        XCTAssertEqual(cardActionsHandler.cardActionsPerformed, [.duckplayer])
    }

    @MainActor func testWhenAskedToPerformActionForEmailProtectionThenItHandlesCardAction() {
        vm.performAction(for: .emailProtection)

        XCTAssertEqual(cardActionsHandler.cardActionsPerformed, [.emailProtection])
    }

    @MainActor func testWhenAskedToPerformActionForSubscriptionThenItHandlesCardAction() {
        vm.performAction(for: .subscription)

        XCTAssertEqual(cardActionsHandler.cardActionsPerformed, [.subscription])
    }

    // MARK: - Pixel Tests (Dismiss)

    @MainActor func testWhenDismissingDefaultBrowserCardThenItFiresPixel() {
        vm.removeItem(for: .defaultBrowser)

        XCTAssertEqual(pixelHandler.fireNextStepsCardDismissedPixelCalledWith, .defaultApp)
    }

    @MainActor func testWhenDismissingDockCardThenItFiresPixel() {
        vm.removeItem(for: .dock)

        XCTAssertEqual(pixelHandler.fireNextStepsCardDismissedPixelCalledWith, .addAppToDockMac)
    }

    @MainActor func testWhenDismissingDuckplayerCardThenItFiresPixel() {
        vm.removeItem(for: .duckplayer)

        XCTAssertEqual(pixelHandler.fireNextStepsCardDismissedPixelCalledWith, .duckplayer)
    }

    @MainActor func testWhenDismissingEmailProtectionCardThenItFiresPixel() {
        vm.removeItem(for: .emailProtection)

        XCTAssertEqual(pixelHandler.fireNextStepsCardDismissedPixelCalledWith, .emailProtection)
    }

    @MainActor func testWhenDismissingImportBookmarksAndPasswordsCardThenItFiresPixel() {
        vm.removeItem(for: .importBookmarksAndPasswords)

        XCTAssertEqual(pixelHandler.fireNextStepsCardDismissedPixelCalledWith, .bringStuff)
    }

    @MainActor func testWhenDismissingSubscriptionCardThenItFiresPixels() {
        vm.removeItem(for: .subscription)

        XCTAssertTrue(pixelHandler.fireSubscriptionCardDismissedPixelCalled)
        XCTAssertEqual(pixelHandler.fireNextStepsCardDismissedPixelCalledWith, .subscription)
    }
}

extension HomePage.Models.ContinueSetUpModel {
    @MainActor static func fixture(
        defaultBrowserProvider: DefaultBrowserProvider = CapturingDefaultBrowserProvider(),
        dataImportProvider: DataImportStatusProviding = CapturingDataImportProvider(),
        emailManager: EmailManager = EmailManager(storage: MockEmailStorage()),
        duckPlayerPreferences: DuckPlayerPreferencesPersistor = DuckPlayerPreferencesPersistorMock(),
        persistor: HomePageContinueSetUpModelPersisting = MockHomePageContinueSetUpModelPersisting(),
        dockCustomizer: DockCustomization = DockCustomizerMock(),
        subscriptionCardVisibilityManager: MockHomePageSubscriptionCardVisibilityManaging = MockHomePageSubscriptionCardVisibilityManaging(),
        pixelHandler: NewTabPageNextStepsCardsPixelHandling = MockNewTabPageNextStepsCardsPixelHandler(),
        cardActionsHandler: NewTabPageNextStepsCardsActionHandling = MockNewTabPageNextStepsCardsActionHandler()
    ) -> HomePage.Models.ContinueSetUpModel {
        HomePage.Models.ContinueSetUpModel(
            defaultBrowserProvider: defaultBrowserProvider,
            dockCustomizer: dockCustomizer,
            dataImportProvider: dataImportProvider,
            emailManager: emailManager,
            duckPlayerPreferences: duckPlayerPreferences,
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
            persistor: persistor,
            pixelHandler: pixelHandler,
            cardActionsHandler: cardActionsHandler
        )
    }
}
