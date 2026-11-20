//
//  SwipeTabsCoordinatorSnapshotTests.swift
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
@testable import Core
@testable import DuckDuckGo

@MainActor
final class SwipeTabsCoordinatorSnapshotTests: XCTestCase {

    private static let screenSize = CGSize(width: 390, height: 844)

    // The coordinator holds these weakly.
    private var mainViewCoordinator: MainViewCoordinator!
    private var previewsSource: MockTabPreviewsSource!
    private var tabsModel: TabsModel!
    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        mainViewCoordinator = nil
        previewsSource = nil
        tabsModel = nil
        super.tearDown()
    }

    func testWhenMainViewIsNotInAWindowThenNoSnapshotIsStored() {
        let (sut, tab) = makeSUT(inWindow: false)

        sut.updateFullScreenSnapshot(forTab: tab)

        XCTAssertTrue(previewsSource.updatedFullScreenSnapshots.isEmpty)
    }

    func testWhenMainViewIsHiddenThenNoSnapshotIsStored() {
        let (sut, tab) = makeSUT(inWindow: true)
        mainViewCoordinator.superview.isHidden = true

        sut.updateFullScreenSnapshot(forTab: tab)

        XCTAssertTrue(previewsSource.updatedFullScreenSnapshots.isEmpty)
    }

    func testWhenMainViewIsOnScreenThenAFullScreenSnapshotIsStored() {
        let (sut, tab) = makeSUT(inWindow: true)

        sut.updateFullScreenSnapshot(forTab: tab)

        XCTAssertEqual(previewsSource.updatedFullScreenSnapshots.count, 1)
        XCTAssertEqual(previewsSource.updatedFullScreenSnapshots.first?.size, Self.screenSize)
    }

    private func makeSUT(inWindow: Bool) -> (SwipeTabsCoordinator, Tab) {
        let parent = UIViewController()
        parent.view.frame = CGRect(origin: .zero, size: Self.screenSize)
        if inWindow {
            let window = UIWindow(frame: CGRect(origin: .zero, size: Self.screenSize))
            window.rootViewController = parent
            window.isHidden = false
            self.window = window
        }

        let coordinator = MainViewCoordinator(parentController: parent)
        mainViewCoordinator = coordinator
        coordinator.navigationBarCollectionView = MainViewFactory.NavigationBarCollectionView(
            frame: CGRect(x: 0, y: 0, width: Self.screenSize.width, height: DefaultOmniBarView.expectedHeight),
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        coordinator.omniBar = MockOmniBar()
        coordinator.toolbar = BrowserToolbarView(frame: .zero)

        previewsSource = MockTabPreviewsSource()
        let sut = SwipeTabsCoordinator(
            coordinator: coordinator,
            tabPreviewsSource: previewsSource,
            appSettings: AppSettingsMock(),
            omnibarDependencies: MockOmnibarDependency(),
            floatingUIManager: FloatingUIManager(
                isFloatingUIFeatureEnabled: false,
                isDuckAIAndInputLiquidGlassFeatureEnabled: false,
                isPadProvider: { false },
                isSupportedOSProvider: { true },
                unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: true)
            ),
            liveTabControllerProvider: { _ in nil },
            inputStateProvider: { _ in TabInputState() },
            placeholderStateProvider: { _ in .newChat },
            isPaidAIChatEnabledProvider: { false },
            allowsSubscriptionUpsellProvider: { false },
            pixelFiring: nil,
            selectTab: { _ in },
            newTab: {},
            onSwipeStarted: {}
        )
        let tab = Tab(link: Link(title: "Example", url: URL(string: "https://example.com")!))
        tabsModel = TabsModel(tabs: [tab], desktop: false)
        sut.tabsModel = tabsModel
        return (sut, tab)
    }
}
