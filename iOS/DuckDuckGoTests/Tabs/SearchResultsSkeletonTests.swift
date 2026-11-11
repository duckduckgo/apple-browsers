//
//  SearchResultsSkeletonTests.swift
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

import Testing
import UIKit
import FeatureFlags_iOS
import PrivacyConfig
@testable import DuckDuckGo

@MainActor
struct SearchResultsSkeletonTests {

    private static func makeHeader(width: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: SearchResultsSkeletonView.Constants.headerHeight)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("The outline's column follows the results page's margins at each page width",
          .timeLimit(.minutes(1)),
          arguments: [
            (402.0, 17.0, 368.0),   // phone, portrait
            (590.0, 17.0, 556.0),   // widest edge-to-edge page
            (600.0, 74.0, 496.0),   // narrowest indented page
            (750.0, 74.0, 646.0),   // phone, landscape, inside the safe area
            (832.0, 74.0, 652.0),   // larger phone, landscape: column capped
            (1032.0, 74.0, 652.0),  // 13" iPad, portrait
            (1210.0, 110.0, 652.0)  // 11" iPad, landscape
          ])
    func contentColumnMatchesPage(pageWidth: Double, x: Double, width: Double) {
        let column = SearchResultsSkeletonView.contentColumn(pageWidth: CGFloat(pageWidth))

        #expect(Double(column.x) == x)
        #expect(Double(column.width) == width)
    }

