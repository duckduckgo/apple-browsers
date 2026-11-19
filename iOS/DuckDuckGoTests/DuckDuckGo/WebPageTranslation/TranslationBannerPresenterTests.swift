//
//  TranslationBannerPresenterTests.swift
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

import UIKit
import WebPageTranslation
import XCTest
@testable import DuckDuckGo

@MainActor
final class TranslationBannerPresenterTests: XCTestCase {

    private let offer = TranslationOffer(source: "es", target: "en")
    private var host: UIViewController!
    private let addressBar = UIView()

    override func setUp() async throws {
        host = UIViewController()
        host.loadViewIfNeeded()
        host.view.addSubview(addressBar)
    }

    func testPresentAddsBanner() {
        let presenter = makePresenter()
        presenter.present(offer, in: host, nextTo: addressBar)
        XCTAssertTrue(presenter.isPresented)
    }

    func testAutoDismissesAfterDelay() async throws {
        let presenter = makePresenter(autoDismissDelay: 0.1, isVoiceOverRunning: false)
        presenter.present(offer, in: host, nextTo: addressBar)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(presenter.isPresented)
    }

    func testDoesNotAutoDismissWithVoiceOver() async throws {
        let presenter = makePresenter(autoDismissDelay: 0.1, isVoiceOverRunning: true)
        presenter.present(offer, in: host, nextTo: addressBar)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(presenter.isPresented)
    }

    func testDismissRemovesBanner() {
        let presenter = makePresenter()
        presenter.present(offer, in: host, nextTo: addressBar)
        presenter.dismiss(animated: false)
        XCTAssertFalse(presenter.isPresented)
    }

    private func makePresenter(autoDismissDelay: TimeInterval = 5, isVoiceOverRunning: Bool = false) -> TranslationBannerPresenter {
        TranslationBannerPresenter(appSettings: AppSettingsMock(),
                                   autoDismissDelay: autoDismissDelay,
                                   isVoiceOverRunning: { isVoiceOverRunning })
    }
}
