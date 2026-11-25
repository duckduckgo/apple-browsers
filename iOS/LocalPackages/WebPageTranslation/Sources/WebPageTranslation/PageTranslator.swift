//
//  PageTranslator.swift
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

import DDGError
import Foundation
import LocalModels
import TranslateKit

/// Translates a batch of texts with a loaded model. Blocking, and not safe to call from two threads at once.
public protocol TranslationEngine: AnyObject {
    /// With `isHtml`, each result is TranslateKit's JSON tree, or `"null"` when the translated HTML is malformed.
    func translate(_ inputs: [String], isHtml: Bool) throws -> [String]
}

extension TranslationModel: TranslationEngine {

    public func translate(_ inputs: [String], isHtml: Bool) throws -> [String] {
        try translate(inputs, isHtml: isHtml, htmlAsJSONTree: isHtml).map(\.text)
    }
}

public enum PageTranslatorError: DDGError {
    case notInstalled(String)
    case missingFile(String)
    case countMismatch

    public static var errorDomain: String { "com.duckduckgo.webPageTranslation.PageTranslatorError" }

    public var errorCode: Int {
        switch self {
        case .notInstalled: return 1
        case .missingFile: return 2
        case .countMismatch: return 3
        }
    }

    public var description: String {
        switch self {
        case .notInstalled(let pairID): return "Translation model \(pairID) isn't installed"
        case .missingFile(let role): return "The manifest pair has no \(role) file"
        case .countMismatch: return "TranslateKit returned a different number of results than inputs"
        }
    }
}

/// Where a pair's model is installed.
public protocol TranslationModelsProviding: Sendable {
    /// The manifest pair for a pair id and the folder its files are installed in; nil when it isn't installed.
    func installedPair(_ pairID: String) -> (pair: TranslationManifest.Pair, folder: URL)?
    /// Downloads and installs a pair, reporting progress from 0 to 1. Callers share one download per pair,
    /// and a caller that stops listening leaves it running.
    func install(_ pairID: String) -> AsyncThrowingStream<Double, Error>
}

/// Translates page units with an installed model. One instance is shared by all tabs, so only one
/// model is in memory: the most recently used pair's.
public final class PageTranslator: @unchecked Sendable {

    /// TranslateKit blocks and isn't thread-safe, so every call, loading included, goes through this queue.
    private let queue = DispatchQueue(label: "com.duckduckgo.webPageTranslation.translation", qos: .userInitiated)
    private let modelsProvider: TranslationModelsProviding
    private let customLoadEngine: (@Sendable (ModelSpec) throws -> TranslationEngine)?
    /// Set up on first use, so launch never waits on TranslateKit, and kept: the models it loads live in its
    /// context. A failed setup isn't retried. Touched only on `queue`.
    private lazy var translateKit = Result { try TranslateKit() }
    /// Touched only on `queue`.
    private var loaded: (pairID: String, engine: TranslationEngine)?

    /// - Parameter loadEngine: loads a model; TranslateKit's `loadModel` when `nil`.
    public init(modelsProvider: TranslationModelsProviding,
                loadEngine: (@Sendable (ModelSpec) throws -> TranslationEngine)? = nil) {
        self.modelsProvider = modelsProvider
        self.customLoadEngine = loadEngine
    }

    public func isInstalled(_ pairID: String) -> Bool {
        modelsProvider.installedPair(pairID) != nil
    }

    /// Makes a pair ready to translate, reporting progress from 0 to 1: at once when it's installed, otherwise
    /// from its download, which every caller shares.
    public func prepare(_ pairID: String) -> AsyncThrowingStream<Double, Error> {
        guard !isInstalled(pairID) else {
            return AsyncThrowingStream { continuation in
                continuation.yield(1)
                continuation.finish()
            }
        }
        return modelsProvider.install(pairID)
    }

    /// Plain units come back as `text`; HTML units as `tree`, minus those TranslateKit found malformed.
    public func translate(_ units: [PageTranslationUnit], pairID: String) async throws -> [PageTranslationUpdate] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try self.translateSync(units, pairID: pairID) })
            }
        }
    }

    private func translateSync(_ units: [PageTranslationUnit], pairID: String) throws -> [PageTranslationUpdate] {
        let engine = try engine(for: pairID)
        let plain = units.filter { !$0.html }
        let html = units.filter(\.html)

        let texts = try runTranslation(for: plain, isHtml: false, with: engine)
        let trees = try runTranslation(for: html, isHtml: true, with: engine)
        return zip(plain, texts).map { PageTranslationUpdate(id: $0.id, text: $1) }
            + zip(html, trees).filter { $1 != "null" }.map { PageTranslationUpdate(id: $0.id, tree: $1) }
    }

    private func runTranslation(for units: [PageTranslationUnit], isHtml: Bool, with engine: TranslationEngine) throws -> [String] {
        guard !units.isEmpty else { return [] }
        let results = try engine.translate(units.map(\.text), isHtml: isHtml)
        guard results.count == units.count else { throw PageTranslatorError.countMismatch }
        return results
    }

    private func loadEngine(_ spec: ModelSpec) throws -> TranslationEngine {
        if let customLoadEngine {
            return try customLoadEngine(spec)
        }
        return try translateKit.get().loadModel(spec)
    }

    private func engine(for pairID: String) throws -> TranslationEngine {
        if let loaded, loaded.pairID == pairID {
            return loaded.engine
        }
        guard let (pair, folder) = modelsProvider.installedPair(pairID) else { throw PageTranslatorError.notInstalled(pairID) }
        // Drop the previous model first, so two are never in memory at once.
        loaded = nil
        let engine = try loadEngine(try pair.modelSpec(in: folder))
        loaded = (pairID, engine)
        return engine
    }
}
