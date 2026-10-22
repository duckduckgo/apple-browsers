//
//  GetAutofillIdentitiesBrowserTool.swift
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
import BrowserServicesKit
import Foundation

/// Shares one saved Autofill identity with Duck.ai, the one the user picks. Nothing leaves the
/// browser until they pick; every call asks again, and nothing is logged.
@MainActor
final class GetAutofillIdentitiesBrowserTool: BrowserTool {

    static let maxPurposeLength = 200

    /// Matches `AIChatBrowserToolsSubfeature.getAutofillIdentities`, which is how the catalog gates it.
    let name = "getAutofillIdentities"
    let title = "Get Autofill identities"
    let description = "Ask the user to share one of their saved identities (name, birthday, address, phone, email) from the browser's Autofill. Use this instead of asking the user to type their details. The user picks which identity to share."
    let permissionMode = BrowserToolPermissionMode.ask
    let approvesEachCall = true

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "purpose": [
                "type": "string",
                "maxLength": .int(GetAutofillIdentitiesBrowserTool.maxPurposeLength),
                "description": "Shown to the user, e.g. \"to fill the checkout on Example Shoes\"."
            ]
        ]
    ]

    let outputSchema: JSONValue? = [
        "type": "object",
        "properties": [
            "identity": [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "title": ["type": "string"],
                    "name": BrowserToolIdentities.stringGroupSchema(["first", "middle", "last"]),
                    "birthday": [
                        "type": "object",
                        "properties": ["day": ["type": "integer"], "month": ["type": "integer"], "year": ["type": "integer"]]
                    ],
                    "address": BrowserToolIdentities.stringGroupSchema(["street", "street2", "city", "province", "postalCode", "countryCode"]),
                    "contact": BrowserToolIdentities.stringGroupSchema(["homePhone", "mobilePhone", "email"])
                ],
                "required": ["id"]
            ]
        ],
        "required": ["identity"]
    ]

    let annotations: MCPToolAnnotations? = MCPToolAnnotations(readOnlyHint: true,
                                                              destructiveHint: false,
                                                              idempotentHint: false,
                                                              openWorldHint: false)

    private let identities: BrowserToolIdentityProviding

    init(identities: BrowserToolIdentityProviding) {
        self.identities = identities
    }

    func approvalPrompt(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolApprovalPrompt {
        guard !context.isBurner else { return .refuse(.unavailable) }
        guard let givenPurpose = Self.purpose(from: arguments) else { return .refuse(.invalidArguments) }
        let saved = identities.identities().filter { $0.id != nil }
        guard !saved.isEmpty else { return .refuse(.notFound) }

        var meta: [String: JSONValue] = [
            "kind": "identityPicker",
            "options": .array(saved.map(BrowserToolIdentities.option(for:)))
        ]
        if let givenPurpose {
            meta["purpose"] = .string(givenPurpose)
        }
        return .choose(message: "Share a saved identity with Duck.ai?",
                       choices: saved.compactMap(BrowserToolIdentities.id(of:)),
                       meta: .object(meta))
    }

    /// Nothing is shared without the user's pick.
    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        .failure(.denied)
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext, approvedChoice: String) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        // Read again: the identity may have been deleted while the user decided.
        guard let identity = identities.identities().first(where: { BrowserToolIdentities.id(of: $0) == approvedChoice }) else {
            return .failure(.notFound)
        }
        return .success(["identity": BrowserToolIdentities.jsonValue(of: identity)])
    }

    /// `.some(nil)` when no purpose was given, nil when the arguments are invalid.
    static func purpose(from arguments: JSONValue?) -> String?? {
        switch arguments {
        case .none, .some(.null):
            return .some(nil)
        case .some(.object):
            break
        default:
            return nil
        }
        switch arguments?["purpose"] {
        case .none, .some(.null):
            return .some(nil)
        case .some(.string(let purpose)):
            let trimmed = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count <= maxPurposeLength else { return nil }
            return .some(trimmed.isEmpty ? nil : trimmed)
        default:
            return nil
        }
    }
}

/// The user's saved Autofill identities, behind a seam so the tool is testable without the vault.
@MainActor
protocol BrowserToolIdentityProviding: AnyObject {
    func identities() -> [SecureVaultModels.Identity]
}

@MainActor
final class AutofillIdentityProvider: BrowserToolIdentityProviding {

    func identities() -> [SecureVaultModels.Identity] {
        (try? AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter.shared).identities()) ?? []
    }
}

/// How an identity is offered in the picker and shared afterwards. Empty fields, and groups left
/// empty by them, are omitted rather than sent as empty strings.
enum BrowserToolIdentities {

    static func id(of identity: SecureVaultModels.Identity) -> String? {
        identity.id.map(String.init)
    }

    static func option(for identity: SecureVaultModels.Identity) -> JSONValue {
        [
            "value": .string(id(of: identity) ?? ""),
            "title": .string(title(of: identity)),
            "subtitle": .string(subtitle(of: identity))
        ]
    }

    /// The name the user gave it, else the person's name.
    static func title(of identity: SecureVaultModels.Identity) -> String {
        text(identity.title) ?? text(fullName(of: identity)) ?? "Identity"
    }

    /// "<first last> · <city>", leaving out whichever part is missing.
    static func subtitle(of identity: SecureVaultModels.Identity) -> String {
        [text(fullName(of: identity)), text(identity.addressCity)].compactMap { $0 }.joined(separator: " · ")
    }

    static func jsonValue(of identity: SecureVaultModels.Identity) -> JSONValue {
        var object: [String: JSONValue] = ["id": .string(id(of: identity) ?? "")]
        object["title"] = text(identity.title).map(JSONValue.string)
        object["name"] = group([
            ("first", text(identity.firstName)),
            ("middle", text(identity.middleName)),
            ("last", text(identity.lastName))
        ])
        object["birthday"] = numberGroup([
            ("day", identity.birthdayDay),
            ("month", identity.birthdayMonth),
            ("year", identity.birthdayYear)
        ])
        object["address"] = group([
            ("street", text(identity.addressStreet)),
            ("street2", text(identity.addressStreet2)),
            ("city", text(identity.addressCity)),
            ("province", text(identity.addressProvince)),
            ("postalCode", text(identity.addressPostalCode)),
            ("countryCode", text(identity.addressCountryCode)?.uppercased())
        ])
        object["contact"] = group([
            ("homePhone", text(identity.homePhone)),
            ("mobilePhone", text(identity.mobilePhone)),
            ("email", text(identity.emailAddress))
        ])
        return .object(object)
    }

    static func stringGroupSchema(_ keys: [String]) -> JSONValue {
        let properties: [String: JSONValue] = Dictionary(uniqueKeysWithValues: keys.map { ($0, JSONValue.object(["type": .string("string")])) })
        return ["type": "object", "properties": .object(properties)]
    }

    private static func fullName(of identity: SecureVaultModels.Identity) -> String {
        [text(identity.firstName), text(identity.lastName)].compactMap { $0 }.joined(separator: " ")
    }

    private static func group(_ entries: [(String, String?)]) -> JSONValue? {
        let present = entries.compactMap { key, value in value.map { (key, JSONValue.string($0)) } }
        return present.isEmpty ? nil : .object(Dictionary(uniqueKeysWithValues: present))
    }

    private static func numberGroup(_ entries: [(String, Int?)]) -> JSONValue? {
        let present = entries.compactMap { key, value in value.map { (key, JSONValue.int($0)) } }
        return present.isEmpty ? nil : .object(Dictionary(uniqueKeysWithValues: present))
    }

    private static func text(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
