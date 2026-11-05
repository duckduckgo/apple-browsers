//
//  DelegateSessionFindInPage.swift
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
import WebKit

@available(iOS 16.0, *)
protocol DelegateFindSession: AnyObject {
    var resultCount: Int { get }
    var highlightedResultIndex: Int { get }
    var isNativeUIVisible: Bool { get }
    func search(_ query: String)
    func highlight(_ direction: UITextStorageDirection)
    func invalidate()
    func end()
}

@available(iOS 16.0, *)
final class WebKitDelegateFindSession: DelegateFindSession {
    enum Failure: String, Error {
        case interactionUnavailable = "Find interaction unavailable"
        case delegateUnavailable = "WebKit delegate unavailable"
        case sessionUnavailable = "WebKit returned no session"
        case nativeNavigatorVisible = "Native navigator already visible"
    }

    private weak var webView: WKWebView?
    private let interaction: UIFindInteraction
    private let sessionDelegate: any UIFindInteractionDelegate
    private let session: UIFindSession
    private let wasFindInteractionEnabled: Bool
    private var ended = false

    init(webView: WKWebView) throws {
        let wasEnabled = webView.isFindInteractionEnabled
        webView.isFindInteractionEnabled = true
        do {
            guard let interaction = webView.findInteraction else { throw Failure.interactionUnavailable }
            guard !interaction.isFindNavigatorVisible else { throw Failure.nativeNavigatorVisible }
            guard let delegate = interaction.delegate else { throw Failure.delegateUnavailable }
            guard let session = delegate.findInteraction(interaction, sessionFor: webView) else { throw Failure.sessionUnavailable }
            self.webView = webView
            self.interaction = interaction
            self.sessionDelegate = delegate
            self.session = session
            self.wasFindInteractionEnabled = wasEnabled
            // Public calls; manually owning WebKit's session lifecycle is unconfirmed.
            delegate.findInteraction?(interaction, didBegin: session)
        } catch {
            webView.isFindInteractionEnabled = wasEnabled
            throw error
        }
    }

    var resultCount: Int { session.resultCount }
    var highlightedResultIndex: Int { session.highlightedResultIndex }
    var isNativeUIVisible: Bool { interaction.isFindNavigatorVisible }

    func search(_ query: String) { session.performSearch(query: query, options: nil) }
    func highlight(_ direction: UITextStorageDirection) { session.highlightNextResult(in: direction) }
    func invalidate() { session.invalidateFoundResults() }

    func end() {
        guard !ended else { return }
        ended = true
        session.invalidateFoundResults()
        sessionDelegate.findInteraction?(interaction, didEnd: session)
        webView?.isFindInteractionEnabled = wasFindInteractionEnabled
    }

    deinit { end() }
}

@available(iOS 16.0, *)
final class DelegateSessionFindInPage: FindInPageSearching {
    weak var delegate: FindInPageDelegate?
    private(set) var searchTerm: String
    private(set) var current = 0
    private(set) var total = 0
    private(set) var diagnosticStatus: String?

    private var session: (any DelegateFindSession)?
    private var observationTimer: Timer?
    private var queryGeneration = 0
    private var pendingDirection: UITextStorageDirection?
    private var ended = false
    private let queryChanged: (String) -> Void

    init(webView: WKWebView, query: String, queryChanged: @escaping (String) -> Void,
         sessionFactory: (WKWebView) throws -> any DelegateFindSession = { try WebKitDelegateFindSession(webView: $0) }) {
        searchTerm = query
        self.queryChanged = queryChanged
        do {
            session = try sessionFactory(webView)
            diagnosticStatus = "EXPERIMENT · WebKit delegate session · nativeUI=false"
            if !query.isEmpty {
                session?.search(query)
                pendingDirection = .forward
            }
            observeResults()
        } catch {
            let reason = (error as? WebKitDelegateFindSession.Failure)?.rawValue ?? error.localizedDescription
            diagnosticStatus = "EXPERIMENT FAILED · \(reason)"
        }
    }

    func search(forText text: String) -> Bool {
        guard !ended, text != searchTerm else { return false }
        queryGeneration += 1
        searchTerm = text
        queryChanged(text)
        current = 0
        total = 0
        pendingDirection = text.isEmpty ? nil : .forward
        session?.invalidate()
        if !text.isEmpty { session?.search(text) }
        observeResults()
        delegate?.updated(findInPage: self)
        return true
    }

    func next() { move(.forward) }
    func previous() { move(.backward) }

    private func move(_ direction: UITextStorageDirection) {
        guard !ended, !searchTerm.isEmpty, let session else { return }
        if session.resultCount > 0 {
            pendingDirection = nil
            session.highlight(direction)
        } else {
            pendingDirection = direction
        }
        refreshResults(generation: queryGeneration)
    }

    private func observeResults() {
        observationTimer?.invalidate()
        observationTimer = nil
        guard !ended, session != nil else { return }
        let generation = queryGeneration
        // UIKit exposes no result-change callback for this route.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.refreshResults(generation: generation)
        }
        observationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func refreshResults(generation: Int) {
        guard !ended, generation == queryGeneration, let session else { return }
        let count = session.resultCount
        let newTotal = searchTerm.isEmpty || count == NSNotFound ? 0 : max(0, count)
        if newTotal > 0, let direction = pendingDirection {
            pendingDirection = nil
            if session.highlightedResultIndex == NSNotFound { session.highlight(direction) }
        }
        let index = session.highlightedResultIndex
        let newCurrent = index >= 0 && index < newTotal ? index + 1 : 0
        let status = "EXPERIMENT · WebKit delegate session · nativeUI=\(session.isNativeUIVisible)"
        guard current != newCurrent || total != newTotal || diagnosticStatus != status else { return }
        current = newCurrent
        total = newTotal
        diagnosticStatus = status
        delegate?.updated(findInPage: self)
    }

    func done() {
        guard !ended else { return }
        ended = true
        queryGeneration += 1
        observationTimer?.invalidate()
        observationTimer = nil
        pendingDirection = nil
        session?.end()
        session = nil
    }

    deinit { done() }
}
