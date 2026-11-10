//
//  SubscriptionTokensDebugView.swift
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

import SwiftUI
import Subscription
import Networking

/// Reads and deletes the subscription token keychain items directly, bypassing the token storage, to simulate lost tokens,
/// and gets the token through the subscription manager to run its refresh and recovery flows.
@MainActor
final class SubscriptionTokensDebugViewModel: ObservableObject {

    typealias Field = SubscriptionTokenKeychainStorage.SubscriptionKeychainField

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

    @Published private(set) var tokens: [Token] = []
    @Published private(set) var lastGetResult: String?
    @Published private(set) var isGettingToken = false
    @Published private(set) var forking: Field?
    @Published var alert: (title: String, message: String)?

    private let keychainManager: any KeychainManaging
    private let getTokenContainer: (AuthTokensCachePolicy) async throws -> TokenContainer
    private let fork: (TokenContainer) async throws -> TokenContainer

    /// - Parameters:
    ///   - getTokenContainer: Gets the token through the subscription manager with the given policy.
    ///   - fork: Spends the refresh token of the given container once and returns the new pair, without storing anything.
    init(keychainManager: any KeychainManaging,
         getTokenContainer: @escaping (AuthTokensCachePolicy) async throws -> TokenContainer,
         fork: @escaping (TokenContainer) async throws -> TokenContainer) {
        self.keychainManager = keychainManager
        self.getTokenContainer = getTokenContainer
        self.fork = fork
        reload()
    }

    func forceFork(_ field: Field) async {
        guard case .found(let container) = read(field) else { return }
        forking = field
        defer {
            forking = nil
            reload()
        }
        do {
            let minted = try await fork(container)
            alert = ("Fork succeeded",
                     """
                     Spent the stored \(field.rawValue) refresh token and discarded the new pair.
                     New refresh token issued \(minted.decodedRefreshToken.issuedAtDate.formatted(date: .omitted, time: .standard)), \
                     expires \(minted.decodedRefreshToken.expirationDate.formatted(date: .abbreviated, time: .standard)).
                     """)
        } catch {
            alert = ("Fork failed", String(describing: error))
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

    func remove(_ field: Field) {
        do {
            try keychainManager.deleteItem(forKey: field.keyValue)
        } catch {
            alert = ("Error", "Failed to remove \(field.rawValue): \(error)")
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

struct SubscriptionTokensDebugView: View {

    @ObservedObject var model: SubscriptionTokensDebugViewModel
    @State private var pendingRemoval: SubscriptionTokensDebugViewModel.Field?

    var body: some View {
        List {
            Section {
                Button("Local") { Task { await model.getToken(policy: .local) } }
                Button("Local Valid (refresh if expired)") { Task { await model.getToken(policy: .localValid) } }
                Button("Force Refresh") { Task { await model.getToken(policy: .localForceRefresh) } }
                if model.isGettingToken {
                    SwiftUI.ProgressView()
                } else if let lastGetResult = model.lastGetResult {
                    Text(lastGetResult).font(.footnote.monospaced()).textSelection(.enabled)
                }
            } header: {
                Text("Get Token")
            } footer: {
                Text("Runs SubscriptionManager.getTokenContainer, including recovery and sign-out when the refresh is rejected.")
            }
            .disabled(model.isGettingToken)

            ForEach(model.tokens) { token in
                Section(title(for: token.field)) {
                    details(for: token.state)
                    if model.forking == token.field {
                        SwiftUI.ProgressView()
                    } else {
                        Button("Force Fork (spend refresh token)") {
                            Task { await model.forceFork(token.field) }
                        }
                        .disabled(!isFound(token.state) || model.forking != nil)
                    }
                    Button("Remove From Keychain", role: .destructive) {
                        pendingRemoval = token.field
                    }
                    .disabled(isMissing(token.state))
                }
            }
        }
        .navigationTitle("Tokens")
        .toolbar {
            Button("Reload") { model.reload() }
        }
        .confirmationDialog("Remove the \(pendingRemoval.map(title(for:)) ?? "") from the keychain?",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let pendingRemoval { model.remove(pendingRemoval) }
            }
        }
        .alert(model.alert?.title ?? "", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert?.message ?? "")
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
            Text("Not stored").foregroundColor(.secondary)
        case .undecodable:
            Text("Stored but can't be decoded").foregroundColor(.red)
        case .readFailed(let error):
            Text("Read failed: \(String(describing: error))").foregroundColor(.red)
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
