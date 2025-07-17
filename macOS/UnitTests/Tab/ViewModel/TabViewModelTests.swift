//
//  TabViewModelTests.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Combine
import DesignResourcesKitIcons
import FeatureFlags
import MaliciousSiteProtection
import Navigation
import PersistenceTestingUtils
import Subscription
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class TabViewModelTests: XCTestCase {

    let maliciousSite = URL("https://www.google.com")!
    var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables = []
    }

    // MARK: - Can reload

    @MainActor
    func testWhenURLIsNilThenCanReloadIsFalse() {
        let tabViewModel = TabViewModel.aTabViewModel

        XCTAssertFalse(tabViewModel.canReload)
    }

    @MainActor
    func testWhenURLIsNotNilThenCanReloadIsTrue() {
        let tabViewModel = TabViewModel.forTabWithURL(.duckDuckGo)

        let canReloadExpectation = expectation(description: "Can reload")
        tabViewModel.$canReload.debounce(for: 0.1, scheduler: RunLoop.main).sink { _ in
            XCTAssert(tabViewModel.canReload)
            canReloadExpectation.fulfill()
        } .store(in: &cancellables)
        waitForExpectations(timeout: 2, handler: nil)
    }

    // MARK: - AddressBarString

    @MainActor
    func testWhenURLIsNilThenAddressBarStringIsEmpty() {
        let tabViewModel = TabViewModel.aTabViewModel

        XCTAssertEqual(tabViewModel.addressBarString, "")
    }

    @MainActor
    func testWhenURLIsSetThenAddressBarIsUpdated() {
        let urlString = "http://spreadprivacy.com"
        let url = URL.makeURL(from: urlString)!
        let tabViewModel = TabViewModel.forTabWithURL(url)

        let addressBarStringExpectation = expectation(description: "Address bar string")

        tabViewModel.simulateLoadingCompletion(url, in: tabViewModel.tab.webView)

        tabViewModel.$addressBarString.debounce(for: 0.5, scheduler: RunLoop.main).sink { _ in
            XCTAssertEqual(tabViewModel.addressBarString, urlString)
            addressBarStringExpectation.fulfill()
        } .store(in: &cancellables)
        waitForExpectations(timeout: 1, handler: nil)
    }

    @MainActor
    func testWhenURLIsFileURLAndShowFullUrlIsDisabledThenAddressBarIsFileName() {
        let urlString = "file:///Users/Dax/file.txt"
        let url = URL.makeURL(from: urlString)!
        let tab = Tab(content: .url(url, source: .link))
        let appearancePreferences = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(showFullURL: false),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger()
        )
        let tabViewModel = TabViewModel(tab: tab, appearancePreferences: appearancePreferences)

        let addressBarStringExpectation = expectation(description: "Address bar string")

        tabViewModel.simulateLoadingCompletion(url, in: tabViewModel.tab.webView)

        tabViewModel.$addressBarString.debounce(for: 0.1, scheduler: RunLoop.main).sink { _ in
            XCTAssertEqual(tabViewModel.addressBarString, urlString)
            XCTAssertEqual(tabViewModel.passiveAddressBarAttributedString.string, url.lastPathComponent)
            addressBarStringExpectation.fulfill()
        } .store(in: &cancellables)
        waitForExpectations(timeout: 1, handler: nil)
    }

    @MainActor
    func testWhenURLIsFileURLAndShowFullUrlIsEnabledThenAddressBarIsFilePath() {
        let urlString = "file:///Users/Dax/file.txt"
        let url = URL.makeURL(from: urlString)!
        let tab = Tab(content: .url(url, source: .link))
        let appearancePreferences = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(showFullURL: true),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger()
        )
        let tabViewModel = TabViewModel(tab: tab, appearancePreferences: appearancePreferences)

        let addressBarStringExpectation = expectation(description: "Address bar string")

        tabViewModel.simulateLoadingCompletion(url, in: tabViewModel.tab.webView)

        tabViewModel.$addressBarString.debounce(for: 0.1, scheduler: RunLoop.main).sink { _ in
            XCTAssertEqual(tabViewModel.addressBarString, urlString)
            XCTAssertEqual(tabViewModel.passiveAddressBarAttributedString.string, urlString)
            addressBarStringExpectation.fulfill()
        } .store(in: &cancellables)
        waitForExpectations(timeout: 1, handler: nil)
    }

    @MainActor
    func testWhenURLIsDataURLThenAddressBarIsDataURL() {
        let urlString = "data:,Hello%2C%20World%21"
        let url = URL.makeURL(from: urlString)!
        let tabViewModel = TabViewModel.forTabWithURL(url)

        let addressBarStringExpectation = expectation(description: "Address bar string")

        tabViewModel.simulateLoadingCompletion(url, in: tabViewModel.tab.webView)

        tabViewModel.$addressBarString.debounce(for: 0.1, scheduler: RunLoop.main).sink { _ in
            XCTAssertEqual(tabViewModel.addressBarString, urlString)
            XCTAssertEqual(tabViewModel.passiveAddressBarAttributedString.string, "data:")
            addressBarStringExpectation.fulfill()
        } .store(in: &cancellables)
        waitForExpectations(timeout: 1, handler: nil)
    }

    @MainActor
    func testWhenURLIsBlobURLWithBasicAuthThenAddressBarStripsBasicAuth() {
        let urlStrings = ["blob:https://spoofed.domain.com%20%20%20%20%20%20%20%20%20@attacker.com",
                          "blob:ftp://another.spoofed.domain.com%20%20%20%20%20%20%20%20%20@attacker.com",
                          "blob:http://yetanother.spoofed.domain.com%20%20%20%20%20%20%20%20%20@attacker.com"]
        let expectedStarts = ["blob:https://", "blob:ftp://", "blob:http://"]
        let expectedNotContains = ["spoofed.domain.com", "another.spoofed.domain.com", "yetanother.spoofed.domain.com"]
        let uuidPattern = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        let uuidRegex = try! NSRegularExpression(pattern: uuidPattern, options: [])

        for i in 0..<urlStrings.count {
            let url = URL.makeURL(from: urlStrings[i])!
            let tabViewModel = TabViewModel.forTabWithURL(url)
            let addressBarStringExpectation = expectation(description: "Address bar string")
            tabViewModel.simulateLoadingCompletion(url, in: tabViewModel.tab.webView)

            tabViewModel.$addressBarString.debounce(for: 0.1, scheduler: RunLoop.main).sink { _ in
                XCTAssertTrue(tabViewModel.addressBarString.starts(with: expectedStarts[i]))
                XCTAssertTrue(tabViewModel.addressBarString.contains("attacker.com"))
                XCTAssertFalse(tabViewModel.addressBarString.contains(expectedNotContains[i]))
                let range = NSRange(location: 0, length: tabViewModel.addressBarString.utf16.count)
                let match = uuidRegex.firstMatch(in: tabViewModel.addressBarString, options: [], range: range)
                XCTAssertNotNil(match, "URL does not end with a GUID")
                addressBarStringExpectation.fulfill()
            } .store(in: &cancellables)
            waitForExpectations(timeout: 1, handler: nil)
        }
    }

    // MARK: - Title

    @MainActor
    func testWhenNewTabPageIsOpenThenTitleIsNewTab() {
        let tab = Tab(content: .newtab)
        let tabViewModel = TabViewModel(tab: tab)

        XCTAssertEqual(tabViewModel.title, UserText.tabHomeTitle)
    }

    @MainActor
    func testWhenTabTitleIsNotNilThenTitleReflectsTabTitle() async throws {
        let tabViewModel = TabViewModel.forTabWithURL(.duckDuckGo)
        let testTitle = "Test title"

        let titleExpectation = expectation(description: "Title")
        tabViewModel.$title.dropFirst().sink {
            if case .failure(let error) = $0 {
                XCTFail("\(error)")
            }
        } receiveValue: { title in
            XCTAssertEqual(title, testTitle)
            titleExpectation.fulfill()
        } .store(in: &cancellables)

        tabViewModel.tab.title = testTitle

        await fulfillment(of: [titleExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenTabTitleIsNilThenTitleIsAddressBarString() {
        let tabViewModel = TabViewModel.forTabWithURL(.duckDuckGo)

        let titleExpectation = expectation(description: "Title")

        tabViewModel.$title.debounce(for: 0.01, scheduler: RunLoop.main).sink { title in
            XCTAssertEqual(title, URL.duckDuckGo.host!)
            titleExpectation.fulfill()
        } .store(in: &cancellables)
        waitForExpectations(timeout: 1, handler: nil)
    }

    // MARK: - Favicon

    @MainActor
    func testWhenContentIsNoneThenFaviconIsNil() {
        let tabViewModel = TabViewModel.forTabWithURL(URL.duckDuckGo)
        tabViewModel.tab.setContent(.none)

        XCTAssertEqual(tabViewModel.favicon, nil)
    }

    @MainActor
    func testWhenContentIsHomeThenFaviconIsHome() {
        let tabViewModel = TabViewModel.aTabViewModel
        tabViewModel.tab.setContent(.newtab)

        let faviconExpectation = expectation(description: "Favicon")
        var fulfilled = false

        tabViewModel.$favicon.debounce(for: 0.1, scheduler: RunLoop.main).sink { favicon in
            guard favicon != nil else { return }
            if favicon?.pngData() == NSImage.homeFavicon.pngData(),
                !fulfilled {
                faviconExpectation.fulfill()
                fulfilled = true
            }
        } .store(in: &cancellables)
        waitForExpectations(timeout: 5, handler: nil)

        XCTAssertImagesEqual(tabViewModel.favicon, .homeFavicon)
    }

    // MARK: - TabContent+DisplayedFavicon Tests

    @MainActor
    func testDisplayedFaviconWithSSLError() {
        let sslError = WKError(_nsError: NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorServerCertificateUntrusted,
            userInfo: [NSURLErrorFailingURLErrorKey: URL.duckDuckGo]
        ))
        let tabViewModel = TabViewModel.forTabWithURL(URL.duckDuckGo)
        tabViewModel.tab.error = sslError

        XCTAssertImagesEqual(tabViewModel.favicon, .redAlertCircle16)
    }

    @MainActor
    func testDisplayedFaviconWithMaliciousErrorPhishing() {
        let maliciousError = WKError(_nsError: MaliciousSiteError(code: .phishing, failingUrl: maliciousSite) as NSError)
        let tabViewModel = TabViewModel.forTabWithURL(URL.duckDuckGo)
        tabViewModel.tab.error = maliciousError

        XCTAssertImagesEqual(tabViewModel.favicon, .redAlertCircle16)
    }

    @MainActor
    func testDisplayedFaviconWithMaliciousErrorMalware() {
        let maliciousError = WKError(_nsError: MaliciousSiteError(code: .malware, failingUrl: maliciousSite) as NSError)
        let tabViewModel = TabViewModel.forTabWithURL(URL.duckDuckGo)
        tabViewModel.tab.error = maliciousError

        XCTAssertImagesEqual(tabViewModel.favicon, .redAlertCircle16)
    }

    @MainActor
    func testDisplayedFaviconWithMaliciousErrorScam() {
        let maliciousError = WKError(_nsError: MaliciousSiteError(code: .scam, failingUrl: maliciousSite) as NSError)
        let tabViewModel = TabViewModel.forTabWithURL(URL.duckDuckGo)
        tabViewModel.tab.error = maliciousError

        XCTAssertImagesEqual(tabViewModel.favicon, .redAlertCircle16)
    }

    @MainActor
    func testDisplayedFaviconWithWebContentProcessTermination() {
        let wkError = WKError(.webContentProcessTerminated)
        let tabViewModel = TabViewModel.forTabWithURL(URL.duckDuckGo)
        tabViewModel.tab.error = wkError

        XCTAssertImagesEqual(tabViewModel.favicon, .alertCircleColor16)
    }

    @MainActor
    func testDisplayedFaviconWithGenericError() {
        let genericError = WKError(_nsError: NSError(domain: "TestDomain", code: 500, userInfo: nil))
        let tabViewModel = TabViewModel.forTabWithURL(URL.duckDuckGo)
        tabViewModel.tab.error = genericError

        XCTAssertImagesEqual(tabViewModel.favicon, .alertCircleColor16)
    }

    @MainActor
    func testDisplayedFaviconForDataBrokerProtection() {
        let tabViewModel = TabViewModel.forTabWithURL(URL.dataBrokerProtection)

        XCTAssertImagesEqual(tabViewModel.favicon, .personalInformationRemovalMulticolor16)
    }

    @MainActor
    func testDisplayedFaviconForNewTabWithBurnerNewStyle() {
        let mockVisualStyle = MockVisualStyle(isNewStyle: true)
        let tabViewModel = TabViewModel.forTabWithURL(
            URL.newtab,
            visualStyle: mockVisualStyle,
            burnerMode: BurnerMode(isBurner: true)
        )

        XCTAssertImagesEqual(tabViewModel.favicon, DesignSystemImages.Glyphs.Size16.fireTab)
    }

    @MainActor
    func testDisplayedFaviconForNewTabWithBurnerOldStyle() {
        let mockVisualStyle = MockVisualStyle(isNewStyle: false)
        let tabViewModel = TabViewModel.forTabWithURL(
            URL.newtab,
            visualStyle: mockVisualStyle,
            burnerMode: BurnerMode(isBurner: true)
        )

        XCTAssertImagesEqual(tabViewModel.favicon, .burnerTabFavicon)
    }

    @MainActor
    func testDisplayedFaviconForNewTabNonBurner() {
        let tabViewModel = TabViewModel.forTabWithURL(URL.newtab)

        XCTAssertImagesEqual(tabViewModel.favicon, .homeFavicon)
    }

    @MainActor
    func testDisplayedFaviconForSettings() {
        for pane in PreferencePaneIdentifier.allCases {
            let tabViewModel = TabViewModel.forTabWithURL(URL.settingsPane(pane))

            if pane == .otherPlatforms /* this is a link */ {
                XCTAssertNil(tabViewModel.favicon)
            } else {
                XCTAssertImagesEqual(tabViewModel.favicon, .settingsMulticolor16, "Failed for \(pane)")
            }
        }
    }

    @MainActor
    func testDisplayedFaviconForBookmarks() {
        let tabViewModel = TabViewModel.forTabWithURL(URL.bookmarks)

        XCTAssertImagesEqual(tabViewModel.favicon, .bookmarksFolder)
    }

    @MainActor
    func testDisplayedFaviconForHistoryWithFeatureEnabled() {
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.historyView]

        let tabViewModel = TabViewModel.forTabWithURL(URL.history, featureFlagger: mockFeatureFlagger)

        XCTAssertImagesEqual(tabViewModel.favicon, .historyFavicon)
    }

    @MainActor
    func testDisplayedFaviconForHistoryWithFeatureDisabled() {
        let mockFeatureFlagger = MockFeatureFlagger() // .historyView defaults to nil/false

        let tabViewModel = TabViewModel.forTabWithURL(URL.history, featureFlagger: mockFeatureFlagger)

        XCTAssertNil(tabViewModel.favicon)
    }

    @MainActor
    func testDisplayedFaviconForSubscription() {
        let tabViewModel = TabViewModel.forTabWithURL(SubscriptionURL.baseURL.subscriptionURL(environment: .production))

        XCTAssertImagesEqual(tabViewModel.favicon, .privacyPro)
    }

    @MainActor
    func testDisplayedFaviconForIdentityTheftRestoration() {
        let tabViewModel = TabViewModel.forTabWithURL(SubscriptionURL.identityTheftRestoration.subscriptionURL(environment: .production))

        XCTAssertImagesEqual(tabViewModel.favicon, .identityTheftRestorationMulticolor16)
    }

    @MainActor
    func testDisplayedFaviconForReleaseNotes() {
        let tabViewModel = TabViewModel.forTabWithURL(URL.releaseNotes)

        XCTAssertImagesEqual(tabViewModel.favicon, .homeFavicon)
    }

    @MainActor
    func testDisplayedFaviconForAIChat() {
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatSidebar]
        let aiChatURL = URL(string: "https://duckduckgo.com/?q=DuckDuckGo+AI+Chat&ia=chat&duckai=2")!
        let tabViewModel = TabViewModel.forTabWithURL(aiChatURL, featureFlagger: mockFeatureFlagger)

        XCTAssertImagesEqual(tabViewModel.favicon, .aiChatPreferences)
    }

    @MainActor
    func testDisplayedFaviconForDuckAIURL() {
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatSidebar]
        let duckAIURL = URL(string: "https://duck.ai/chat")!
        let tabViewModel = TabViewModel.forTabWithURL(duckAIURL, featureFlagger: mockFeatureFlagger)

        XCTAssertNil(tabViewModel.favicon) // not an actual ai chat url: loaded by the Tab
    }

    @MainActor
    func testDisplayedFaviconForDuckPlayerURL() {
        let duckPlayerURL = URL.duckPlayer("test")
        let tabViewModel = TabViewModel.forTabWithURL(duckPlayerURL)

        XCTAssertImagesEqual(tabViewModel.favicon, .duckPlayerSettings)
    }

    @MainActor
    func testDisplayedFaviconForHistoryURLWithFeatureEnabled() {
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.historyView]

        let tabViewModel = TabViewModel.forTabWithURL(URL.history, featureFlagger: mockFeatureFlagger)

        XCTAssertImagesEqual(tabViewModel.favicon, .historyFavicon)
    }

    @MainActor
    func testDisplayedFaviconForHistoryURLWithFeatureDisabled() {
        let mockFeatureFlagger = MockFeatureFlagger() // .historyView defaults to nil/false

        let tabViewModel = TabViewModel.forTabWithURL(URL.history, featureFlagger: mockFeatureFlagger)

        XCTAssertNil(tabViewModel.favicon)
    }

    @MainActor
    func testDisplayedFaviconForEmailProtectionURL() {
        let tabViewModel = TabViewModel.forTabWithURL(URL.duckDuckGoEmail)

        XCTAssertImagesEqual(tabViewModel.favicon, .emailProtectionIcon)
    }

    @MainActor
    func testDisplayedFaviconForRegularURLWithActualFavicon() {
        let regularURL = URL(string: "https://example.com")!
        let actualFavicon = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!

        let tabViewModel = TabViewModel.forTabWithURL(regularURL)
        tabViewModel.tab.favicon = actualFavicon

        XCTAssertImagesEqual(tabViewModel.favicon, actualFavicon)
    }

    @MainActor
    func testDisplayedFaviconForRegularURLWithoutActualFavicon() {
        let regularURL = URL(string: "https://example.com")!

        let tabViewModel = TabViewModel.forTabWithURL(regularURL)
        tabViewModel.tab.favicon = nil

        XCTAssertNil(tabViewModel.favicon)
    }

    @MainActor
    func testDisplayedFaviconForOnboardingWithActualFavicon() {
        let actualFavicon = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!

        let tabViewModel = TabViewModel.forTabWithURL(URL.duckDuckGo)
        tabViewModel.tab.setContent(.onboarding)
        tabViewModel.tab.favicon = actualFavicon

        XCTAssertImagesEqual(tabViewModel.favicon, actualFavicon)
    }

    @MainActor
    func testDisplayedFaviconForWebExtensionWithActualFavicon() {
        let extensionURL = URL(string: "webkit-extension://test")!
        let actualFavicon = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!

        let tabViewModel = TabViewModel.forTabWithURL(URL.duckDuckGo)
        tabViewModel.tab.setContent(.webExtensionUrl(extensionURL))
        tabViewModel.tab.favicon = actualFavicon

        XCTAssertImagesEqual(tabViewModel.favicon, actualFavicon)
    }

    @MainActor
    func testDisplayedFaviconForNoneWithActualFavicon() {
        let actualFavicon = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!

        let tabViewModel = TabViewModel.forTabWithURL(URL.duckDuckGo)
        tabViewModel.tab.setContent(.none)
        tabViewModel.tab.favicon = actualFavicon

        XCTAssertImagesEqual(tabViewModel.favicon, actualFavicon)
    }

    // MARK: - Zoom

    @MainActor
    func testThatDefaultValueForTabsWebViewIsOne() throws {
        UserDefaultsWrapper<Any>.clearAll()
        let tabVM = TabViewModel(
            tab: Tab(),
            appearancePreferences: AppearancePreferences(
                keyValueStore: try MockKeyValueFileStore(),
                privacyConfigurationManager: MockPrivacyConfigurationManager(),
                featureFlagger: MockFeatureFlagger()
            ),
            accessibilityPreferences: AccessibilityPreferences()
        )

        XCTAssertEqual(tabVM.tab.webView.zoomLevel, DefaultZoomValue.percent100)
    }

    @MainActor
    func testWhenPreferencesDefaultZoomLevelIsSetThenTabsWebViewZoomLevelIsUpdated() {
        UserDefaultsWrapper<Any>.clearAll()
        let tabVM = TabViewModel(tab: Tab())
        let filteredCases = DefaultZoomValue.allCases.filter { $0 != AccessibilityPreferences.shared.defaultPageZoom }
        let randomZoomLevel = filteredCases.randomElement()!
        AccessibilityPreferences.shared.defaultPageZoom = randomZoomLevel

        XCTAssertEqual(tabVM.tab.webView.zoomLevel, randomZoomLevel)
    }

    @MainActor
    func testWhenPreferencesDefaultZoomLevelIsSetAndANewTabIsOpenThenItsWebViewHasTheLatestValueOfZoomLevel() throws {
        UserDefaultsWrapper<Any>.clearAll()
        let filteredCases = DefaultZoomValue.allCases.filter { $0 != AccessibilityPreferences.shared.defaultPageZoom }
        let randomZoomLevel = filteredCases.randomElement()!
        AccessibilityPreferences.shared.defaultPageZoom = randomZoomLevel

        let tabVM = TabViewModel(
            tab: Tab(),
            appearancePreferences: AppearancePreferences(
                keyValueStore: try MockKeyValueFileStore(),
                privacyConfigurationManager: MockPrivacyConfigurationManager(),
                featureFlagger: MockFeatureFlagger()
            )
        )

        XCTAssertEqual(tabVM.tab.webView.zoomLevel, randomZoomLevel)
    }

    @MainActor
    func test_WhenPreferencesDefaultZoomLevelIsSet_AndThereIsAZoomLevelForWebsite_ThenTabsWebViewZoomLevelIsNotUpdated() {
        // GIVEN
        UserDefaultsWrapper<Any>.clearAll()
        let url = URL(string: "https://app.asana.com/0/1")!
        let hostURL = "https://app.asana.com/"
        let filteredCases = DefaultZoomValue.allCases.filter { $0 != AccessibilityPreferences.shared.defaultPageZoom }
        let randomZoomLevel = filteredCases.randomElement()!
        AccessibilityPreferences.shared.updateZoomPerWebsite(zoomLevel: randomZoomLevel, url: hostURL)
        var tab = Tab(url: url)
        var tabVM = TabViewModel(tab: tab)

        // WHEN
        AccessibilityPreferences.shared.defaultPageZoom = .percent50
        tab = Tab(url: url)
        tabVM = TabViewModel(tab: tab)

        // THEN
        XCTAssertEqual(tabVM.tab.webView.zoomLevel, randomZoomLevel)
    }

    @MainActor
    func test_WhenPreferencesDefaultZoomLevelIsSet_AndThereIsAZoomLevelForWebsite_AndIsFireWindow_ThenTabsWebViewZoomLevelIsNotUpdated() {
        // GIVEN
        UserDefaultsWrapper<Any>.clearAll()
        let url = URL(string: "https://app.asana.com/0/1")!
        let hostURL = "https://app.asana.com/"
        let filteredCases = DefaultZoomValue.allCases.filter { $0 != AccessibilityPreferences.shared.defaultPageZoom }
        let randomZoomLevel = filteredCases.randomElement()!
        AccessibilityPreferences.shared.updateZoomPerWebsite(zoomLevel: randomZoomLevel, url: hostURL)
        let tab = Tab(url: url)
        var tabVM = TabViewModel(tab: tab)

        // WHEN
        AccessibilityPreferences.shared.defaultPageZoom = .percent50
        let burnerTab = Tab(content: .url(url, credential: nil, source: .ui), burnerMode: BurnerMode(isBurner: true))
        tabVM = TabViewModel(tab: burnerTab)

        // THEN
        XCTAssertEqual(tabVM.tab.webView.zoomLevel, AccessibilityPreferences.shared.defaultPageZoom)
    }

    @MainActor
    func test_WhenPreferencesZoomPerWebsiteLevelIsSet_AndANewTabIsOpen_ThenItsWebViewHasTheLatestValueOfZoomLevel() throws {
        // GIVEN
        UserDefaultsWrapper<Any>.clearAll()
        let url = URL(string: "https://app.asana.com/0/1")!
        let hostURL = "https://app.asana.com/"
        let filteredCases = DefaultZoomValue.allCases.filter { $0 != AccessibilityPreferences.shared.defaultPageZoom }
        let randomZoomLevel = filteredCases.randomElement()!
        AccessibilityPreferences.shared.updateZoomPerWebsite(zoomLevel: randomZoomLevel, url: hostURL)

        // WHEN
        let tab = Tab(url: url)
        let tabVM = TabViewModel(
            tab: tab,
            appearancePreferences: AppearancePreferences(
                keyValueStore: try MockKeyValueFileStore(),
                privacyConfigurationManager: MockPrivacyConfigurationManager(),
                featureFlagger: MockFeatureFlagger()
            )
        )

        // THEN
        XCTAssertEqual(tabVM.tab.webView.zoomLevel, randomZoomLevel)
    }

    @MainActor
    func test_WhenPreferencesZoomPerWebsiteLevelIsSet_AndANewBurnerTabIsOpen_ThenItsWebViewHasTheDefaultZoomLevel() throws {
        // GIVEN
        UserDefaultsWrapper<Any>.clearAll()
        let url = URL(string: "https://app.asana.com/0/1")!
        let hostURL = "https://app.asana.com/"
        let filteredCases = DefaultZoomValue.allCases.filter { $0 != AccessibilityPreferences.shared.defaultPageZoom }
        let randomZoomLevel = filteredCases.randomElement()!
        AccessibilityPreferences.shared.updateZoomPerWebsite(zoomLevel: randomZoomLevel, url: hostURL)

        // WHEN
        let burnerTab = Tab(content: .url(url, credential: nil, source: .ui), burnerMode: BurnerMode(isBurner: true))
        let tabVM = TabViewModel(
            tab: burnerTab,
            appearancePreferences: AppearancePreferences(
                keyValueStore: try MockKeyValueFileStore(),
                privacyConfigurationManager: MockPrivacyConfigurationManager(),
                featureFlagger: MockFeatureFlagger()
            )
        )

        // THEN
        XCTAssertEqual(tabVM.tab.webView.zoomLevel, AccessibilityPreferences.shared.defaultPageZoom)
    }

    @MainActor
    func test_WhenPreferencesZoomPerWebsiteLevelIsSet_ThenTabsWebViewZoomLevelIsUpdated() async {
        // GIVEN
        UserDefaultsWrapper<Any>.clearAll()
        let url = URL(string: "https://app.asana.com/0/1")!
        let hostURL = "https://app.asana.com/"
        let tab = Tab(url: url)
        let tabVM = TabViewModel(tab: tab)
        let filteredCases = DefaultZoomValue.allCases.filter { $0 != AccessibilityPreferences.shared.defaultPageZoom }
        let randomZoomLevel = filteredCases.randomElement()!

        // WHEN
        AccessibilityPreferences.shared.updateZoomPerWebsite(zoomLevel: randomZoomLevel, url: hostURL)

        // THEN
        await MainActor.run {
            XCTAssertEqual(tabVM.tab.webView.zoomLevel, randomZoomLevel, "Tab's web view zoom level was not updated as expected.")
        }
    }

    @MainActor
    func test_WhenPreferencesZoomPerWebsiteLevelIsSet_AndIsFireWindow_ThenTabsWebViewZoomLevelIsNot() async {
        // GIVEN
        UserDefaultsWrapper<Any>.clearAll()
        let url = URL(string: "https://app.asana.com/0/1")!
        let hostURL = "https://app.asana.com/"
        let burnerTab = Tab(content: .url(url, credential: nil, source: .ui), burnerMode: BurnerMode(isBurner: true))
        let tabVM = TabViewModel(tab: burnerTab)
        let filteredCases = DefaultZoomValue.allCases.filter { $0 != AccessibilityPreferences.shared.defaultPageZoom }
        let randomZoomLevel = filteredCases.randomElement()!

        // WHEN
        AccessibilityPreferences.shared.updateZoomPerWebsite(zoomLevel: randomZoomLevel, url: hostURL)

        // THEN
        await MainActor.run {
            XCTAssertEqual(tabVM.tab.webView.zoomLevel, AccessibilityPreferences.shared.defaultPageZoom)
        }
    }

    @MainActor
    func test_WhenZoomWasSetIsCalled_ThenAppearancePreferencesPerWebsiteZoomIsSet() {
        // GIVEN
        let url = URL(string: "https://app.asana.com/0/1")!
        let hostURL = "https://app.asana.com/"
        UserDefaultsWrapper<Any>.clearAll()
        let tab = Tab(url: url)
        let tabVM = TabViewModel(tab: tab)
        let filteredCases = DefaultZoomValue.allCases.filter { $0 !=  AccessibilityPreferences.shared.defaultPageZoom }
        let randomZoomLevel = filteredCases.randomElement()!

        // WHEN
        tabVM.zoomWasSet(to: randomZoomLevel)

        // THEN
        XCTAssertEqual(AccessibilityPreferences.shared.zoomPerWebsite(url: hostURL), randomZoomLevel)
    }

    @MainActor
    func test_WhenZoomWasSetIsCalled_AndIsFireWindow_ThenAppearancePreferencesPerWebsiteZoomIsNotSet() {
        // GIVEN
        let url = URL(string: "https://app.asana.com/0/1")!
        let hostURL = "https://app.asana.com/"
        AccessibilityPreferences.shared.updateZoomPerWebsite(zoomLevel: AccessibilityPreferences.shared.defaultPageZoom, url: hostURL)
        UserDefaultsWrapper<Any>.clearAll()
        let burnerTab = Tab(content: .url(url, credential: nil, source: .ui), burnerMode: BurnerMode(isBurner: true))
        let tabVM = TabViewModel(tab: burnerTab)
        let filteredCases = DefaultZoomValue.allCases.filter { $0 !=  AccessibilityPreferences.shared.defaultPageZoom }
        let randomZoomLevel = filteredCases.randomElement()!

        // WHEN
        print(randomZoomLevel)
        tabVM.zoomWasSet(to: randomZoomLevel)

        // THEN
        XCTAssertEqual(AccessibilityPreferences.shared.zoomPerWebsite(url: hostURL), nil)
    }

    @MainActor
    func test_WhenWebViewResetZoomLevelForASite_ThenNoZoomSavedForTheSite() {
        // GIVEN
        let url = URL(string: "https://app.asana.com/0/1")!
        let hostURL = "https://app.asana.com/"
        UserDefaultsWrapper<Any>.clearAll()
        let filteredCases = DefaultZoomValue.allCases.filter { $0 != AccessibilityPreferences.shared.defaultPageZoom }
        let randomZoomLevel = filteredCases.randomElement()!
        AccessibilityPreferences.shared.updateZoomPerWebsite(zoomLevel: randomZoomLevel, url: hostURL)
        let tab = Tab(url: url)
        let tabView = TabViewModel(tab: tab)

        // WHEN
        tabView.tab.webView.resetZoomLevel()

        // THEN
        XCTAssertEqual(AccessibilityPreferences.shared.zoomPerWebsite(url: hostURL), nil)
    }

    @MainActor
    func test_WhenWebViewZoomInForASite_ThenNewZoomSavedForTheSite() async {
        // GIVEN
        let url = URL(string: "https://app.asana.com/0/1")!
        let hostURL = "https://app.asana.com/"
        UserDefaultsWrapper<Any>.clearAll()
        let (randomZoomLevel, nextZoomLevel, _) = randomLevelAndAdjacent()
        let window = MockWindow()
        window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        AccessibilityPreferences.shared.updateZoomPerWebsite(zoomLevel: randomZoomLevel, url: hostURL)
        let tab = Tab(url: url)
        window.contentView?.addSubview(tab.webView)
        tab.webView.frame = window.contentView!.bounds
        let tabView = TabViewModel(tab: tab)

        // WHEN
        tabView.tab.webView.zoomIn()

        // THEN
        if nextZoomLevel == AccessibilityPreferences.shared.defaultPageZoom {
            XCTAssertNil(AccessibilityPreferences.shared.zoomPerWebsite(url: hostURL))
        } else {
            XCTAssertEqual(AccessibilityPreferences.shared.zoomPerWebsite(url: hostURL), nextZoomLevel)
        }
    }

    @MainActor
    func test_WhenWebViewZoomOutForASite_ThenNewZoomSavedForTheSite() async {
        // GIVEN
        let url = URL(string: "https://app.asana.com/0/1")!
        let hostURL = "https://app.asana.com/"
        UserDefaultsWrapper<Any>.clearAll()
        let (randomZoomLevel, _, previousZoomLevel) = randomLevelAndAdjacent()
        let window = MockWindow()
        window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        AccessibilityPreferences.shared.updateZoomPerWebsite(zoomLevel: randomZoomLevel, url: hostURL)
        let tab = Tab(url: url)
        window.contentView?.addSubview(tab.webView)
        tab.webView.frame = window.contentView!.bounds
        let tabView = TabViewModel(tab: tab)

        // WHEN
        tabView.tab.webView.zoomOut()

        // THEN
        if previousZoomLevel == AccessibilityPreferences.shared.defaultPageZoom {
            XCTAssertNil(AccessibilityPreferences.shared.zoomPerWebsite(url: hostURL))
        } else {
            XCTAssertEqual(AccessibilityPreferences.shared.zoomPerWebsite(url: hostURL), previousZoomLevel)
        }
    }

    private func randomLevelAndAdjacent() -> (randomLevel: DefaultZoomValue, nextLevel: DefaultZoomValue, previousLevel: DefaultZoomValue) {
        let allCases = DefaultZoomValue.allCases

        let selectableRange = 1..<(allCases.count - 1)
        let randomIndex = selectableRange.randomElement()!
        let randomLevel = allCases[randomIndex]

        let nextLevel = allCases[randomIndex + 1]
        let previousLevel = allCases[randomIndex - 1]

        return (randomLevel, nextLevel, previousLevel)
    }
}

