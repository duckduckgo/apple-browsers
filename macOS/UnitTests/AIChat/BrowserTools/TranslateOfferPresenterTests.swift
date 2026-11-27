//
//  TranslateOfferPresenterTests.swift
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
import Combine
import FeatureFlags_macOS
import Foundation
@_spi(Testing) import Persistence
import PrivacyConfig
import PrivacyConfigTestsUtils
import SharedTestUtilities
import Testing
import WebKit
@testable import DuckDuckGo_Privacy_Browser

@MainActor
@Suite("Translate offer in the browser tool prompt presenter")
struct TranslateOfferPresenterTests {

    private let collection: TabCollectionViewModel
    private let presenter: BrowserToolPermissionPromptPresenter
    private let setting = TranslatePagesSetting(store: InMemoryKeyValueStore(), notificationCenter: NotificationCenter())

    init() {
        collection = Self.collection(urls: ["https://a.example", "https://b.example"])
        presenter = Self.presenter(collections: [collection], setting: setting)
    }

    private static func collection(urls: [String], burnerMode: BurnerMode = .regular) -> TabCollectionViewModel {
        let tabs: [AnyTab] = urls.map { .loaded(Tab(content: .url(URL(string: $0)!, credential: nil, source: .ui), burnerMode: burnerMode)) }
        return TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs), pinnedTabsManagerProvider: nil, burnerMode: burnerMode)
    }

    private static func presenter(collections: [TabCollectionViewModel], setting: TranslatePagesSetting? = nil) -> BrowserToolPermissionPromptPresenter {
        let manager = WindowControllersManagerMock()
        manager.customAllTabCollectionViewModels = collections
        let setting = setting ?? TranslatePagesSetting(store: InMemoryKeyValueStore(), notificationCenter: NotificationCenter())
        return BrowserToolPermissionPromptPresenter(windowControllersManager: manager, translatePages: setting) { _, _, _ in }
    }

    private func tabID(_ index: Int) -> TabIdentifier { collection.tabCollection.tabs[index].uuid }

    @available(iOS 16, macOS 13, *)
    @Test("A later load replaces the tab's offer, and a load in the user's language withdraws it", .timeLimit(.minutes(1)))
    func laterLoads() {
        presenter.offerTranslation(languageCode: "es", tabID: tabID(0))
        #expect(presenter.translateOfferLanguageCode(for: tabID(0)) == "es")

        presenter.offerTranslation(languageCode: "fr", tabID: tabID(0))
        #expect(presenter.translateOfferLanguageCode(for: tabID(0)) == "fr")

        presenter.offerTranslation(languageCode: nil, tabID: tabID(0))
        #expect(presenter.translateOfferLanguageCode(for: tabID(0)) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Dismissing keeps that tab from offering again, while other tabs still offer", .timeLimit(.minutes(1)))
    func dismissal() {
        presenter.offerTranslation(languageCode: "es", tabID: tabID(0))
        presenter.answerTranslateOffer(for: tabID(0), translate: false)
        #expect(presenter.translateOfferLanguageCode(for: tabID(0)) == nil)

        presenter.offerTranslation(languageCode: "fr", tabID: tabID(0))
        presenter.offerTranslation(languageCode: "es", tabID: tabID(1))
        #expect(presenter.translateOfferLanguageCode(for: tabID(0)) == nil)
        #expect(presenter.translateOfferLanguageCode(for: tabID(1)) == "es")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Translating closes the offer without keeping the tab from offering again", .timeLimit(.minutes(1)))
    func translate() {
        presenter.offerTranslation(languageCode: "es", tabID: tabID(0))
        presenter.answerTranslateOffer(for: tabID(0), translate: true)
        #expect(presenter.translateOfferLanguageCode(for: tabID(0)) == nil)

        presenter.offerTranslation(languageCode: "fr", tabID: tabID(0))
        #expect(presenter.translateOfferLanguageCode(for: tabID(0)) == "fr")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A queued or withdrawn offer records no language", .timeLimit(.minutes(1)))
    func withdrawnBeforeShown() async {
        presenter.offerTranslation(languageCode: "ja", tabID: tabID(1))
        presenter.offerTranslation(languageCode: nil, tabID: tabID(1))
        collection.select(at: .unpinned(1))
        for _ in 0..<20 { await Task.yield() }

        #expect(setting.offeredLanguageCodes.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Excluding a language or choosing Never Ask withdraws offers already waiting", .timeLimit(.minutes(1)))
    func settingChangesWithdrawWaitingOffers() {
        presenter.offerTranslation(languageCode: "fr", tabID: tabID(0))
        presenter.offerTranslation(languageCode: "fr", tabID: tabID(1))
        setting.exclude(languageCode: "fr")
        #expect(presenter.translateOfferLanguageCode(for: tabID(0)) == nil)
        #expect(presenter.translateOfferLanguageCode(for: tabID(1)) == nil)

        presenter.offerTranslation(languageCode: "de", tabID: tabID(1))
        setting.mode = .neverAsk
        #expect(presenter.translateOfferLanguageCode(for: tabID(1)) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The box stays ticked when the offer's popover is rebuilt on a tab switch", .timeLimit(.minutes(1)))
    func choiceSurvivesTabSwitch() {
        presenter.offerTranslation(languageCode: "es", tabID: tabID(0))
        presenter.translateOfferChoice(for: tabID(0))?.dontAskAgain = true
        collection.select(at: .unpinned(1))
        collection.select(at: .unpinned(0))

        presenter.answerTranslateOffer(for: tabID(0), translate: false)
        #expect(setting.excludedLanguageCodes == ["es"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A ticked box excludes the language on Translate and on No Thanks, and later pages in it don't offer", .timeLimit(.minutes(1)),
          arguments: [true, false])
    func dontAskAgain(translate: Bool) {
        presenter.offerTranslation(languageCode: "es", tabID: tabID(0))
        presenter.translateOfferChoice(for: tabID(0))?.dontAskAgain = true
        presenter.answerTranslateOffer(for: tabID(0), translate: translate)
        #expect(setting.excludedLanguageCodes == ["es"])

        presenter.offerTranslation(languageCode: "es", tabID: tabID(1))
        #expect(presenter.translateOfferLanguageCode(for: tabID(1)) == nil)
        presenter.offerTranslation(languageCode: "fr", tabID: tabID(1))
        #expect(presenter.translateOfferLanguageCode(for: tabID(1)) == "fr")
    }

    @available(iOS 16, macOS 13, *)
    @Test("An unticked box excludes nothing", .timeLimit(.minutes(1)))
    func unticked() {
        presenter.offerTranslation(languageCode: "es", tabID: tabID(0))
        presenter.answerTranslateOffer(for: tabID(0), translate: false)

        #expect(setting.excludedLanguageCodes.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Never Ask and excluded languages stop the offer, and nothing is recorded for them", .timeLimit(.minutes(1)))
    func settingGates() {
        setting.exclude(languageCode: "es")
        presenter.offerTranslation(languageCode: "es", tabID: tabID(0))
        #expect(presenter.translateOfferLanguageCode(for: tabID(0)) == nil)

        setting.mode = .neverAsk
        presenter.offerTranslation(languageCode: "fr", tabID: tabID(0))
        #expect(presenter.translateOfferLanguageCode(for: tabID(0)) == nil)
        #expect(setting.offeredLanguageCodes.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A closed tab's offer goes away", .timeLimit(.minutes(1)))
    func closedTab() {
        let closedTabID = tabID(1)
        presenter.offerTranslation(languageCode: "es", tabID: closedTabID)
        collection.remove(at: .unpinned(1))
        presenter.offerTranslation(languageCode: "fr", tabID: tabID(0))

        #expect(presenter.translateOfferLanguageCode(for: closedTabID) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A Fire Window never offers", .timeLimit(.minutes(1)))
    func burner() {
        let burner = Self.collection(urls: ["https://a.example"], burnerMode: BurnerMode(isBurner: true))
        let presenter = Self.presenter(collections: [burner])
        let tabID = burner.tabCollection.tabs[0].uuid

        presenter.offerTranslation(languageCode: "es", tabID: tabID)

        #expect(presenter.translateOfferLanguageCode(for: tabID) == nil)
    }
}

@MainActor
@Suite("Browser tool and local-model prompts take the Duck.ai button from the translate offer")
struct TranslateOfferPriorityTests {

    private let tabs: [Tab]
    private let collection: TabCollectionViewModel
    private let windowController: MainWindowController
    private let presenter: BrowserToolPermissionPromptPresenter
    private let suppressions = Suppressions()
    private let coordinator = ClientToolPermissionCoordinator(permissions: BrowserToolSitePermissions(permissionManager: PermissionManagerMock()))
    private let prompter = CapturingPrompter()

    init() {
        tabs = ["https://a.example", "https://b.example"].map { Tab(content: .url(URL(string: $0)!, credential: nil, source: .ui)) }
        collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs), windowControllersManager: WindowControllersManagerMock())
        let mainViewController = MainViewController(tabCollectionViewModel: collection,
                                                    autofillPopoverPresenter: DefaultAutofillPopoverPresenter(pinningManager: MockPinningManager()),
                                                    aiChatSessionStore: AIChatSessionStore(featureFlagger: MockFeatureFlagger()))
        let windows = WindowControllersManagerMock()
        windowController = MainWindowController(window: MockWindow(isVisible: false), mainViewController: mainViewController,
                                                fireViewModel: Application.appDelegate.fireCoordinator.fireViewModel,
                                                themeManager: MockThemeManager())
        windows.mainWindowControllers = [windowController]
        let suppressions = suppressions
        presenter = BrowserToolPermissionPromptPresenter(windowControllersManager: windows,
                                                         translatePages: TranslatePagesSetting(store: InMemoryKeyValueStore(), notificationCenter: NotificationCenter()),
                                                         translateOfferSuppressed: { suppressions.values.append($0) }) { _, _, _ in }
    }

    private func tab(_ index: Int) -> Tab { tabs[index] }

    /// Shows a tool prompt for the chat on `tab`, as Duck.ai asking to run a tool.
    private func showToolPrompt(for tab: Tab) async throws -> ClientToolPermissionPrompt {
        let coordinator = coordinator
        let prompter = prompter
        Task { _ = await coordinator.authorize(callID: UUID().uuidString, tool: SearchDownloadsBrowserTool(), prompter: prompter) }
        for _ in 0..<100 where prompter.prompt == nil { await Task.yield() }
        let prompt = try #require(prompter.prompt)
        #expect(presenter.present(prompt, chatWebView: tab.webView, prompter: prompter))
        return prompt
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page that qualifies while a tool prompt waits gets no offer, and is reported once", .timeLimit(.minutes(1)))
    func toolPromptWaiting() async throws {
        let prompt = try await showToolPrompt(for: tab(0))

        presenter.offerTranslation(languageCode: "es", tabID: tab(1).uuid)
        presenter.withdraw(requestID: prompt.requestID)
        presenter.offerTranslation(languageCode: "es", tabID: tab(1).uuid)

        #expect(presenter.translateOfferLanguageCode(for: tab(1).uuid) == nil)
        #expect(suppressions.values == [.browserTool])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A tool prompt closes the offers in its window, and they don't return on that page", .timeLimit(.minutes(1)))
    func toolPromptArrives() async throws {
        presenter.offerTranslation(languageCode: "es", tabID: tab(0).uuid)
        presenter.offerTranslation(languageCode: "fr", tabID: tab(1).uuid)

        let prompt = try await showToolPrompt(for: tab(0))
        #expect(presenter.translateOfferLanguageCode(for: tab(0).uuid) == nil)
        #expect(presenter.translateOfferLanguageCode(for: tab(1).uuid) == nil)
        #expect(suppressions.values == [.browserTool, .browserTool])

        presenter.withdraw(requestID: prompt.requestID)
        presenter.offerTranslation(languageCode: "es", tabID: tab(0).uuid)
        #expect(presenter.translateOfferLanguageCode(for: tab(0).uuid) == nil)

        presenter.offerTranslation(languageCode: nil, tabID: tab(0).uuid)
        presenter.offerTranslation(languageCode: "es", tabID: tab(0).uuid)
        #expect(presenter.translateOfferLanguageCode(for: tab(0).uuid) == "es")
        #expect(suppressions.values.count == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The local-model prompt closes the offer and skips pages that qualify while it shows", .timeLimit(.minutes(1)))
    func localModelPrompt() {
        presenter.offerTranslation(languageCode: "es", tabID: tab(0).uuid)

        presenter.localModelPromptWillShow(in: windowController.window)
        #expect(presenter.translateOfferLanguageCode(for: tab(0).uuid) == nil)
        presenter.offerTranslation(languageCode: "fr", tabID: tab(1).uuid)
        #expect(presenter.translateOfferLanguageCode(for: tab(1).uuid) == nil)
        #expect(suppressions.values == [.localModel, .localModel])

        presenter.localModelPromptDidClose()
        presenter.offerTranslation(languageCode: "es", tabID: tab(0).uuid)
        #expect(presenter.translateOfferLanguageCode(for: tab(0).uuid) == nil)
        presenter.offerTranslation(languageCode: nil, tabID: tab(0).uuid)
        presenter.offerTranslation(languageCode: "es", tabID: tab(0).uuid)
        #expect(presenter.translateOfferLanguageCode(for: tab(0).uuid) == "es")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A local-model prompt in another window leaves the offer alone", .timeLimit(.minutes(1)))
    func localModelPromptElsewhere() {
        presenter.offerTranslation(languageCode: "es", tabID: tab(0).uuid)

        presenter.localModelPromptWillShow(in: NSWindow())
        presenter.offerTranslation(languageCode: "fr", tabID: tab(1).uuid)

        #expect(presenter.translateOfferLanguageCode(for: tab(0).uuid) == "es")
        #expect(presenter.translateOfferLanguageCode(for: tab(1).uuid) == "fr")
        #expect(suppressions.values.isEmpty)
    }
}

@MainActor
private final class Suppressions {
    var values: [TranslateOfferSuppressor] = []
}

@MainActor
private final class CapturingPrompter: ClientToolPermissionPrompting {
    var prompt: ClientToolPermissionPrompt?
    func presentClientToolPermissionPrompt(_ prompt: ClientToolPermissionPrompt) -> Bool {
        self.prompt = prompt
        return true
    }
    func withdrawClientToolPermissionPrompt(requestID: String) {}
}

@MainActor
@Suite("Whether a tab may offer to translate its page")
struct TranslateOfferEligibilityTests {

    private static func canOffer(isFeatureOn: Bool = true, isWebPage: Bool = true, showsTranslationMenuItem: Bool = true,
                                 isPageAttachable: Bool = true, isSidebarOpen: Bool = false) -> Bool {
        PageContextTabExtension.canOfferTranslation(isFeatureOn: isFeatureOn, isWebPage: isWebPage, showsTranslationMenuItem: showsTranslationMenuItem,
                                                    isPageAttachable: isPageAttachable, isSidebarOpen: isSidebarOpen)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An attachable web page offers while the flag and the translate setting are on and no sidebar is open", .timeLimit(.minutes(1)))
    func eligible() {
        #expect(Self.canOffer())
    }

    @available(iOS 16, macOS 13, *)
    @Test("Any failing condition stops the offer", .timeLimit(.minutes(1)))
    func ineligible() {
        #expect(!Self.canOffer(isFeatureOn: false))
        #expect(!Self.canOffer(isWebPage: false))
        #expect(!Self.canOffer(showsTranslationMenuItem: false))
        #expect(!Self.canOffer(isPageAttachable: false))
        #expect(!Self.canOffer(isSidebarOpen: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning the flag off while an offer waits withdraws it", .timeLimit(.minutes(1)))
    func flagTurnsOff() async {
        let tab = Tab(content: .url(URL(string: "https://es.example")!, credential: nil, source: .ui))
        let windows = WindowControllersManagerMock()
        windows.customAllTabCollectionViewModels = [TabCollectionViewModel(tabCollection: TabCollection(tabs: [.loaded(tab)]), pinnedTabsManagerProvider: nil)]
        let flags = MockFeatureFlagger(featuresStub: [FeatureFlag.aiChatOfferTranslationAndSummarize.rawValue: true])
        let browserTools = AIChatBrowserToolsService(featureFlagger: flags, windowControllersManager: windows, historyCoordinator: HistoryCoordinatingMock(),
                                                     bookmarkManager: MockBookmarkManager(), permissionManager: PermissionManagerMock(),
                                                     translatePages: TranslatePagesSetting(store: InMemoryKeyValueStore(), notificationCenter: NotificationCenter()))
        let pageContext = PageContextTabExtension(scriptsPublisher: Empty<UserScripts, Never>(),
                                                  webViewPublisher: Empty<WKWebView, Never>(),
                                                  contentPublisher: Empty<Tab.TabContent, Never>(),
                                                  tabID: tab.uuid,
                                                  featureFlagger: flags,
                                                  privacyConfigurationManager: MockPrivacyConfigurationManager(),
                                                  extractionPixelHandler: PageContextExtractionPixelHandler(firePixel: { _ in }),
                                                  aiChatSessionStore: MockAIChatSessionStore(),
                                                  aiChatMenuConfiguration: MockAIChatConfig(),
                                                  isLoadedInSidebar: false,
                                                  faviconManagement: FaviconManagerMock(),
                                                  linkedPageLoader: NoLinkedPageLoader(),
                                                  browserTools: browserTools)
        browserTools.permissionPrompts.offerTranslation(languageCode: "es", tabID: tab.uuid)
        #expect(browserTools.permissionPrompts.translateOfferLanguageCode(for: tab.uuid) == "es")

        flags.featuresStub[FeatureFlag.aiChatOfferTranslationAndSummarize.rawValue] = false
        flags.triggerUpdate()
        for _ in 0..<20 { await Task.yield() }

        #expect(browserTools.permissionPrompts.translateOfferLanguageCode(for: tab.uuid) == nil)
        withExtendedLifetime(pageContext) {}
    }
}

private final class NoLinkedPageLoader: LinkedPageContextLoading {
    var sessionReadDomains = Set<String>()
    func load(_ url: URL) async -> LinkedPageContextLoadResult { .prevented("") }
}
