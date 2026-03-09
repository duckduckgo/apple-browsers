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

import Foundation
import WebKit

// MARK: - Cookie Providing

public protocol AIChatCookieProviding {
    func cookies(for url: URL) async -> [HTTPCookie]
}

public struct WKHTTPCookieStoreProvider: AIChatCookieProviding {
    private let cookieStore: WKHTTPCookieStore

    public init(cookieStore: WKHTTPCookieStore = WKWebsiteDataStore.default().httpCookieStore) {
        self.cookieStore = cookieStore
    }

    public func cookies(for url: URL) async -> [HTTPCookie] {
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

public struct AIChatModelsResponse: Decodable {
    public let models: [AIChatRemoteModel]

    public init(models: [AIChatRemoteModel]) {
        self.models = models
    }
}

public struct AIChatRemoteModel: Decodable, Equatable {
    public let id: String
    public let name: String
    public let provider: String
    public let entityHasAccess: Bool
    public let supportsImageUpload: Bool
    public let supportedTools: [String]
    public let accessTier: [String]

    public init(id: String, name: String, provider: String, entityHasAccess: Bool, supportsImageUpload: Bool, supportedTools: [String], accessTier: [String]) {
        self.id = id
        self.name = name
        self.provider = provider
        self.entityHasAccess = entityHasAccess
        self.supportsImageUpload = supportsImageUpload
        self.supportedTools = supportedTools
        self.accessTier = accessTier
    }
}

// MARK: - Service Protocol

public protocol AIChatModelsProviding {
    func fetchModels() async throws -> [AIChatRemoteModel]
}

// MARK: - Service Implementation

public final class AIChatModelsService: AIChatModelsProviding {

    public enum ServiceError: Error, LocalizedError {
        case invalidResponse
        case httpError(statusCode: Int)

        public var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid response from models endpoint"
            case .httpError(let statusCode): return "HTTP error \(statusCode) from models endpoint"
            }
        }
    }

    private let baseURL: URL
    private let session: URLSession
    private let cookieProvider: AIChatCookieProviding

    public init(
        baseURL: URL = URL(string: "https://duck.ai")!,
        session: URLSession = .shared,
        cookieProvider: AIChatCookieProviding = WKHTTPCookieStoreProvider()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.cookieProvider = cookieProvider
    }

    public func fetchModels() async throws -> [AIChatRemoteModel] {
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

extension AIChatModel {
    public init(remoteModel: AIChatRemoteModel) {
        self.init(
            id: remoteModel.id,
            name: remoteModel.name,
            provider: .from(id: remoteModel.id, providerString: remoteModel.provider),
            supportsImageUpload: remoteModel.supportsImageUpload,
            entityHasAccess: remoteModel.entityHasAccess
        )
    }
}

extension AIChatModel.ModelProvider {
    public static func from(id: String, providerString: String) -> AIChatModel.ModelProvider {
        if id.hasPrefix("meta-llama/") || providerString == "azure" {
            return .meta
        } else if id.hasPrefix("mistralai/") {
            return .mistral
        } else if providerString == "anthropic" {
            return .anthropic
        } else if providerString == "openai" {
            return .openAI
        } else {
            return .unknown
        }
    }
}
