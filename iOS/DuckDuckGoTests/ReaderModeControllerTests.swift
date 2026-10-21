//
//  ReaderModeControllerTests.swift
//  DuckDuckGoTests
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

import Core
import FeatureFlags_iOS
import ReaderMode
import Testing
import WebKit
@testable import DuckDuckGo

@MainActor
struct ReaderModeControllerTests {
    private let url = URL(string: "https://example.com/article")!

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func flagOffDoesNoSnapshotAndRuntimeChangesClearActiveReader() async throws {
        let article = try await makeArticle()
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        var captures = 0
        let controller = ReaderModeController(featureFlagger: flagger, capture: { _ in
            captures += 1
            return .init(url: url, html: "article")
        }, extract: { _, _ in article })
        let webView = ReaderTestWebView(url: url)
        controller.attach(webView: webView)
        controller.isVisible = true
        await settle()
        #expect(captures == 0)
        #expect(!controller.state.isAvailable)

        flagger.enabledFeatureFlags = [.readerMode]
        flagger.triggerUpdate()
        try await waitUntil { controller.state.isAvailable }
        #expect(captures == 1)
        controller.setActive(true)
        #expect(controller.state.isActive)
        controller.navigationStarted()
        controller.setActive(false)
        #expect(!controller.state.isActive)
        controller.navigationFinished()
        controller.setActive(true)
        flagger.enabledFeatureFlags = []
        flagger.triggerUpdate()
        try await waitUntil { !controller.state.isAvailable }
        controller.sampleIfNeeded()
        await settle()
        #expect(captures == 1)

        flagger.enabledFeatureFlags = [.readerMode]
        flagger.triggerUpdate()
        try await waitUntil { controller.state.isAvailable }
        #expect(captures == 2)
        #expect(!controller.state.isActive)
        controller.detach()
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func queuedSnapshotIsSuppressedWhenFlagTurnsOff() async throws {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.readerMode])
        var captures = 0
        let controller = ReaderModeController(featureFlagger: flagger, capture: { _ in
            captures += 1
            return nil
        })
        let webView = ReaderTestWebView(url: url)
        controller.attach(webView: webView)
        controller.isVisible = true
        flagger.enabledFeatureFlags = []
        flagger.triggerUpdate()
        await settle()
        #expect(captures == 0)
        #expect(!controller.state.isAvailable)
        controller.detach()
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func staleExtractionCannotOfferAfterSameURLReloadOrFlagDisable() async throws {
        let article = try await makeArticle()
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.readerMode])
        var pending: CheckedContinuation<ReaderArticle?, Error>?
        let controller = ReaderModeController(featureFlagger: flagger, capture: { _ in
            .init(url: url, html: "article")
        }, extract: { _, _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        })
        let webView = ReaderTestWebView(url: url)
        controller.attach(webView: webView)
        controller.isVisible = true
        try await waitUntil { pending != nil }
        controller.navigationStarted()
        controller.pageChanged()
        pending?.resume(returning: article)
        pending = nil
        await settle()
        #expect(!controller.state.isAvailable)

        controller.sampleIfNeeded()
        try await waitUntil { pending != nil }
        flagger.enabledFeatureFlags = []
        flagger.triggerUpdate()
        pending?.resume(returning: article)
        pending = nil
        await settle()
        #expect(!controller.state.isAvailable)
        controller.detach()
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func replacementBeforeTaskStartsDoesNotCaptureOldWebViewOrBlockNewOne() async throws {
        let article = try await makeArticle()
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.readerMode])
        var captures: [WKWebView] = []
        let controller = ReaderModeController(featureFlagger: flagger, capture: { webView in
            captures.append(webView)
            return .init(url: url, html: "article")
        }, extract: { _, _ in article })
        var old: WKWebView? = ReaderTestWebView(url: url)
        controller.attach(webView: try #require(old))
        controller.isVisible = true
        let replacement = ReaderTestWebView(url: url)
        controller.attach(webView: replacement)
        old = nil
        await settle()
        controller.sampleIfNeeded()
        try await waitUntil { controller.state.isAvailable }
        #expect(captures.count == 1)
        #expect(captures.first === replacement)
        controller.detach()
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func hiddenBackgroundOfferedAndActiveTabsStopSampling() async throws {
        let article = try await makeArticle()
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.readerMode])
        var captures = 0
        var extractions = 0
        let controller = ReaderModeController(featureFlagger: flagger, capture: { _ in
            captures += 1
            return .init(url: url, html: "article")
        }, extract: { _, _ in
            extractions += 1
            return article
        })
        let webView = ReaderTestWebView(url: url)
        controller.attach(webView: webView)
        await settle()
        #expect(captures == 0)
        controller.setForeground(false)
        controller.isVisible = true
        await settle()
        #expect(captures == 0)
        controller.setForeground(true)
        try await waitUntil { controller.state.isAvailable }
        controller.sampleIfNeeded()
        await settle()
        #expect(captures == 1)
        #expect(extractions == 1)
        controller.setActive(true)
        controller.sampleIfNeeded()
        await settle()
        #expect(captures == 1)
        controller.setActive(false)
        await settle()
        #expect(controller.state.isAvailable)
        #expect(captures == 1)
        #expect(extractions == 1)
        controller.detach()
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func unchangedSnapshotSkipsExtractionWhenNoArticleWasFound() async throws {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.readerMode])
        var captures = 0
        var extractions = 0
        let controller = ReaderModeController(featureFlagger: flagger, capture: { _ in
            captures += 1
            return .init(url: url, html: "navigation")
        }, extract: { _, _ in
            extractions += 1
            return nil
        })
        let webView = ReaderTestWebView(url: url)
        controller.attach(webView: webView)
        controller.isVisible = true
        try await waitUntil { extractions == 1 }
        await settle()
        controller.sampleIfNeeded()
        try await waitUntil { captures == 2 }
        await settle()
        #expect(!controller.state.isAvailable)
        #expect(extractions == 1)
        controller.detach()
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func tabsAreIndependentAndSPARoutesAndTerminationClearState() async throws {
        let article = try await makeArticle()
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.readerMode])
        let capture: (WKWebView) async throws -> ReaderModeController.Snapshot? = { webView in
            .init(url: webView.url!, html: "article")
        }
        let first = ReaderModeController(featureFlagger: flagger, capture: capture, extract: { _, _ in article })
        let second = ReaderModeController(featureFlagger: flagger, capture: capture, extract: { _, _ in article })
        let firstPage = ReaderTestWebView(url: url)
        let secondPage = ReaderTestWebView(url: url)
        first.attach(webView: firstPage)
        second.attach(webView: secondPage)
        first.isVisible = true
        second.isVisible = true
        try await waitUntil { first.state.isAvailable && second.state.isAvailable }
        first.setActive(true)
        #expect(first.state.isActive)
        #expect(!second.state.isActive)
        firstPage.simulatedURL = URL(string: "https://example.com/article#section")!
        first.urlChanged()
        #expect(first.state.isActive)
        firstPage.simulatedURL = URL(string: "https://example.com/next")!
        first.urlChanged()
        #expect(!first.state.isAvailable)
        #expect(second.state.isAvailable)
        second.processTerminated()
        #expect(!second.state.isAvailable)
        first.detach()
        second.detach()
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func staleSnapshotNeverStartsExtractionAndProvisionalFailureRetriesOriginalPage() async throws {
        let article = try await makeArticle()
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.readerMode])
        var pending: CheckedContinuation<ReaderModeController.Snapshot?, Error>?
        var extractions = 0
        let controller = ReaderModeController(featureFlagger: flagger, capture: { _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        }, extract: { _, _ in
            extractions += 1
            return article
        })
        let webView = ReaderTestWebView(url: url)
        controller.attach(webView: webView)
        controller.isVisible = true
        try await waitUntil { pending != nil }
        controller.navigationStarted()
        pending?.resume(returning: .init(url: url, html: "old"))
        pending = nil
        await settle()
        #expect(extractions == 0)
        #expect(!controller.state.isAvailable)

        // A failed provisional navigation leaves the previous page in WebKit.
        controller.navigationFinished()
        try await waitUntil { pending != nil }
        pending?.resume(returning: .init(url: url, html: "preserved"))
        pending = nil
        try await waitUntil { controller.state.isAvailable }
        #expect(extractions == 1)
        controller.detach()
    }

    private func makeArticle() async throws -> ReaderArticle {
        let paragraph = "<p>This report describes a journey across the mountains and through the forests. The walkers followed a river to a quiet valley and stopped to study the birds and trees along the trail.</p>"
        let paragraphs = (1...8).map { paragraph.replacingOccurrences(of: "This report", with: "Stage \($0). This report") }.joined()
        let html = "<html><head><title>Journey</title></head><body><article>" + paragraphs + "</article></body></html>"
        return try #require(ReaderModeExtractor().article(fromHTML: html, url: url))
    }

    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<500 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(predicate())
    }
}

@MainActor
private final class ReaderTestWebView: WKWebView {
    var simulatedURL: URL
    override var url: URL? { simulatedURL }
    override var isLoading: Bool { false }

    init(url: URL) {
        simulatedURL = url
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
