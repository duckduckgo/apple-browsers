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
import os.log
import WebKit
import WKAbstractions

// MARK: - Cookie Providing

@MainActor
public protocol AIChatCookieProviding {
    func cookies(for url: URL) async -> [HTTPCookie]
}

@MainActor
public struct WKHTTPCookieStoreProvider: AIChatCookieProviding {
    private let cookieStore: any DDGHTTPCookieStore

    public nonisolated init(cookieStore: any DDGHTTPCookieStore = HTTPCookieStoreWrapper(wrapped: WKWebsiteDataStore.default().httpCookieStore)) {
        self.cookieStore = cookieStore
    }

    public func cookies(for url: URL) async -> [HTTPCookie] {
        let cookies = await cookieStore.allCookies()
        let domain = url.host ?? ""
        return cookies.filter { cookie in
            let cookieDomain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return domain.hasSuffix(cookieDomain)
        }
    }
}

// MARK: - Remote Models

public struct AIChatModelsResponse: Decodable {
    public let models: [AIChatRemoteModel]
    public let attachmentLimits: AIChatAttachmentLimits?

    public init(models: [AIChatRemoteModel], attachmentLimits: AIChatAttachmentLimits? = nil) {
        self.models = models
        self.attachmentLimits = attachmentLimits
    }

    private enum CodingKeys: String, CodingKey {
        case models
        case attachmentLimits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        models = try container.decode([AIChatRemoteModel].self, forKey: .models)

        do {
            attachmentLimits = try container.decodeIfPresent(AIChatAttachmentLimits.self, forKey: .attachmentLimits)
        } catch {
            Logger.aiChat.error("Failed to decode AI Chat attachment limits: \(error.localizedDescription)")
            attachmentLimits = nil
        }
    }
}

public struct AIChatRemoteModel: Decodable, Equatable {
    public let id: String
    public let name: String
    public let modelShortName: String?
    public let provider: String
    public let entityHasAccess: Bool
    public let supportsImageUpload: Bool
    public let supportedFileTypes: [String]?
    public let supportedTools: [String]
    public let accessTier: [String]
    public let supportedReasoningEffort: [AIChatReasoningEffort]
    public let reasoningEffortAccess: [AIChatReasoningEffortAccess]?

    public init(
        id: String,
        name: String,
        modelShortName: String? = nil,
        provider: String,
        entityHasAccess: Bool,
        supportsImageUpload: Bool,
        supportedFileTypes: [String]? = nil,
        supportedTools: [String],
        accessTier: [String],
        supportedReasoningEffort: [AIChatReasoningEffort] = [],
        reasoningEffortAccess: [AIChatReasoningEffortAccess]? = nil
    ) {
        self.id = id
        self.name = name
        self.modelShortName = modelShortName
        self.provider = provider
        self.entityHasAccess = entityHasAccess
        self.supportsImageUpload = supportsImageUpload
        self.supportedFileTypes = supportedFileTypes
        self.supportedTools = supportedTools
        self.accessTier = accessTier
        self.supportedReasoningEffort = supportedReasoningEffort
        self.reasoningEffortAccess = reasoningEffortAccess
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, modelShortName, provider, entityHasAccess, supportsImageUpload, supportedFileTypes, supportedTools, supportedReasoningEffort, accessTier, reasoningEffortAccess
    }

    /// Raw wire shape of a single `reasoningEffortAccess` entry. Decoded as `String` for
    /// `id` so that future / unknown effort IDs do not fail the whole `/models` decode.
    private struct RawReasoningEffortAccess: Decodable {
        let id: String
        let accessTier: [String]
        let entityHasAccess: Bool
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.modelShortName = try container.decodeIfPresent(String.self, forKey: .modelShortName)
        self.provider = try container.decode(String.self, forKey: .provider)
        self.entityHasAccess = try container.decode(Bool.self, forKey: .entityHasAccess)
        self.supportsImageUpload = try container.decode(Bool.self, forKey: .supportsImageUpload)
        self.supportedFileTypes = try container.decodeIfPresent([String].self, forKey: .supportedFileTypes)
        self.supportedTools = try container.decode([String].self, forKey: .supportedTools)
        self.supportedReasoningEffort = try container.decodeIfPresent([String].self, forKey: .supportedReasoningEffort)?
            .compactMap(AIChatReasoningEffort.init(rawValue:)) ?? []
        self.accessTier = try container.decode([String].self, forKey: .accessTier)

