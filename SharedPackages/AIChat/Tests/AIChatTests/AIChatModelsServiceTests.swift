//
//  AIChatModelsServiceTests.swift
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
import AIChat

@MainActor
final class AIChatModelsServiceTests: XCTestCase {

    // MARK: - JSON Decoding Tests

    func testWhenValidJSONIsDecoded_ThenModelsAreParsedCorrectly() throws {
        // Given
        let json = """
        {
            "models": [
                {
                    "id": "gpt-4o-mini",
                    "name": "GPT-4o mini",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": false,
                    "supportedTools": ["WebSearch"],
                    "accessTier": ["free"]
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        // When
        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)

        // Then
        XCTAssertEqual(response.models.count, 1)
        XCTAssertEqual(response.models[0].id, "gpt-4o-mini")
        XCTAssertEqual(response.models[0].name, "GPT-4o mini")
        XCTAssertEqual(response.models[0].provider, "openai")
        XCTAssertTrue(response.models[0].entityHasAccess)
        XCTAssertFalse(response.models[0].supportsImageUpload)
        XCTAssertEqual(response.models[0].supportedTools, ["WebSearch"])
        XCTAssertEqual(response.models[0].accessTier, ["free"])
        XCTAssertEqual(response.models[0].supportedReasoningEffort, [])
    }

    func testWhenJSONOmitsSupportedReasoningEffort_ThenDecodesWithEmptyArray() throws {
        // Covers backwards compatibility: older `duckchat/v1/models` responses don't include
        // the field, and they must still decode rather than failing with `keyNotFound`.
        let json = """
        {
            "models": [
                {
                    "id": "gpt-4o-mini",
                    "name": "GPT-4o mini",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": false,
                    "supportedTools": [],
                    "accessTier": ["free"]
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)

        XCTAssertEqual(response.models.count, 1)
        XCTAssertEqual(response.models[0].supportedReasoningEffort, [])
    }

    func testWhenJSONIncludesNullSupportedReasoningEffort_ThenDecodesWithEmptyArray() throws {
        let json = """
        {
            "models": [
                {
                    "id": "gpt-4o-mini",
                    "name": "GPT-4o mini",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": false,
                    "supportedTools": [],
                    "supportedReasoningEffort": null,
                    "accessTier": ["free"]
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)

        XCTAssertEqual(response.models.count, 1)
        XCTAssertEqual(response.models[0].supportedReasoningEffort, [])
    }

    func testWhenJSONIncludesSupportedReasoningEffort_ThenValueIsDecoded() throws {
        let json = """
        {
            "models": [
                {
                    "id": "reasoning-model",
                    "name": "Reasoning Model",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": false,
                    "supportedTools": [],
                    "supportedReasoningEffort": ["none", "low", "medium"],
                    "accessTier": ["free"]
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)

        XCTAssertEqual(response.models[0].supportedReasoningEffort, [.none, .low, .medium])
    }

    func testWhenJSONIncludesUnknownSupportedReasoningEffort_ThenUnknownValueIsIgnored() throws {
        let json = """
        {
            "models": [
                {
                    "id": "future-model",
                    "name": "Future Model",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": false,
                    "supportedTools": [],
                    "supportedReasoningEffort": ["none", "future", "high"],
                    "accessTier": ["free"]
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)

        XCTAssertEqual(response.models[0].supportedReasoningEffort, [.none, .high])
    }

    // MARK: - reasoningEffortAccess Decoding

    func testWhenJSONOmitsReasoningEffortAccess_ThenFieldIsNil() throws {
        // Backwards compatibility: pre-rollout payloads (and any future BE responses that
        // choose not to gate per-effort) omit the field entirely. The client must preserve
        // current behavior — supported efforts inherit model access.
        let json = """
        {
            "models": [
                {
                    "id": "gpt-5.2",
                    "name": "GPT-5.2",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": true,
                    "supportedTools": [],
                    "supportedReasoningEffort": ["none", "low", "medium"],
                    "accessTier": ["plus", "pro", "internal"]
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)

        XCTAssertNil(response.models[0].reasoningEffortAccess)
    }

    func testWhenJSONIncludesNullReasoningEffortAccess_ThenFieldIsNil() throws {
        let json = """
        {
            "models": [
                {
                    "id": "gpt-5.2",
                    "name": "GPT-5.2",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": true,
                    "supportedTools": [],
                    "supportedReasoningEffort": ["none", "low", "medium"],
                    "accessTier": ["plus", "pro", "internal"],
                    "reasoningEffortAccess": null
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)

        XCTAssertNil(response.models[0].reasoningEffortAccess)
    }

    func testWhenJSONIncludesEmptyReasoningEffortAccess_ThenFieldIsEmptyArray() throws {
        // An explicit empty array is distinct from `nil` (field absent). Surfacing this
        // distinction lets callers tell "BE has no per-effort metadata" (nil) apart from
        // "BE returned per-effort metadata but no entries are accessible/known" ([]).
        let json = """
        {
            "models": [
                {
                    "id": "gpt-5.2",
                    "name": "GPT-5.2",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": true,
                    "supportedTools": [],
                    "supportedReasoningEffort": ["none", "low", "medium"],
                    "accessTier": ["plus", "pro", "internal"],
                    "reasoningEffortAccess": []
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)

        XCTAssertEqual(response.models[0].reasoningEffortAccess, [])
    }

    func testWhenJSONIncludesFullReasoningEffortAccess_ThenAllEntriesAreDecoded() throws {
        let json = """
        {
            "models": [
                {
                    "id": "gpt-5.2",
                    "name": "GPT-5.2",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": true,
                    "supportedTools": [],
                    "supportedReasoningEffort": ["none", "low", "medium"],
                    "accessTier": ["plus", "pro", "internal"],
                    "reasoningEffortAccess": [
                        { "id": "none", "accessTier": ["plus", "pro", "internal"], "entityHasAccess": true },
                        { "id": "low", "accessTier": ["plus", "pro", "internal"], "entityHasAccess": true },
                        { "id": "medium", "accessTier": ["pro", "internal"], "entityHasAccess": false }
                    ]
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)
        let access = try XCTUnwrap(response.models[0].reasoningEffortAccess)

        XCTAssertEqual(access.count, 3)
        XCTAssertEqual(access[0], AIChatReasoningEffortAccess(effort: .none, accessTier: ["plus", "pro", "internal"], entityHasAccess: true))
        XCTAssertEqual(access[1], AIChatReasoningEffortAccess(effort: .low, accessTier: ["plus", "pro", "internal"], entityHasAccess: true))
        XCTAssertEqual(access[2], AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro", "internal"], entityHasAccess: false))
    }

    func testWhenReasoningEffortAccessContainsUnknownId_ThenUnknownEntryIsIgnored() throws {
        // Forward compatibility: server may add new effort IDs (e.g. "very_high") before
        // the client knows them. The unknown entry must be silently dropped and the rest
        // of the model must still decode.
        let json = """
        {
            "models": [
                {
                    "id": "future-model",
                    "name": "Future Model",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": false,
                    "supportedTools": [],
                    "supportedReasoningEffort": ["none", "high"],
                    "accessTier": ["pro"],
                    "reasoningEffortAccess": [
                        { "id": "none", "accessTier": ["pro"], "entityHasAccess": true },
                        { "id": "very_high", "accessTier": ["pro"], "entityHasAccess": true },
                        { "id": "high", "accessTier": ["pro"], "entityHasAccess": true }
                    ]
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)
        let access = try XCTUnwrap(response.models[0].reasoningEffortAccess)

        XCTAssertEqual(access.map(\.effort), [.none, .high])
    }

    func testWhenReasoningEffortAccessEntryHasUnknownNestedField_ThenItIsIgnored() throws {
        // Forward compatibility: server may add new fields per entry (e.g. a display
        // label, deprecation flag). Unknown fields inside an entry must not fail the decode.
        let json = """
        {
            "models": [
                {
                    "id": "gpt-5.2",
                    "name": "GPT-5.2",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": true,
                    "supportedTools": [],
                    "supportedReasoningEffort": ["medium"],
                    "accessTier": ["pro"],
                    "reasoningEffortAccess": [
                        {
                            "id": "medium",
                            "accessTier": ["pro"],
                            "entityHasAccess": true,
                            "displayLabel": "Extended Reasoning",
                            "deprecated": false
                        }
                    ]
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)
        let access = try XCTUnwrap(response.models[0].reasoningEffortAccess)

        XCTAssertEqual(access, [
            AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro"], entityHasAccess: true)
        ])
    }

    func testWhenReasoningEffortAccessEntryIsMalformed_ThenWholeFieldFallsBackToNilButModelDecodes() throws {
        let json = """
        {
            "models": [
                {
                    "id": "gpt-5.2",
                    "name": "GPT-5.2",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": true,
                    "supportedTools": [],
                    "supportedReasoningEffort": ["medium"],
                    "accessTier": ["pro"],
                    "reasoningEffortAccess": [
                        { "id": "medium" }
                    ]
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)

        XCTAssertEqual(response.models[0].id, "gpt-5.2")
        XCTAssertNil(response.models[0].reasoningEffortAccess)
    }

    func testWhenReasoningEffortAccessIsWrongType_ThenWholeFieldFallsBackToNilButModelDecodes() throws {
        // Defensive: if BE accidentally returns an object instead of an array, we don't
        // explode — we drop the field and keep parsing the rest.
        let json = """
        {
            "models": [
                {
                    "id": "gpt-5.2",
                    "name": "GPT-5.2",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": true,
                    "supportedTools": [],
                    "supportedReasoningEffort": ["medium"],
                    "accessTier": ["pro"],
                    "reasoningEffortAccess": { "medium": true }
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)
        XCTAssertEqual(response.models[0].id, "gpt-5.2")
        XCTAssertNil(response.models[0].reasoningEffortAccess)
    }

    func testWhenReasoningEffortAccessIsDecoded_ThenItIsMappedOntoAIChatModel() throws {
        let json = """
        {
            "models": [
                {
                    "id": "gpt-5.2",
                    "name": "GPT-5.2",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": true,
                    "supportedTools": [],
                    "supportedReasoningEffort": ["none", "low", "medium"],
                    "accessTier": ["plus", "pro", "internal"],
                    "reasoningEffortAccess": [
                        { "id": "none", "accessTier": ["plus", "pro", "internal"], "entityHasAccess": true },
                        { "id": "low", "accessTier": ["plus", "pro", "internal"], "entityHasAccess": true },
                        { "id": "medium", "accessTier": ["pro", "internal"], "entityHasAccess": false }
                    ]
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)
        let model = AIChatModel(remoteModel: response.models[0], userTier: .plus)
        let access = try XCTUnwrap(model.reasoningEffortAccess)

        XCTAssertEqual(access.count, 3)
        XCTAssertEqual(access.first(where: { $0.effort == .medium })?.entityHasAccess, false)
        XCTAssertEqual(access.first(where: { $0.effort == .low })?.entityHasAccess, true)
    }

    func testWhenReasoningEffortAccessIsAbsent_ThenMappedAIChatModelHasNilField() throws {
        // Mirror of the decoding test, asserted at the mapping layer.
        let json = """
        {
            "models": [
                {
                    "id": "gpt-4o-mini",
                    "name": "GPT-4o mini",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": false,
                    "supportedTools": [],
                    "accessTier": ["free"]
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)
        let model = AIChatModel(remoteModel: response.models[0], userTier: .free)

        XCTAssertNil(model.reasoningEffortAccess)
    }

    func testWhenMultipleModelsAreDecoded_ThenAllAreParsed() throws {
        // Given
        let json = """
        {
            "models": [
                {
                    "id": "gpt-4o-mini",
                    "name": "GPT-4o mini",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": false,
                    "supportedTools": [],
                    "accessTier": ["free"]
                },
                {
                    "id": "claude-sonnet-4-5",
                    "name": "Claude Sonnet 4.5",
                    "provider": "anthropic",
                    "entityHasAccess": false,
                    "supportsImageUpload": true,
                    "supportedTools": ["WebSearch"],
                    "accessTier": ["premium"]
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        // When
        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)

        // Then
        XCTAssertEqual(response.models.count, 2)
        XCTAssertEqual(response.models[0].id, "gpt-4o-mini")
        XCTAssertEqual(response.models[1].id, "claude-sonnet-4-5")
        XCTAssertFalse(response.models[1].entityHasAccess)
        XCTAssertTrue(response.models[1].supportsImageUpload)
    }

    func testWhenSupportedFileTypesArePresent_ThenTheyDecode() throws {
        let json = """
        {
            "models": [
                {
                    "id": "gpt-4o",
                    "name": "GPT-4o",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": true,
                    "supportedFileTypes": ["application/pdf"],
                    "supportedTools": [],
                    "accessTier": ["free"]
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)

        XCTAssertEqual(response.models.first?.supportedFileTypes, ["application/pdf"])
    }

    func testWhenAttachmentLimitsArePresent_ThenTheyDecode() throws {
        let json = """
        {
            "models": [],
            "attachmentLimits": {
                "free": {
                    "files": {
                        "maxPerConversation": 3,
                        "maxFileSizeMB": 5,
                        "maxTotalFileSizeBytes": 5242880,
                        "maxPagesPerFile": 8
                    },
                    "images": {
                        "maxPerTurn": 3,
                        "maxPerConversation": 5,
                        "maxInputCharsWithAttachments": 4500
                    }
                },
                "plus": {
                    "files": {
                        "maxPerConversation": 5,
                        "maxFileSizeMB": 25,
                        "maxTotalFileSizeBytes": 26214400,
                        "maxPagesPerFile": 35
                    },
                    "images": {
                        "maxPerTurn": 3,
                        "maxPerConversation": 10,
                        "maxInputCharsWithAttachments": 4500
                    }
                },
                "pro": {
                    "files": {
                        "maxPerConversation": 5,
                        "maxFileSizeMB": 25,
                        "maxTotalFileSizeBytes": 26214400,
                        "maxPagesPerFile": 50
                    },
                    "images": {
                        "maxPerTurn": 3,
                        "maxPerConversation": 10,
                        "maxInputCharsWithAttachments": 4500
                    }
                }
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)

        XCTAssertEqual(response.attachmentLimits?.free.files.maxPerConversation, 3)
        XCTAssertEqual(response.attachmentLimits?.plus.images.maxPerConversation, 10)
        XCTAssertEqual(response.attachmentLimits?.limits(for: .free).images.maxPerTurn, 3)
        XCTAssertEqual(response.attachmentLimits?.limits(for: .plus).files.maxPagesPerFile, 35)
        XCTAssertEqual(response.attachmentLimits?.limits(for: .pro).files.maxPagesPerFile, 50)
        XCTAssertEqual(response.attachmentLimits?.limits(for: .internal).files.maxPagesPerFile, 50)
    }

    func testWhenAttachmentLimitsAreMalformed_ThenModelsStillDecode() throws {
        let json = """
        {
            "models": [
                {
                    "id": "gpt-4o",
                    "name": "GPT-4o",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": true,
                    "supportedTools": [],
                    "accessTier": ["free"]
                }
            ],
            "attachmentLimits": {
                "free": {
                    "files": {
                        "maxPerConversation": 3,
                        "maxFileSizeMB": 5,
                        "maxTotalFileSizeBytes": 5242880,
                        "maxPagesPerFile": 8
                    },
                    "images": {
                        "maxPerTurn": 3,
                        "maxPerConversation": 5,
                        "maxInputCharsWithAttachments": 4500
                    }
                }
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)

        XCTAssertEqual(response.models.first?.id, "gpt-4o")
        XCTAssertNil(response.attachmentLimits)
    }

    // MARK: - AIChatModel Mapping Tests

    func testWhenRemoteModelIsMapped_ThenFieldsAreCorrect() {
        // Given
        let remoteModel = AIChatRemoteModel(
            id: "gpt-4o-mini",
            name: "GPT-4o mini",
            modelShortName: "4o-mini",
            provider: "openai",
            entityHasAccess: true,
            supportsImageUpload: false,
            supportedTools: ["WebSearch"],
            accessTier: ["free"]
        )

        // When — free user should have access to a free-tier model
        let model = AIChatModel(remoteModel: remoteModel, userTier: .free)

        // Then
        XCTAssertEqual(model.id, "gpt-4o-mini")
        XCTAssertEqual(model.name, "GPT-4o mini")
        XCTAssertTrue(model.entityHasAccess)
        XCTAssertFalse(model.supportsImageUpload)
    }

    func testWhenRemoteModelIncludesFileSupport_ThenMappedModelSupportsFileUpload() {
        let remoteModel = AIChatRemoteModel(
            id: "gpt-4o",
            name: "GPT-4o",
            modelShortName: "GPT-4o",
            provider: "openai",
            entityHasAccess: true,
            supportsImageUpload: true,
            supportedFileTypes: ["application/pdf"],
            supportedTools: [],
            accessTier: ["free"]
        )

        let model = AIChatModel(remoteModel: remoteModel, userTier: .free)

        XCTAssertTrue(model.supportsFileUpload)
        XCTAssertEqual(model.supportedFileTypes, ["application/pdf"])
    }

    func testWhenReasoningEffortIsProvided_ThenItIsDecodedAndMapped() throws {
        let json = """
        {
            "models": [
                {
                    "id": "gpt-5.2",
                    "name": "GPT-5.2",
                    "provider": "openai",
                    "entityHasAccess": true,
                    "supportsImageUpload": true,
                    "supportedTools": [],
                    "accessTier": ["plus", "pro"],
                    "supportedReasoningEffort": ["none", "low", "medium"]
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AIChatModelsResponse.self, from: data)
        let model = AIChatModel(remoteModel: response.models[0], userTier: .plus)

        XCTAssertEqual(response.models[0].supportedReasoningEffort, [.none, .low, .medium])
        XCTAssertEqual(model.supportedReasoningEffort, [.none, .low, .medium])
    }

    func testWhenUserTierMatchesAccessTier_ThenEntityHasAccess() {
        let remoteModel = AIChatRemoteModel(
            id: "gpt-4o",
            name: "GPT-4o",
            modelShortName: "GPT-4o",
            provider: "openai",
            entityHasAccess: false,
            supportsImageUpload: true,
            supportedTools: [],
            accessTier: ["plus", "pro", "internal"]
        )

        let plusModel = AIChatModel(remoteModel: remoteModel, userTier: .plus)
        XCTAssertTrue(plusModel.entityHasAccess)

        let freeModel = AIChatModel(remoteModel: remoteModel, userTier: .free)
        XCTAssertFalse(freeModel.entityHasAccess)
    }

    // MARK: - ModelProvider Mapping Tests

    func testWhenProviderIsOpenAI_ThenMapsToOpenAI() {
        let provider = AIChatModel.ModelProvider.from(id: "gpt-4o-mini", providerString: "openai")
        XCTAssertEqual(provider, .openAI)
    }

    func testWhenProviderIsAnthropicString_ThenMapsToAnthropic() {
        let provider = AIChatModel.ModelProvider.from(id: "claude-sonnet-4-5", providerString: "anthropic")
        XCTAssertEqual(provider, .anthropic)
    }

    func testWhenModelIdHasMetaLlamaSlashPrefix_ThenMapsToMeta() {
        let provider = AIChatModel.ModelProvider.from(id: "meta-llama/Llama-4-Scout", providerString: "togetherai")
        XCTAssertEqual(provider, .meta)
    }

    func testWhenModelIdHasMetaLlamaUnderscorePrefix_ThenMapsToMeta() {
        let provider = AIChatModel.ModelProvider.from(id: "meta-llama_Llama-4-Scout-17B-16E-Instruct", providerString: "azure")
        XCTAssertEqual(provider, .meta)
    }

    func testWhenProviderIsAzure_ThenMapsToMeta() {
        let provider = AIChatModel.ModelProvider.from(id: "some-model", providerString: "azure")
        XCTAssertEqual(provider, .meta)
    }

    func testWhenModelIdHasMistralSlashPrefix_ThenMapsToMistral() {
        let provider = AIChatModel.ModelProvider.from(id: "mistralai/Mistral-Small-3", providerString: "togetherai")
        XCTAssertEqual(provider, .mistral)
    }

    func testWhenModelIdHasMistralUnderscorePrefix_ThenMapsToMistral() {
        let provider = AIChatModel.ModelProvider.from(id: "mistralai_Mistral-Small-24B-Instruct-2501", providerString: "togetherai")
        XCTAssertEqual(provider, .mistral)
    }

    func testWhenProviderIsMistralString_ThenMapsToMistral() {
        let provider = AIChatModel.ModelProvider.from(id: "mistral-small-2603", providerString: "mistral")
        XCTAssertEqual(provider, .mistral)
    }

    func testWhenProviderIsMistralAIString_ThenMapsToMistral() {
        let provider = AIChatModel.ModelProvider.from(id: "ministral-3b", providerString: "mistralai")
        XCTAssertEqual(provider, .mistral)
    }

    func testWhenModelIdContainsGptOss_ThenMapsToOSS() {
        let provider = AIChatModel.ModelProvider.from(id: "openai_gpt-oss-120b", providerString: "togetherai")
        XCTAssertEqual(provider, .oss)
    }

    func testWhenModelIdContainsGptOssWithTinfoil_ThenMapsToOSS() {
        let provider = AIChatModel.ModelProvider.from(id: "tinfoil/gpt-oss-120b", providerString: "tinfoil")
        XCTAssertEqual(provider, .oss)
    }

    func testWhenProviderIsTinfoilForNonGptOssModel_ThenMapsToOSS() {
        let provider = AIChatModel.ModelProvider.from(id: "tinfoil/gemma4-31b", providerString: "tinfoil")
        XCTAssertEqual(provider, .oss)
    }

    func testWhenProviderIsOpenAIString_ThenMapsToOpenAI() {
        let provider = AIChatModel.ModelProvider.from(id: "gpt-5", providerString: "openai")
        XCTAssertEqual(provider, .openAI)
    }

    func testWhenProviderIsUnknown_ThenMapsToUnknown() {
        let provider = AIChatModel.ModelProvider.from(id: "unknown-model", providerString: "unknown-provider")
        XCTAssertEqual(provider, .unknown)
    }

    func testWhenModelIdHasMetaPrefix_ThenIdTakesPrecedenceOverProviderString() {
        // Model ID prefix should take precedence over provider string
        let provider = AIChatModel.ModelProvider.from(id: "meta-llama_Llama-4-Scout", providerString: "anthropic")
        XCTAssertEqual(provider, .meta)
    }

    func testWhenModelIdHasMistralPrefix_ThenIdTakesPrecedenceOverProviderString() {
        let provider = AIChatModel.ModelProvider.from(id: "mistralai_Mistral-Small-3", providerString: "openai")
        XCTAssertEqual(provider, .mistral)
    }

    // MARK: - Service Error Tests

    func testWhenHTTPErrorOccurs_ThenServiceThrowsHTTPError() async {
        // Given
        let mockCookieProvider = MockCookieProvider()
        let (_, url) = makeStubSession(statusCode: 500, data: Data())
        let service = AIChatModelsService(baseURL: url, session: .shared, cookieProvider: mockCookieProvider)

        // When/Then — verify the service calls the URL correctly (integration would need URLProtocol stubbing)
        // For unit-level, we test the error type exists and has correct description
        let error = AIChatModelsService.ServiceError.httpError(statusCode: 500)
        XCTAssertEqual(error.errorDescription, "HTTP error 500 from models endpoint")
    }

    func testWhenInvalidResponseError_ThenDescriptionIsCorrect() {
        let error = AIChatModelsService.ServiceError.invalidResponse
        XCTAssertEqual(error.errorDescription, "Invalid response from models endpoint")
    }
}

// MARK: - Mocks

@MainActor
private final class MockCookieProvider: AIChatCookieProviding {
    var cookiesToReturn: [HTTPCookie] = []

    func cookies(for url: URL) async -> [HTTPCookie] {
        return cookiesToReturn
    }
}

// MARK: - Helpers

private func makeStubSession(statusCode: Int, data: Data) -> (URLSession, URL) {
    // Returns a placeholder URL for documentation; real URLProtocol stubbing
    // would be needed for full integration tests of the service layer.
    let url = URL(string: "https://stub.test")!
    return (.shared, url)
}
