//
//  AIChatModelsService.swift
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
import Foundation
import WebKit

// MARK: - Cookie Providing

protocol AIChatCookieProviding {
    func cookies(for url: URL) async -> [HTTPCookie]
}

struct WKHTTPCookieStoreProvider: AIChatCookieProviding {
    private let cookieStore: WKHTTPCookieStore

    init(cookieStore: WKHTTPCookieStore = WKWebsiteDataStore.default().httpCookieStore) {
        self.cookieStore = cookieStore
    }

    func cookies(for url: URL) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                let domain = url.host ?? ""
                let relevant = cookies.filter { cookie in
                    let cookieDomain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                    return domain.hasSuffix(cookieDomain)
                }
                continuation.resume(returning: relevant)
            }
        }
    }
}

// MARK: - Remote Models

struct AIChatModelsResponse: Decodable {
    let models: [AIChatRemoteModel]
}

struct AIChatRemoteModel: Decodable, Equatable {
    let id: String
    let name: String
    let modelShortName: String?
    let provider: String
    let entityHasAccess: Bool
    let supportsImageUpload: Bool
    let supportedTools: [String]
    let accessTier: [String]
}

// MARK: - Service Protocol

protocol AIChatModelsProviding {
    func fetchModels() async throws -> [AIChatRemoteModel]
}

// MARK: - Service Implementation

final class AIChatModelsService: AIChatModelsProviding {

    enum ServiceError: Error, LocalizedError {
        case invalidResponse
        case httpError(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid response from models endpoint"
            case .httpError(let statusCode): return "HTTP error \(statusCode) from models endpoint"
            }
        }
    }

    private let baseURL: URL
    private let session: URLSession
    private let cookieProvider: AIChatCookieProviding

    init(
        baseURL: URL = URL(string: "https://duck.ai")!,
        session: URLSession = .shared,
        cookieProvider: AIChatCookieProviding = WKHTTPCookieStoreProvider()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.cookieProvider = cookieProvider
    }

    func fetchModels() async throws -> [AIChatRemoteModel] {
        let url = baseURL.appendingPathComponent("duckchat/v1/models")

        let cookies = await cookieProvider.cookies(for: baseURL)
        var request = URLRequest(url: url)
        HTTPCookie.requestHeaderFields(with: cookies).forEach {
            request.addValue($1, forHTTPHeaderField: $0)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(AIChatModelsResponse.self, from: data).models
    }

}

// MARK: - AIChatModel Mapping

/// Represents the user's resolved access tier for model unlocking.
enum AIChatUserTier: String {
    case free
    case plus
    case pro
    case `internal`
}

extension AIChatModel {
    private static let nativeSupportedImageFormats = ["png", "jpeg", "webp"]

    /// Creates an `AIChatModel` from a remote model, resolving access based on the user's local subscription tier.
    init(remoteModel: AIChatRemoteModel, userTier: AIChatUserTier) {
        let hasAccess = remoteModel.accessTier.contains(userTier.rawValue)
        self.init(
            id: remoteModel.id,
            name: remoteModel.name,
            shortName: remoteModel.modelShortName,
            provider: .from(id: remoteModel.id, providerString: remoteModel.provider),
            supportsImageUpload: remoteModel.supportsImageUpload,
            supportedImageFormats: remoteModel.supportsImageUpload ? Self.nativeSupportedImageFormats : [],
            entityHasAccess: hasAccess,
            accessTier: remoteModel.accessTier
        )
    }
}

extension AIChatModel.ModelProvider {
    /// Maps a remote model's ID and provider string to the local ModelProvider enum.
    /// Model ID takes precedence since togetherai hosts models from multiple providers.
    /// Handles both `/` and `_` separators in model IDs (e.g. "meta-llama/Llama" or "meta-llama_Llama").
    static func from(id: String, providerString: String) -> AIChatModel.ModelProvider {
        if id.hasPrefix("meta-llama/") || id.hasPrefix("meta-llama_") || providerString == "azure" {
            return .meta
        } else if id.hasPrefix("mistralai/") || id.hasPrefix("mistralai_") {
            return .mistral
        } else if id.contains("gpt-oss") {
            return .oss
        } else if providerString == "anthropic" {
            return .anthropic
        } else if providerString == "openai" {
            return .openAI
        } else {
            return .unknown
        }
    }
}
