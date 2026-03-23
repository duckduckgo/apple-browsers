//
//  QuitSurveyViewModelTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import History
import PixelKit
import PixelKitTestingUtilities
import XCTest
import PrivacyConfig

@testable import DuckDuckGo_Privacy_Browser

// MARK: - Helpers

private func makeEntry(host: String, lastVisit: Date) -> HistoryEntry {
    makeEntry(url: URL(string: "https://\(host)/")!, lastVisit: lastVisit)
}

private func makeEntry(url: URL, lastVisit: Date) -> HistoryEntry {
    HistoryEntry(
        identifier: UUID(),
        url: url,
        title: nil,
        failedToLoad: false,
        numberOfTotalVisits: 1,
        lastVisit: lastVisit,
        visits: [],
        numberOfTrackersBlocked: 0,
        blockedTrackingEntities: [],
        trackersFound: false,
        cookiePopupBlocked: false
    )
}

// MARK: - Helpers

private func makeFeatureFlagWithDomainSelector() -> MockFeatureFlagger {
    let flagger = MockFeatureFlagger()
    flagger.enabledFeatureFlags = [.websitesHistoryFirstTimeQuitSurvey]
    return flagger
}

@MainActor private func makeHistory(_ domains: [String]) -> HistoryCoordinatingMock {
    let mock = HistoryCoordinatingMock()
    mock.history = domains.enumerated().map { index, domain in
        makeEntry(host: domain, lastVisit: Date().addingTimeInterval(-Double(index)))
    }
    return mock
}

// MARK: - View Model Factory

@MainActor
private func makeViewModel(
    feedbackSender: FeedbackSenderImplementing = MockFeedbackSender(),
    featureFlagger: MockFeatureFlagger = MockFeatureFlagger(),
    pixelFiring: PixelFiring? = nil,
    historyCoordinating: HistoryCoordinatingMock? = nil,
    onQuit: @escaping () -> Void = {}
) -> QuitSurveyViewModel {
    QuitSurveyViewModel(
        feedbackSender: feedbackSender,
        persistor: nil,
        featureFlagger: featureFlagger,
        pixelFiring: pixelFiring,
        historyCoordinating: historyCoordinating,
        onQuit: onQuit
    )
}

// MARK: - Tests

@MainActor
final class QuitSurveyViewModelTests: XCTestCase {

    func testRecentDomainsIsEmptyIfFFisNotEnabledAndHistoryIsNotEmpty() {
        let now = Date()
        let historyCoordinating = HistoryCoordinatingMock()
        historyCoordinating.history = [
            makeEntry(host: "a.com", lastVisit: now.addingTimeInterval(-1)),
            makeEntry(host: "b.com", lastVisit: now.addingTimeInterval(-2)),
            makeEntry(host: "c.com", lastVisit: now.addingTimeInterval(-3)),
            makeEntry(host: "d.com", lastVisit: now.addingTimeInterval(-4)),
            makeEntry(host: "e.com", lastVisit: now.addingTimeInterval(-5)),
            makeEntry(host: "f.com", lastVisit: now.addingTimeInterval(-6)),
            makeEntry(host: "a.com", lastVisit: now.addingTimeInterval(-7)), // duplicate
        ]

        let viewModel = QuitSurveyViewModel(
            persistor: nil,
            featureFlagger: MockFeatureFlagger(),
            historyCoordinating: historyCoordinating,
            onQuit: {}
        )

        XCTAssertEqual(viewModel.recentDomains, [])
    }

    func testRecentDomainsReturnsLast5UniqueHostsSortedByMostRecent() {
        let now = Date()
        let historyCoordinating = HistoryCoordinatingMock()
        historyCoordinating.history = [
            makeEntry(host: "a.com", lastVisit: now.addingTimeInterval(-1)),
            makeEntry(host: "b.com", lastVisit: now.addingTimeInterval(-2)),
            makeEntry(host: "c.com", lastVisit: now.addingTimeInterval(-3)),
            makeEntry(host: "d.com", lastVisit: now.addingTimeInterval(-4)),
            makeEntry(host: "e.com", lastVisit: now.addingTimeInterval(-5)),
            makeEntry(host: "f.com", lastVisit: now.addingTimeInterval(-6)),
            makeEntry(host: "a.com", lastVisit: now.addingTimeInterval(-7)), // duplicate
        ]
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.websitesHistoryFirstTimeQuitSurvey]

