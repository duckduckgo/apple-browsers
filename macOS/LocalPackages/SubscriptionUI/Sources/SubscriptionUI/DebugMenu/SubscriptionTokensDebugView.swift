//
//  SubscriptionTokensDebugView.swift
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

import AppKit
import SwiftUI
import Subscription
import Networking

/// Reads and deletes the subscription token keychain items directly, bypassing the token storage, to simulate lost tokens,
/// and gets the token through the subscription manager to run its refresh and recovery flows.
@MainActor
public final class SubscriptionTokensDebugViewModel: ObservableObject {

    public typealias Field = SubscriptionTokenKeychainStorage.SubscriptionKeychainField

    enum TokenState {
        case found(TokenContainer)
        case missing
        case undecodable
        case readFailed(Error)
    }

    struct Token: Identifiable {
        let field: Field
        let state: TokenState
        var id: String { field.rawValue }
    }

    struct Alert {
        let title: String
        let message: String
    }

    @Published private(set) var tokens: [Token] = []
    @Published private(set) var lastGetResult: String?
    @Published private(set) var isGettingToken = false
    @Published private(set) var invalidating: Field?
    @Published var alert: Alert?

    var canInvalidate: Bool { invalidate != nil }

    private let keychainManager: any KeychainManaging
    private let getTokenContainer: (AuthTokensCachePolicy) async throws -> TokenContainer
    private let invalidate: ((String) async throws -> Void)?
    /// The Terminal command that deletes the VPN system extension's token from the System keychain, or `nil` to leave it out.
    let vpnExtensionTokenRemovalCommand: String?

    /// - Parameters:
    ///   - keychainManager: Reads and deletes the subscription token keychain items.
    ///   - getTokenContainer: Gets the token through the subscription manager with the given policy.
    ///   - invalidate: Invalidates the given refresh token on the server. Nil outside staging.
    ///   - vpnSystemExtensionBundleID: The bundle ID of the VPN system extension, used to build the command that deletes its token,
    ///     or `nil` when the VPN doesn't run as a system extension.
    public init(keychainManager: any KeychainManaging,
                getTokenContainer: @escaping (AuthTokensCachePolicy) async throws -> TokenContainer,
                invalidate: ((String) async throws -> Void)?,
                vpnSystemExtensionBundleID: String? = nil) {
        self.keychainManager = keychainManager
        self.getTokenContainer = getTokenContainer
        self.invalidate = invalidate
        self.vpnExtensionTokenRemovalCommand = vpnSystemExtensionBundleID.map(Self.vpnExtensionTokenRemovalCommand(bundleID:))
        reload()
    }

    func invalidateRefreshToken(_ field: Field) async {
        guard let invalidate, case .found(let container) = read(field) else { return }
        invalidating = field
        defer {
            invalidating = nil
            reload()
        }
        do {
            try await invalidate(container.refreshToken)
            alert = Alert(title: "Token invalidated",
                          message: "The server invalidated the stored \(field.rawValue) refresh token. The token stays in the keychain.")
        } catch {
            alert = Alert(title: "Invalidation failed", message: String(describing: error))
        }
    }

    func getToken(policy: AuthTokensCachePolicy) async {
        isGettingToken = true
        defer {
            isGettingToken = false
            reload()
        }
        let time = Date().formatted(date: .omitted, time: .standard)
        do {
            let container = try await getTokenContainer(policy)
            lastGetResult = "\(policy.description) succeeded at \(time), refresh token issued \(container.decodedRefreshToken.issuedAtDate.formatted(date: .omitted, time: .standard))"
        } catch {
            lastGetResult = "\(policy.description) failed at \(time): \(String(describing: error))"
        }
    }

    func reload() {
        tokens = Field.allCases.map { Token(field: $0, state: read($0)) }
    }

    /// Builds the `security` command that deletes the token the VPN system extension with the given bundle ID stores in the System keychain.
    static func vpnExtensionTokenRemovalCommand(bundleID: String) -> String {
        "sudo security delete-generic-password -s '\(bundleID).authTokenContainer' -a '\(bundleID).tokenContainer' /Library/Keychains/System.keychain"
    }

    func copyVPNExtensionTokenRemovalCommand() {
        guard let vpnExtensionTokenRemovalCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(vpnExtensionTokenRemovalCommand, forType: .string)
    }

    func remove(_ field: Field) {
        do {
            try keychainManager.deleteItem(forKey: field.keyValue)
        } catch {
            alert = Alert(title: "Error", message: "Failed to remove \(field.rawValue): \(error)")
        }
        reload()
    }

    private func read(_ field: Field) -> TokenState {
        do {
            guard let data = try keychainManager.retrieveData(forKey: field.keyValue) else { return .missing }
            guard let container = try? JSONDecoder().decode(TokenContainer.self, from: data) else { return .undecodable }
            return .found(container)
        } catch {
            return .readFailed(error)
        }
    }
}

