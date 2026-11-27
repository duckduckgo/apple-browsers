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

import Foundation
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
@Suite("Translate offer in the browser tool prompt presenter")
struct TranslateOfferPresenterTests {

    private let collection: TabCollectionViewModel
    private let presenter: BrowserToolPermissionPromptPresenter

    init() {
        collection = Self.collection(urls: ["https://a.example", "https://b.example"])
        presenter = Self.presenter(collections: [collection])
    }

    private static func collection(urls: [String], burnerMode: BurnerMode = .regular) -> TabCollectionViewModel {
        let tabs: [AnyTab] = urls.map { .loaded(Tab(content: .url(URL(string: $0)!, credential: nil, source: .ui), burnerMode: burnerMode)) }
        return TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs), pinnedTabsManagerProvider: nil, burnerMode: burnerMode)
    }

    private static func presenter(collections: [TabCollectionViewModel]) -> BrowserToolPermissionPromptPresenter {
        let manager = WindowControllersManagerMock()
        manager.customAllTabCollectionViewModels = collections
        return BrowserToolPermissionPromptPresenter(windowControllersManager: manager) { _, _, _ in }
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