extension TabViewModel {

    @MainActor
    static var aTabViewModel: TabViewModel {
        let tab = Tab()
        return TabViewModel(tab: tab)
    }

    @MainActor
    static func forTabWithURL(
        _ url: URL,
        featureFlagger: FeatureFlagger? = nil,
        visualStyle: VisualStyleProviding? = nil,
        burnerMode: BurnerMode = .regular
    ) -> TabViewModel {
        let tab = Tab(
            content: .contentFromURL(url, source: .link),
            burnerMode: burnerMode
        )

        if let featureFlagger = featureFlagger {
            let appearancePreferences = AppearancePreferences(
                keyValueStore: try! MockKeyValueFileStore(),
                privacyConfigurationManager: MockPrivacyConfigurationManager(),
                featureFlagger: featureFlagger
            )
            return TabViewModel(
                tab: tab,
                appearancePreferences: appearancePreferences,
                featureFlagger: featureFlagger,
                visualStyle: visualStyle ?? NSApp.delegateTyped.visualStyle
            )
        } else {
            return TabViewModel(tab: tab, visualStyle: visualStyle ?? NSApp.delegateTyped.visualStyle)
        }
    }

    @MainActor
    func simulateLoadingCompletion(_ url: URL, in webView: WKWebView) {
        let navAction = NavigationAction(request: URLRequest(url: url), navigationType: .other, currentHistoryItemIdentity: nil, redirectHistory: nil, isUserInitiated: nil, sourceFrame: .mainFrame(for: webView), targetFrame: .mainFrame(for: webView), shouldDownload: false, mainFrameNavigation: nil)
        let navigation = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [navAction], isCurrent: true, isCommitted: true)
        self.tab.didCommit(navigation)
    }

}