/// Shows the main and backup subscription tokens stored in the keychain, and lets the user get, fork or remove them.
public struct SubscriptionTokensDebugView: View {

    @ObservedObject var model: SubscriptionTokensDebugViewModel
    @State private var pendingRemoval: SubscriptionTokensDebugViewModel.Field?
    @State private var pendingInvalidation: SubscriptionTokensDebugViewModel.Field?

    public init(model: SubscriptionTokensDebugViewModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(verbatim: "Tokens").font(.title2.bold())
                    Spacer()
                    Button("Reload") { model.reload() }
                }

                getTokenSection

                ForEach(model.tokens) { token in
                    tokenSection(token)
                }

                if let command = model.vpnExtensionTokenRemovalCommand {
                    vpnExtensionTokenSection(command: command)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 560)
        .confirmationDialog("Remove the \(pendingRemoval.map(title(for:)) ?? "") from the keychain?",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let pendingRemoval { model.remove(pendingRemoval) }
            }
        }
        .confirmationDialog("Invalidate the \(pendingInvalidation.map(title(for:)) ?? "") refresh token on the server?",
                            isPresented: Binding(get: { pendingInvalidation != nil }, set: { if !$0 { pendingInvalidation = nil } }),
                            titleVisibility: .visible) {
            Button("Invalidate", role: .destructive) {
                if let pendingInvalidation { Task { await model.invalidateRefreshToken(pendingInvalidation) } }
            }
        }
        .alert(model.alert?.title ?? "", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert?.message ?? "")
        }
    }

    private var getTokenSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Local") { Task { await model.getToken(policy: .local) } }
                    Button("Local Valid (refresh if expired)") { Task { await model.getToken(policy: .localValid) } }
                    Button("Force Refresh") { Task { await model.getToken(policy: .localForceRefresh) } }
                }
                .disabled(model.isGettingToken)
                if model.isGettingToken {
                    SwiftUI.ProgressView().controlSize(.small)
                } else if let lastGetResult = model.lastGetResult {
                    Text(lastGetResult).font(.footnote.monospaced()).textSelection(.enabled)
                }
                Text(verbatim: "Runs SubscriptionManager.getTokenContainer, including recovery and sign-out when the refresh is rejected.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text(verbatim: "Get Token").font(.headline)
        }
    }

    private func tokenSection(_ token: SubscriptionTokensDebugViewModel.Token) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                details(for: token.state)
                HStack {
                    if model.invalidating == token.field {
                        SwiftUI.ProgressView().controlSize(.small)
                    } else {
                        Button("Invalidate Refresh Token", role: .destructive) {
                            pendingInvalidation = token.field
                        }
                        .disabled(!model.canInvalidate || !isFound(token.state) || model.invalidating != nil)
                    }
                    Button("Remove From Keychain", role: .destructive) {
                        pendingRemoval = token.field
                    }
                    .disabled(isMissing(token.state))
                }
                if !model.canInvalidate {
                    Text(verbatim: "Invalidating works only on the staging environment.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text(title(for: token.field)).font(.headline)
        }
    }

    private func vpnExtensionTokenSection(command: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "The VPN system extension keeps its own copy of the token in the System keychain. Run this in Terminal to delete it:")
                Text(command)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                Button("Copy") { model.copyVPNExtensionTokenRemovalCommand() }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text(verbatim: "VPN Extension Token").font(.headline)
        }
    }

    @ViewBuilder
    private func details(for state: SubscriptionTokensDebugViewModel.TokenState) -> some View {
        switch state {
        case .found(let container):
            row("Account", container.decodedAccessToken.externalID)
            row("Access token expires", dateText(container.decodedAccessToken.expirationDate))
            row("Refresh token issued", dateText(container.decodedRefreshToken.issuedAtDate))
            row("Refresh token expires", dateText(container.decodedRefreshToken.expirationDate))
        case .missing:
            Text(verbatim: "Not stored").foregroundColor(.secondary)
        case .undecodable:
            Text(verbatim: "Stored but can't be decoded").foregroundColor(.red)
        case .readFailed(let error):
            Text(verbatim: "Read failed: \(String(describing: error))").foregroundColor(.red)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.footnote.monospaced()).textSelection(.enabled)
        }
    }

    private func dateText(_ date: Date) -> String {
        let relative = RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        return "\(date.formatted(date: .abbreviated, time: .standard)) (\(relative))"
    }

    private func title(for field: SubscriptionTokensDebugViewModel.Field) -> String {
        switch field {
        case .tokenContainer: return "Main Token"
        case .backupTokenContainer: return "Backup Token"
        }
    }

    private func isFound(_ state: SubscriptionTokensDebugViewModel.TokenState) -> Bool {
        if case .found = state { return true }
        return false
    }

    private func isMissing(_ state: SubscriptionTokensDebugViewModel.TokenState) -> Bool {
        if case .missing = state { return true }
        return false
    }
}