    @available(iOS 16, macOS 13, *)
    @Test("In landscape the outline starts inside the safe area, where the page's content does", .timeLimit(.minutes(1)))
    func landscapeOutlineStartsAtContent() {
        let path = SearchResultsSkeletonView.path(width: 874, height: 402, contentTop: 48, scale: 3, pageInsets: (62, 62), includesHeader: false)

        let bounds = path.boundingBoxOfPath
        let contentX: CGFloat = 62 + 74
        #expect(bounds.minX == contentX)
        #expect(bounds.maxX <= 874 - 62)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the real header on the cover, the outline starts at the first result", .timeLimit(.minutes(1)))
    func outlineWithoutHeaderStartsAtResults() {
        let withHeader = SearchResultsSkeletonView.path(width: 402, height: 800, contentTop: 120, scale: 3)
        let withoutHeader = SearchResultsSkeletonView.path(width: 402, height: 800, contentTop: 120, scale: 3, includesHeader: false)

        #expect(withHeader.boundingBoxOfPath.minY < 120 + SearchResultsSkeletonView.Constants.headerHeight)
        #expect(withoutHeader.boundingBoxOfPath.minY == 120 + SearchResultsSkeletonView.Constants.resultsTop)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The outline stays solid down to the first result, then fades to the bottom edge", .timeLimit(.minutes(1)))
    func fadeStartsAtFirstResult() {
        let locations = SearchResultsSkeletonView.fadeLocations(height: 800, contentTop: 106).map(\.doubleValue)

        #expect(locations == [0, 0.25, 1])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A header is shown only at the width it was captured at", .timeLimit(.minutes(1)))
    func headerImageNeedsMatchingWidth() throws {
        let skeleton = SearchResultsSkeletonView(frame: CGRect(x: 0, y: 0, width: 402, height: 800))
        let headerView = try #require(skeleton.subviews.first as? UIImageView)

        skeleton.headerImage = Self.makeHeader(width: 402)
        skeleton.layoutIfNeeded()
        #expect(!headerView.isHidden)

        skeleton.frame.size.width = 874
        skeleton.layoutIfNeeded()
        #expect(headerView.isHidden)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The header sits over the web view when it is narrower than the cover", .timeLimit(.minutes(1)))
    func headerFollowsPageView() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        let webView = UIView(frame: CGRect(x: 62, y: 0, width: 750, height: 402))
        let skeleton = SearchResultsSkeletonView(frame: container.bounds)
        container.addSubview(webView)
        container.addSubview(skeleton)
        let headerView = try #require(skeleton.subviews.first as? UIImageView)

        skeleton.pageView = webView
        skeleton.contentTop = 48
        skeleton.headerImage = Self.makeHeader(width: 750)
        skeleton.layoutIfNeeded()

        #expect(!headerView.isHidden)
        #expect(headerView.frame == CGRect(x: 62, y: 48, width: 750, height: SearchResultsSkeletonView.Constants.headerHeight))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A remembered header is offered for its own appearance and width only", .timeLimit(.minutes(1)))
    func memoryMatchesAppearanceAndWidth() {
        let memory = SearchPageHeaderMemory()
        let header = Self.makeHeader(width: 402)
        #expect(memory.header(for: .light, width: 402) == nil)

        memory.record(header, for: .light)

        #expect(memory.header(for: .light, width: 402) === header)
        #expect(memory.header(for: .dark, width: 402) == nil)
        #expect(memory.header(for: .light, width: 874) == nil)
    }

    private static let search = URL(string: "https://duckduckgo.com/?q=pizza")!

    @available(iOS 16, macOS 13, *)
    @Test("The outline flag is on for internal users only until the remote configuration says otherwise", .timeLimit(.minutes(1)))
    func skeletonFlagDefaultsToInternalOnly() {
        guard case .internalOnly = FeatureFlag.searchSubmitPageSkeleton.defaultValue else {
            Issue.record("searchSubmitPageSkeleton must default to internal only")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the outline flag off, a search keeps the plain cover and teaches no header",
          .timeLimit(.minutes(1)),
          arguments: [[FeatureFlag](), [.searchSubmitPageCover], [.searchSubmitPageSkeleton]])
    func skeletonOffWithoutBothFlags(enabled: [FeatureFlag]) {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: enabled)

        #expect(!MainViewController.showsSearchResultsSkeleton(for: Self.search, featureFlagger: flagger))
        #expect(!MainViewController.learnsSearchPageHeader(from: Self.search, featureFlagger: flagger))
    }

    @available(iOS 16, macOS 13, *)
    @Test("With both flags on, a search shows the outline and teaches the header; a website does neither", .timeLimit(.minutes(1)))
    func skeletonOnWithBothFlags() throws {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.searchSubmitPageCover, .searchSubmitPageSkeleton])
        let website = try #require(URL(string: "https://example.com"))

        #expect(MainViewController.showsSearchResultsSkeleton(for: Self.search, featureFlagger: flagger))
        #expect(MainViewController.learnsSearchPageHeader(from: Self.search, featureFlagger: flagger))
        #expect(!MainViewController.showsSearchResultsSkeleton(for: website, featureFlagger: flagger))
        #expect(!MainViewController.learnsSearchPageHeader(from: website, featureFlagger: flagger))
    }

    @available(iOS 16, macOS 13, *)
    @Test("The outline flag changing while the app runs applies to the next search", .timeLimit(.minutes(1)))
    func skeletonFollowsFlagChanges() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.searchSubmitPageCover])
        #expect(!MainViewController.showsSearchResultsSkeleton(for: Self.search, featureFlagger: flagger))

        flagger.enabledFeatureFlags.append(.searchSubmitPageSkeleton)
        #expect(MainViewController.showsSearchResultsSkeleton(for: Self.search, featureFlagger: flagger))

        flagger.enabledFeatureFlags = [.searchSubmitPageCover]
        #expect(!MainViewController.showsSearchResultsSkeleton(for: Self.search, featureFlagger: flagger))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Only the All results page teaches the header",
          .timeLimit(.minutes(1)),
          arguments: [
            ("https://duckduckgo.com/?q=pizza", true),
            ("https://duckduckgo.com/?q=pizza&ia=web", true),
            ("https://duckduckgo.com/?q=pizza&ia=images&iax=images", false),
            ("https://duckduckgo.com/?q=pizza&ia=news", false),
            ("https://duckduckgo.com/?q=pizza&ia=web&iaxm=maps", false)
          ])
    func headerLearnedFromAllResultsOnly(url: String, expected: Bool) throws {
        #expect(MainViewController.isAllResultsPage(try #require(URL(string: url))) == expected)
    }
}