        let viewModel = QuitSurveyViewModel(
            persistor: nil,
            featureFlagger: featureFlagger,
            historyCoordinating: historyCoordinating,
            onQuit: {}
        )

        XCTAssertEqual(viewModel.recentDomains.map(\.domain), ["a.com", "b.com", "c.com", "d.com", "e.com"])
    }

    func testRecentDomainsStripsQueryStringsFromHistoryURLs() {
        let historyCoordinating = HistoryCoordinatingMock()
        historyCoordinating.history = [
            makeEntry(url: URL(string: "https://example.com/page?user=secret&token=abc")!, lastVisit: Date()),
        ]
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.websitesHistoryFirstTimeQuitSurvey]

        let viewModel = QuitSurveyViewModel(
            persistor: nil,
            featureFlagger: featureFlagger,
            historyCoordinating: historyCoordinating,
            onQuit: {}
        )

        XCTAssertEqual(viewModel.recentDomains.map(\.domain), ["example.com"])
    }

    func testRecentDomainsStripsFragmentsFromHistoryURLs() {
        let historyCoordinating = HistoryCoordinatingMock()
        historyCoordinating.history = [
            makeEntry(url: URL(string: "https://example.com/page#section-with-id")!, lastVisit: Date()),
        ]
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.websitesHistoryFirstTimeQuitSurvey]

        let viewModel = QuitSurveyViewModel(
            persistor: nil,
            featureFlagger: featureFlagger,
            historyCoordinating: historyCoordinating,
            onQuit: {}
        )

        XCTAssertEqual(viewModel.recentDomains.map(\.domain), ["example.com"])
    }

    func testRecentDomainsDeduplicatesByHostAcrossDifferentPaths() {
        let now = Date()
        let historyCoordinating = HistoryCoordinatingMock()
        historyCoordinating.history = [
            makeEntry(url: URL(string: "https://example.com/page1?q=1")!, lastVisit: now.addingTimeInterval(-1)),
            makeEntry(url: URL(string: "https://example.com/page2?q=2")!, lastVisit: now.addingTimeInterval(-2)),
        ]
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.websitesHistoryFirstTimeQuitSurvey]

        let viewModel = QuitSurveyViewModel(
            persistor: nil,
            featureFlagger: featureFlagger,
            historyCoordinating: historyCoordinating,
            onQuit: {}
        )

        XCTAssertEqual(viewModel.recentDomains.map(\.domain), ["example.com"])
    }

    func testRecentDomainsIsEmptyWhenNoHistory() {
        let viewModel = QuitSurveyViewModel(
            persistor: nil,
            featureFlagger: MockFeatureFlagger(),
            historyCoordinating: nil,
            onQuit: {}
        )

        XCTAssertTrue(viewModel.recentDomains.isEmpty)
    }

    func testToggleDomainAddsAndRemovesDomain() {
        let viewModel = QuitSurveyViewModel(
            persistor: nil,
            featureFlagger: MockFeatureFlagger(),
            historyCoordinating: makeHistory(["example.com"]),
            onQuit: {}
        )

        viewModel.toggleDomain("example.com")
        XCTAssertTrue(viewModel.selectedDomains.contains("example.com"))

        viewModel.toggleDomain("example.com")
        XCTAssertFalse(viewModel.selectedDomains.contains("example.com"))
    }

    func testShouldShowDomainSelectorWhenWebsitesPillSelectedAndHistoryNonEmpty() {
        let historyCoordinating = HistoryCoordinatingMock()
        historyCoordinating.history = [
            makeEntry(host: "example.com", lastVisit: Date()),
        ]
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.websitesHistoryFirstTimeQuitSurvey]

        let viewModel = QuitSurveyViewModel(
            persistor: nil,
            featureFlagger: featureFlagger,
            historyCoordinating: historyCoordinating,
            onQuit: {}
        )

        XCTAssertFalse(viewModel.shouldShowDomainSelector)

        viewModel.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId)
        XCTAssertTrue(viewModel.shouldShowDomainSelector)
    }

    func testShouldShowDomainSelectorWhenPagesFrozePillSelectedAndHistoryNonEmpty() {
        let historyCoordinating = HistoryCoordinatingMock()
        historyCoordinating.history = [
            makeEntry(host: "example.com", lastVisit: Date()),
        ]
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.websitesHistoryFirstTimeQuitSurvey]

        let viewModel = QuitSurveyViewModel(
            persistor: nil,
            featureFlagger: featureFlagger,
            historyCoordinating: historyCoordinating,
            onQuit: {}
        )

        XCTAssertFalse(viewModel.shouldShowDomainSelector)

        viewModel.toggleOption("pages-froze")
        XCTAssertTrue(viewModel.shouldShowDomainSelector)
    }

    func testShouldShowDomainSelectorWhenPagesLoadedSlowlyPillSelectedAndHistoryNonEmpty() {
        let historyCoordinating = HistoryCoordinatingMock()
        historyCoordinating.history = [
            makeEntry(host: "example.com", lastVisit: Date()),
        ]
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.websitesHistoryFirstTimeQuitSurvey]

        let viewModel = QuitSurveyViewModel(
            persistor: nil,
            featureFlagger: featureFlagger,
            historyCoordinating: historyCoordinating,
            onQuit: {}
        )

        XCTAssertFalse(viewModel.shouldShowDomainSelector)

        viewModel.toggleOption("pages-loaded-slowly")
        XCTAssertTrue(viewModel.shouldShowDomainSelector)
    }

    func testShouldNotShowDomainSelectorWhenFeatureFlagIsOff() {
        let historyCoordinating = HistoryCoordinatingMock()
        historyCoordinating.history = [
            makeEntry(host: "example.com", lastVisit: Date()),
        ]

        let viewModel = QuitSurveyViewModel(
            persistor: nil,
            featureFlagger: MockFeatureFlagger(),
            historyCoordinating: historyCoordinating,
            onQuit: {}
        )

        viewModel.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId)
        XCTAssertFalse(viewModel.shouldShowDomainSelector)
    }

    func testSubmitFeedbackIncludesDomainsInFeedbackText() {
        let historyCoordinating = HistoryCoordinatingMock()
        historyCoordinating.history = [
            makeEntry(host: "a.com", lastVisit: Date()),
        ]
        let sender = MockFeedbackSender()
        let vm = QuitSurveyViewModel(feedbackSender: sender, featureFlagger: MockFeatureFlagger(), historyCoordinating: historyCoordinating, onQuit: {})
        vm.selectNegativeResponse()
        vm.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId)
        vm.toggleDomain("a.com")
        vm.submitFeedback()
        XCTAssertTrue(sender.lastFeedback?.comment.contains("a.com") == true)
    }

    func testSubmitFeedbackIncludesOtherDomainTextWhenSelectedAndFilled() {
        let sender = MockFeedbackSender()
        let vm = QuitSurveyViewModel(feedbackSender: sender, featureFlagger: MockFeatureFlagger(), onQuit: {})
        vm.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId)
        vm.toggleOtherDomain()
        vm.otherDomainText = "custom.example.com"
        vm.submitFeedback()
        XCTAssertTrue(sender.lastFeedback?.comment.contains("custom.example.com") == true)
    }

    func testSubmitFeedbackExcludesOtherDomainTextWhenNotSelected() {
        let sender = MockFeedbackSender()
        let vm = QuitSurveyViewModel(feedbackSender: sender, featureFlagger: MockFeatureFlagger(), onQuit: {})
        vm.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId)
        vm.otherDomainText = "custom.example.com" // set text without toggling the checkbox
        vm.submitFeedback()
        XCTAssertFalse(sender.lastFeedback?.comment.contains("custom.example.com") == true)
    }

    func testSubmitFeedbackExcludesOtherDomainTextWhenWhitespaceOnly() {
        let sender = MockFeedbackSender()
        let vm = QuitSurveyViewModel(feedbackSender: sender, featureFlagger: MockFeatureFlagger(), onQuit: {})
        vm.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId)
        vm.toggleOtherDomain()
        vm.otherDomainText = "   "
        vm.submitFeedback()
        XCTAssertFalse(sender.lastFeedback?.comment.contains("Affected domains") == true)
    }

    func testToggleOtherDomainClearsTextOnDeselect() {
        let vm = QuitSurveyViewModel(featureFlagger: MockFeatureFlagger(), onQuit: {})
        vm.toggleOtherDomain()
        vm.otherDomainText = "custom.example.com"
        vm.toggleOtherDomain() // deselect
        XCTAssertTrue(vm.otherDomainText.isEmpty)
    }

    // MARK: - Bug fixes

    func testDeselectingWebsitesPillClearsDomainState() {
        let sender = MockFeedbackSender()
        let vm = QuitSurveyViewModel(feedbackSender: sender, featureFlagger: makeFeatureFlagWithDomainSelector(),
                                     historyCoordinating: makeHistory(["example.com"]), onQuit: {})
        vm.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId)
        vm.toggleDomain("example.com")
        vm.toggleOtherDomain()
        vm.otherDomainText = "other.com"

        vm.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId) // deselect the pill

        XCTAssertTrue(vm.selectedDomains.isEmpty)
        XCTAssertFalse(vm.isOtherDomainSelected)
        XCTAssertTrue(vm.otherDomainText.isEmpty)
    }

    func testDeselectingPagesFrozePillClearsDomainStateWhenItIsLastTrigger() {
        let vm = QuitSurveyViewModel(featureFlagger: makeFeatureFlagWithDomainSelector(),
                                     historyCoordinating: makeHistory(["example.com"]), onQuit: {})
        vm.toggleOption("pages-froze")
        vm.toggleDomain("example.com")
        vm.toggleOtherDomain()
        vm.otherDomainText = "other.com"

        vm.toggleOption("pages-froze") // deselect — no other triggers selected

        XCTAssertTrue(vm.selectedDomains.isEmpty)
        XCTAssertFalse(vm.isOtherDomainSelected)
        XCTAssertTrue(vm.otherDomainText.isEmpty)
    }

    func testDeselectingPagesLoadedSlowlyPillClearsDomainStateWhenItIsLastTrigger() {
        let vm = QuitSurveyViewModel(featureFlagger: makeFeatureFlagWithDomainSelector(),
                                     historyCoordinating: makeHistory(["example.com"]), onQuit: {})
        vm.toggleOption("pages-loaded-slowly")
        vm.toggleDomain("example.com")
        vm.toggleOtherDomain()
        vm.otherDomainText = "other.com"

        vm.toggleOption("pages-loaded-slowly") // deselect — no other triggers selected

        XCTAssertTrue(vm.selectedDomains.isEmpty)
        XCTAssertFalse(vm.isOtherDomainSelected)
        XCTAssertTrue(vm.otherDomainText.isEmpty)
    }

    func testDeselectingOneTriggerKeepsDomainStateWhenAnotherTriggerIsStillSelected() {
        let vm = QuitSurveyViewModel(featureFlagger: makeFeatureFlagWithDomainSelector(),
                                     historyCoordinating: makeHistory(["example.com"]), onQuit: {})
        vm.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId)
        vm.toggleOption("pages-froze")
        vm.toggleDomain("example.com")

        vm.toggleOption("pages-froze") // deselect — websites-didnt-work is still selected

        XCTAssertTrue(vm.selectedDomains.contains("example.com"))
    }

    func testDeselectingLastTriggerClearsDomainStateEvenWithOtherNonTriggerPillsSelected() {
        let vm = QuitSurveyViewModel(featureFlagger: makeFeatureFlagWithDomainSelector(),
                                     historyCoordinating: makeHistory(["example.com"]), onQuit: {})
        vm.toggleOption("pages-froze")
        vm.toggleOption("slow-to-open") // non-trigger pill
        vm.toggleDomain("example.com")

        vm.toggleOption("pages-froze") // deselect last trigger

        XCTAssertTrue(vm.selectedDomains.isEmpty)
    }

    func testDeselectingWebsitesPillMeansDomainsNotSubmitted() {
        let sender = MockFeedbackSender()
        let vm = QuitSurveyViewModel(feedbackSender: sender, featureFlagger: makeFeatureFlagWithDomainSelector(),
                                     historyCoordinating: makeHistory(["example.com"]), onQuit: {})
        vm.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId)
        vm.toggleDomain("example.com")
        vm.toggleOtherDomain()
        vm.otherDomainText = "other.com"

        vm.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId) // deselect the pill
        vm.toggleOption("slow-to-open") // select a different pill so submit is enabled
        vm.submitFeedback()

        XCTAssertFalse(sender.lastFeedback?.comment.contains("example.com") == true)
        XCTAssertFalse(sender.lastFeedback?.comment.contains("other.com") == true)
    }

    func testGoBackClearsDomainState() {
        let vm = QuitSurveyViewModel(featureFlagger: MockFeatureFlagger(),
                                     historyCoordinating: makeHistory(["example.com"]), onQuit: {})
        vm.selectNegativeResponse()
        vm.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId)
        vm.toggleDomain("example.com")
        vm.toggleOtherDomain()
        vm.otherDomainText = "other.com"

        vm.goBack()

        XCTAssertTrue(vm.selectedDomains.isEmpty)
        XCTAssertFalse(vm.isOtherDomainSelected)
        XCTAssertTrue(vm.otherDomainText.isEmpty)
    }

    // MARK: - Pixels

    func testSubmitFeedbackFiresPixelWithAffectedDomainsParameter() {
        let pixelMock = PixelKitMock(expecting: [])
        let sender = MockFeedbackSender()
        let vm = makeViewModel(feedbackSender: sender, pixelFiring: pixelMock, historyCoordinating: makeHistory(["example.com"]))
        vm.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId)
        vm.toggleDomain("example.com")
        vm.submitFeedback()

        let submissionCall = pixelMock.actualFireCalls.first {
            $0.pixel.name == QuitSurveyPixelName.quitSurveyThumbsDownSubmission.rawValue
        }
        XCTAssertNotNil(submissionCall)
        XCTAssertEqual(submissionCall?.pixel.parameters?["affected_domains"], "example.com")
    }

    func testSubmitFeedbackStripsQueryStringFromOtherDomainText() {
        let sender = MockFeedbackSender()
        let vm = QuitSurveyViewModel(feedbackSender: sender, featureFlagger: MockFeatureFlagger(), onQuit: {})
        vm.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId)
        vm.toggleOtherDomain()
        vm.otherDomainText = "example.com/path?user=secret&token=abc"
        vm.submitFeedback()
        XCTAssertFalse(sender.lastFeedback?.comment.contains("user=secret") == true)
        XCTAssertFalse(sender.lastFeedback?.comment.contains("token=abc") == true)
        XCTAssertTrue(sender.lastFeedback?.comment.contains("example.com") == true)
    }

    func testSubmitFeedbackStripsFragmentFromOtherDomainText() {
        let sender = MockFeedbackSender()
        let vm = QuitSurveyViewModel(feedbackSender: sender, featureFlagger: MockFeatureFlagger(), onQuit: {})
        vm.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId)
        vm.toggleOtherDomain()
        vm.otherDomainText = "example.com/page#section-with-id"
        vm.submitFeedback()
        XCTAssertFalse(sender.lastFeedback?.comment.contains("section-with-id") == true)
        XCTAssertTrue(sender.lastFeedback?.comment.contains("example.com") == true)
    }

    func testSubmitFeedbackStripsCommasFromOtherDomainTextInPixel() {
        let pixelMock = PixelKitMock(expecting: [])
        let sender = MockFeedbackSender()
        let vm = makeViewModel(feedbackSender: sender, pixelFiring: pixelMock)
        vm.toggleOption(QuitSurveyViewModel.websitesDidntWorkOptionId)
        vm.toggleOtherDomain()
        vm.otherDomainText = "a.com,b.com"
        vm.submitFeedback()

        let submissionCall = pixelMock.actualFireCalls.first {
            $0.pixel.name == QuitSurveyPixelName.quitSurveyThumbsDownSubmission.rawValue
        }
        let affectedDomains = submissionCall?.pixel.parameters?["affected_domains"]
        XCTAssertNotNil(affectedDomains)
        XCTAssertFalse(affectedDomains?.contains(",") == true, "Commas in other domain text must not corrupt the pixel separator")
    }

    func testSubmitFeedbackDoesNotIncludeAffectedDomainsParameterWhenNoneSelected() {
        let pixelMock = PixelKitMock(expecting: [])
        let sender = MockFeedbackSender()
        let vm = makeViewModel(feedbackSender: sender, pixelFiring: pixelMock)
        vm.toggleOption("slow-to-open")
        vm.submitFeedback()

        let submissionCall = pixelMock.actualFireCalls.first {
            $0.pixel.name == QuitSurveyPixelName.quitSurveyThumbsDownSubmission.rawValue
        }
        XCTAssertNotNil(submissionCall)
        XCTAssertNil(submissionCall?.pixel.parameters?["affected_domains"])
    }
}
