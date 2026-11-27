//
//  BrowserToolPermissionsPreferencesTests.swift
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

import AIChat
import FeatureFlags_macOS
@_spi(Testing) import Persistence
import PrivacyConfig
@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BrowserToolPermissionsPreferencesTests: XCTestCase {

    private var manager: PermissionManagerMock!
    private var permissions: BrowserToolSitePermissions!
    private var catalog: BrowserToolCatalog!
    private var pixels: PixelKitMock!
    private var model: BrowserToolPermissionsPreferences!
    private var translateStore: InMemoryKeyValueStore!
    private var translatePages: TranslatePagesSetting!
    private var featureFlagger: MockFeatureFlagger!
    private var translateCenter: NotificationCenter!

    override func setUp() {
        super.setUp()
        manager = PermissionManagerMock()
        permissions = BrowserToolSitePermissions(permissionManager: manager)
        let tools = [FakeTool(name: "pinTab", permissionMode: .auto), FakeTool(name: "listOpenTabs", permissionMode: .ask)]
        catalog = BrowserToolCatalog(tools: tools, configuration: FakeConfiguration())
        pixels = PixelKitMock()
        translateStore = InMemoryKeyValueStore()
        translateCenter = NotificationCenter()
        translatePages = TranslatePagesSetting(store: translateStore, notificationCenter: translateCenter)
        featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub[FeatureFlag.aiChatOfferTranslationAndSummarize.rawValue] = true
        model = makeModel()
    }

    private func makeModel(source: BrowserToolsPixel.PermissionSource = .settings) -> BrowserToolPermissionsPreferences {
        BrowserToolPermissionsPreferences(catalog: catalog, permissions: permissions, permissionManager: manager,
                                          source: source, pixelFiring: pixels, translatePages: translatePages,
                                          featureFlagger: featureFlagger)
    }

    override func tearDown() {
        model = nil
        pixels = nil
        catalog = nil
        permissions = nil
        manager = nil
        super.tearDown()
    }

    func testRowsFollowTheSettingsOrderWithEachToolsDefault() {
        XCTAssertEqual(model.rows.map(\.name), ["listOpenTabs", "pinTab"])
        XCTAssertEqual(model.rows.map { model.state(of: $0) }, [.ask, .allow])
        XCTAssertFalse(model.canResetAll)
    }

    func testWhenAToolIsSetAwayFromItsDefaultThenTheChoiceIsStored() {
        let pinTab = model.rows[1]

        model.setState(.ask, of: pinTab)

        XCTAssertEqual(permissions.state(forToolNamed: "pinTab"), .ask)
        XCTAssertEqual(model.state(of: pinTab), .ask)
        XCTAssertTrue(model.canResetAll)
    }

    func testWhenAToolIsSetBackToItsDefaultThenNothingIsStored() {
        let pinTab = model.rows[1]
        model.setState(.deny, of: pinTab)

        model.setState(.allow, of: pinTab)

        XCTAssertNil(permissions.state(forToolNamed: "pinTab"))
        XCTAssertFalse(model.canResetAll)
    }

    func testWhenResetThenEveryToolIsBackToItsDefault() {
        model.setState(.deny, of: model.rows[0])
        model.setState(.ask, of: model.rows[1])

        model.resetAll()

        XCTAssertEqual(permissions.storedDecisions, [:])
        XCTAssertEqual(model.rows.map { model.state(of: $0) }, [.ask, .allow])
    }

    func testWhenTheChoiceChangesElsewhereThenTheRowsFollow() {
        let expectation = expectation(description: "reloaded")
        let cancellable = model.$storedStates.first { $0["listOpenTabs"] == .allow }.sink { _ in expectation.fulfill() }
        permissions.setState(.allow, forToolNamed: "listOpenTabs")

        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(model.state(of: model.rows[0]), .allow)
        cancellable.cancel()
    }

    // MARK: - Translate Pages

    func testWhenTheFlagIsOffThenTheTranslateRowIsHidden() {
        featureFlagger.featuresStub[FeatureFlag.aiChatOfferTranslationAndSummarize.rawValue] = false
        model = makeModel()

        XCTAssertFalse(model.showsTranslateRow)
    }

    func testWhenTheFlagChangesWhileOpenThenTheRowFollows() {
        let key = FeatureFlag.aiChatOfferTranslationAndSummarize.rawValue
        let hidden = expectation(description: "hidden")
        let shown = expectation(description: "shown")
        let cancellable = model.$showsTranslateRow.dropFirst().sink { $0 ? shown.fulfill() : hidden.fulfill() }

        featureFlagger.featuresStub[key] = false
        featureFlagger.triggerUpdate()
        wait(for: [hidden], timeout: 1)
        featureFlagger.featuresStub[key] = true
        featureFlagger.triggerUpdate()
        wait(for: [shown], timeout: 1)

        cancellable.cancel()
    }

    func testWhenTheFlagIsOffThenResetAllKeepsTranslatePreferences() {
        model.setTranslateMode(.neverAsk)
        translatePages.exclude(languageCode: "de")
        featureFlagger.featuresStub[FeatureFlag.aiChatOfferTranslationAndSummarize.rawValue] = false
        model.reload()

        model.resetAll()

        XCTAssertEqual(translatePages.mode, .neverAsk)
        XCTAssertEqual(translatePages.excludedLanguageCodes, ["de"])
    }

    func testWhenTheFlagTurnsOffBeforeTheQueuedRefreshThenResetAllKeepsTranslatePreferences() {
        model.setTranslateMode(.neverAsk)
        permissions.setState(.deny, forToolNamed: "pinTab")
        model.reload()
        featureFlagger.featuresStub[FeatureFlag.aiChatOfferTranslationAndSummarize.rawValue] = false

        model.resetAll()

        XCTAssertNil(permissions.state(forToolNamed: "pinTab"))
        XCTAssertEqual(translatePages.mode, .neverAsk)
    }

    func testWhenALanguageIsExcludedOutsideTheModelThenItIsPickedUp() {
        let expectation = expectation(description: "reloaded")
        let cancellable = model.$translateExcludedLanguages.first { $0 == ["de"] }.sink { _ in expectation.fulfill() }

        translatePages.exclude(languageCode: "de")

        wait(for: [expectation], timeout: 1)
        cancellable.cancel()
    }

    func testTranslatePagesDefaultsToAlwaysAskWithNothingToReset() {
        XCTAssertTrue(model.showsTranslateRow)
        XCTAssertEqual(model.translateMode, .alwaysAsk)
        XCTAssertEqual(model.translateExcludedLanguages, [])
        XCTAssertFalse(model.canResetAll)
    }

    func testWhenTranslateIsSetToNeverAskThenItIsStoredAndResettable() {
        model.setTranslateMode(.neverAsk)

        XCTAssertEqual(TranslatePagesSetting(store: translateStore).mode, .neverAsk)
        XCTAssertEqual(model.translateMode, .neverAsk)
        XCTAssertTrue(model.canResetAll)
    }

    func testWhenTheRowIsResetThenModeAndExcludedLanguagesAreCleared() {
        model.setTranslateMode(.neverAsk)
        translatePages.exclude(languageCode: "fr")

        model.resetTranslate()

        XCTAssertEqual(model.translateMode, .alwaysAsk)
        XCTAssertEqual(model.translateExcludedLanguages, [])
        XCTAssertFalse(translatePages.isCustomized)
    }

    func testResetAllAlsoClearsTranslatePages() {
        model.setTranslateMode(.neverAsk)
        translatePages.exclude(languageCode: "de")

        model.resetAll()

        XCTAssertEqual(model.translateMode, .alwaysAsk)
        XCTAssertEqual(model.translateExcludedLanguages, [])
    }

    func testResetAllIsOfferedWhenOnlyAnExcludedLanguageIsStored() {
        translatePages.exclude(languageCode: "de")
        model.reload()

        XCTAssertTrue(model.canResetAll)
    }

    func testExcludingALanguageKeepsItsPrimarySubtagOnceAndSurvivesANewInstance() {
        translatePages.exclude(languageCode: "fr-CA")
        translatePages.exclude(languageCode: "FR")
        translatePages.exclude(languageCode: "pt_BR")

        let reloaded = TranslatePagesSetting(store: translateStore)
        XCTAssertEqual(reloaded.excludedLanguageCodes, ["fr", "pt"])
        XCTAssertTrue(reloaded.isExcluded(languageCode: "fr-FR"))
        XCTAssertFalse(reloaded.isExcluded(languageCode: "de"))
    }

    func testWhenOnlyTranslatePagesIsCustomizedThenResetAllFiresNoToolResetPixel() {
        model.setTranslateMode(.neverAsk)

        model.resetAll()

        XCTAssertTrue(pixels.actualFireCalls.isEmpty)
        XCTAssertEqual(model.translateMode, .alwaysAsk)
    }

    func testIncludingAnExcludedLanguageBringsItBack() {
        translatePages.exclude(languageCode: "fr")
        translatePages.exclude(languageCode: "de")

        model.setTranslate(languageCode: "fr", excluded: false)

        XCTAssertEqual(model.translateExcludedLanguages, ["de"])
        model.setTranslate(languageCode: "de", excluded: false)
        XCTAssertEqual(model.translateExcludedLanguages, [])
        XCTAssertFalse(model.isTranslateCustomized)
    }

    func testTheLanguageMenuListsTheAppLocalizationsByNameWithoutTheSystemLanguage() {
        let locale = Locale(identifier: "en_US")

        let codes = TranslatePagesLanguages.menuCodes(localizations: ["en", "de", "es", "fr"], offered: [], excluded: [],
                                                      systemCode: "en", locale: locale)

        XCTAssertEqual(codes.map { TranslatePagesLanguages.name(of: $0, locale: locale) }, ["French", "German", "Spanish"])
    }

    func testTheLanguageMenuAddsOfferedAndExcludedLanguagesOnceByName() {
        let locale = Locale(identifier: "en_US")

        let codes = TranslatePagesLanguages.menuCodes(localizations: ["de", "fr"], offered: ["sv", "de"], excluded: ["ja", "fr"],
                                                      systemCode: "en", locale: locale)

        XCTAssertEqual(codes.map { TranslatePagesLanguages.name(of: $0, locale: locale) }, ["French", "German", "Japanese", "Swedish"])
    }

    func testTheAppLocalizationsDropBaseAndKeepThePrimarySubtag() {
        XCTAssertEqual(TranslatePagesLanguages.appLocalizations(from: ["Base", "en", "pt-BR", "zh-Hans", "de"]),
                       ["en", "pt", "zh", "de"])
    }

    func testTheRealBundleHasLocalizations() {
        XCTAssertFalse(TranslatePagesLanguages.appLocalizations().isEmpty)
    }

    func testWhenAnotherInstanceRecordsAnOfferedLanguageThenTheOpenModelFollows() {
        let expectation = expectation(description: "reloaded")
        let cancellable = model.$translateOfferedLanguages.first { $0 == ["sv"] }.sink { _ in expectation.fulfill() }
        let offer = TranslatePagesSetting(store: translateStore, notificationCenter: translateCenter)

        offer.recordOffered(languageCode: "sv")

        wait(for: [expectation], timeout: 1)
        cancellable.cancel()
    }

    func testAnOfferedLanguageIsRecordedOnceAndSurvivesAReset() {
        translatePages.recordOffered(languageCode: "sv-SE")
        translatePages.recordOffered(languageCode: "sv")
        translatePages.exclude(languageCode: "sv")

        model.resetTranslate()

        let reloaded = TranslatePagesSetting(store: translateStore)
        XCTAssertEqual(reloaded.offeredLanguageCodes, ["sv"])
        XCTAssertEqual(reloaded.excludedLanguageCodes, [])
        XCTAssertEqual(model.translateOfferedLanguages, ["sv"])
    }

    func testResetAllKeepsOfferedLanguages() {
        translatePages.recordOffered(languageCode: "sv")
        model.reload()

        model.resetAll()

        XCTAssertEqual(translatePages.offeredLanguageCodes, ["sv"])
    }

    func testRecordingAnOfferedLanguageAloneDoesNotMakeTheSettingCustomized() {
        translatePages.recordOffered(languageCode: "sv")

        XCTAssertFalse(translatePages.isCustomized)
    }

    func testTheSummaryNamesTheSystemLanguageThenTheExcludedOnes() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(TranslatePagesLanguages.summary(excluded: [], systemCode: "en", locale: locale), "English")
        XCTAssertEqual(TranslatePagesLanguages.summary(excluded: ["fr", "es", "en"], systemCode: "en", locale: locale), "English, French, Spanish")
    }

    // MARK: - Pixels

    func testWhenAChoiceChangesInSettingsThenThePermissionChangedPixelFires() {
        model.setState(.allow, of: model.rows[0])

        XCTAssertEqual(pixels.actualFireCalls.map(\.pixel.name), ["aichat_tools_permission_changed_macos"])
        XCTAssertEqual(pixels.actualFireCalls[0].pixel.parameters,
                       ["tool": "list_open_tabs", "from": "ask", "to": "allow", "source": "settings"])
    }

    func testWhenAChoiceChangesInThePanelThenThePixelNamesThePanel() {
        model = makeModel(source: .panel)

        model.setState(.deny, of: model.rows[1])

        XCTAssertEqual(pixels.actualFireCalls.map(\.pixel.parameters), [["tool": "pin_tab", "from": "allow", "to": "deny", "source": "panel"]])
    }

    func testWhenTheSameChoiceIsPickedAgainThenNoPixelFires() {
        model.setState(.ask, of: model.rows[0])

        XCTAssertTrue(pixels.actualFireCalls.isEmpty)
    }

    func testWhenOneToolIsResetThenThePixelReportsTheChangeToItsDefault() {
        permissions.setState(.deny, forToolNamed: "pinTab")
        model.reload()

        model.reset(model.rows[1])

        XCTAssertEqual(pixels.actualFireCalls.map(\.pixel.parameters), [["tool": "pin_tab", "from": "deny", "to": "allow", "source": "settings"]])
    }

    func testWhenEveryToolIsResetThenTheResetPixelFires() {
        permissions.setState(.deny, forToolNamed: "listOpenTabs")
        model.reload()

        model.resetAll()

        XCTAssertEqual(pixels.actualFireCalls.map(\.pixel.name), ["aichat_tools_permissions_reset_macos"])
        XCTAssertNil(pixels.actualFireCalls[0].pixel.parameters)
    }

}

@MainActor
private final class FakeTool: BrowserTool {
    let name: String
    let permissionMode: BrowserToolPermissionMode
    var inputSchema: JSONValue { ["type": "object"] }

    init(name: String, permissionMode: BrowserToolPermissionMode) {
        self.name = name
        self.permissionMode = permissionMode
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        .success(.object([:]))
    }
}

@MainActor
private final class FakeConfiguration: BrowserToolsConfiguration {
    var isEnabled: Bool { true }
    func isToolEnabled(named name: String) -> Bool { true }
}