        do {
            let rawEntries = try container.decodeIfPresent([RawReasoningEffortAccess].self, forKey: .reasoningEffortAccess)
            self.reasoningEffortAccess = rawEntries?.compactMap { entry in
                guard let effort = AIChatReasoningEffort(rawValue: entry.id) else { return nil }
                return AIChatReasoningEffortAccess(
                    effort: effort,
                    accessTier: entry.accessTier,
                    entityHasAccess: entry.entityHasAccess
                )
            }
        } catch {
            Logger.aiChat.error("Failed to decode AI Chat reasoningEffortAccess: \(error.localizedDescription)")
            self.reasoningEffortAccess = nil
        }
    }
}

// MARK: - Service Protocol

@MainActor
public protocol AIChatModelsProviding {
    func fetchModels() async throws -> AIChatModelsResponse
}

// MARK: - Service Implementation

@MainActor
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

    /// The production AI Chat API origin, built from the canonical `URL.duckAIHost`.
    public static let defaultBaseURL = URL(string: "https://\(URL.duckAIHost)")!

    private let baseURL: URL
    private let session: URLSession
    private let cookieProvider: AIChatCookieProviding

    public nonisolated init(
        baseURL: URL = AIChatModelsService.defaultBaseURL,
        session: URLSession = .shared,
        cookieProvider: AIChatCookieProviding = WKHTTPCookieStoreProvider()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.cookieProvider = cookieProvider
    }

    public func fetchModels() async throws -> AIChatModelsResponse {
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

        return try JSONDecoder().decode(AIChatModelsResponse.self, from: data)
    }

}

// MARK: - AIChatModel Mapping

public enum AIChatUserTier: String {
    case free
    case plus
    case pro
    case `internal`
}

extension AIChatModel {
    private static let nativeSupportedImageFormats = ["png", "jpeg", "webp"]

    public init(remoteModel: AIChatRemoteModel, userTier: AIChatUserTier) {
        let hasAccess = remoteModel.accessTier.contains(userTier.rawValue)
        let hasEffortAccess = remoteModel.reasoningEffortAccess?.map { entry in
            AIChatReasoningEffortAccess(
                effort: entry.effort,
                accessTier: entry.accessTier,
                entityHasAccess: entry.accessTier.contains(userTier.rawValue)
            )
        }
        self.init(
            id: remoteModel.id,
            name: remoteModel.name,
            shortName: remoteModel.modelShortName,
            provider: .from(id: remoteModel.id, providerString: remoteModel.provider),
            supportsImageUpload: remoteModel.supportsImageUpload,
            supportedFileTypes: remoteModel.supportedFileTypes ?? [],
            supportedImageFormats: remoteModel.supportsImageUpload ? Self.nativeSupportedImageFormats : [],
            supportedTools: remoteModel.supportedTools.compactMap(AIChatRAGTool.init(rawValue:)),
            entityHasAccess: hasAccess,
            accessTier: remoteModel.accessTier,
            supportedReasoningEffort: remoteModel.supportedReasoningEffort,
            reasoningEffortAccess: hasEffortAccess
        )
    }
}

extension AIChatModel.ModelProvider {
    public static func from(id: String, providerString: String) -> AIChatModel.ModelProvider {
        let normalizedProviderString = providerString.lowercased()
        let isMetaProvider = id.hasPrefix("meta-llama/") || id.hasPrefix("meta-llama_") || normalizedProviderString == "azure"
        let isMistralProvider = id.hasPrefix("mistralai/")
            || id.hasPrefix("mistralai_")
            || normalizedProviderString == "mistral"
            || normalizedProviderString == "mistralai"

        if isMetaProvider {
            return .meta
        } else if isMistralProvider {
            return .mistral
        } else if id.contains("gpt-oss") || normalizedProviderString == "tinfoil" {
            return .oss
        } else if normalizedProviderString == "anthropic" {
            return .anthropic
        } else if normalizedProviderString == "openai" {
            return .openAI
        } else {
            return .unknown
        }
    }
}