private extension Tab {
    @MainActor
    convenience init(url: URL? = nil) {
        self.init(content: url.map { TabContent.url($0, source: .link) } ?? .none)
    }
}

// MARK: - Test Mocks

final class MockVisualStyle: VisualStyleProviding {
    var toolbarButtonsCornerRadius: CGFloat = 0

    var fireWindowGraphic: NSImage = .fireHeader

    var areNavigationBarCornersRound: Bool = false

    var fireButtonSize: CGFloat = 0

    var navigationToolbarButtonsSpacing: CGFloat = 0

    var tabBarButtonSize: CGFloat = 0

    var addToolbarShadow: Bool = false

    let isNewStyle: Bool

    init(isNewStyle: Bool) {
        self.isNewStyle = isNewStyle
    }

    var addressBarStyleProvider: DuckDuckGo_Privacy_Browser.AddressBarStyleProviding {
        fatalError("Not implemented for test")
    }

    var colorsProvider: DuckDuckGo_Privacy_Browser.ColorsProviding {
        fatalError("Not implemented for test")
    }

    var iconsProvider: DuckDuckGo_Privacy_Browser.IconsProviding {
        fatalError("Not implemented for test")
    }

    var tabStyleProvider: any DuckDuckGo_Privacy_Browser.TabStyleProviding {
        fatalError("Not implemented for test")
    }

}
