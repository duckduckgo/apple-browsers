//
//  SaveLoginDebugView.swift
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
import BrowserServicesKit
import Core

struct SaveLoginDebugView: View {

    @State private var selectedVariant: SaveLoginVariant?

    var body: some View {
        List {
            Section(header: Text(verbatim: "Variants")) {
                ForEach(SaveLoginVariant.allCases) { variant in
                    Button(variant.title) {
                        selectedVariant = variant
                    }
                }
            }
        }
        .navigationTitle("Save Login Previews")
        .applyBackground()
        .sheet(item: $selectedVariant) { variant in
            SaveLoginDebugSheet(variant: variant.layoutType, onDismiss: { selectedVariant = nil })
        }
    }
}

private enum SaveLoginVariant: String, CaseIterable, Identifiable {
    case newUser
    case newUserVariant1
    case newUserVariant2
    case newUserVariant3
    case saveLogin
    case savePassword
    case updateUsername
    case updatePassword

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newUser: return "New user (control)"
        case .newUserVariant1: return "New user (variant 1)"
        case .newUserVariant2: return "New user (variant 2)"
        case .newUserVariant3: return "New user (variant 3)"
        case .saveLogin: return "Save login"
        case .savePassword: return "Save password only"
        case .updateUsername: return "Update username"
        case .updatePassword: return "Update password"
        }
    }

    var layoutType: SaveLoginView.LayoutType {
        switch self {
        case .newUser: return .newUser
        case .newUserVariant1: return .newUserVariant1
        case .newUserVariant2: return .newUserVariant2
        case .newUserVariant3: return .newUserVariant3
        case .saveLogin: return .saveLogin
        case .savePassword: return .savePassword
        case .updateUsername: return .updateUsername
        case .updatePassword: return .updatePassword
        }
    }
}

private struct SaveLoginDebugSheet: View {

    let variant: SaveLoginView.LayoutType
    let onDismiss: () -> Void

    @StateObject private var viewModel = SaveLoginDebugSheetViewModel()
    @StateObject private var delegate = SaveLoginDebugDelegate()

    var body: some View {
        sheetContent
            .onAppear {
            guard viewModel.loginViewModel == nil else { return }
            delegate.onDismiss = onDismiss
            delegate.onHeightChange = { height in
                viewModel.contentHeight = height
            }
            let appSettings = AppDependencyProvider.shared.appSettings
            let featureFlagger = AppDependencyProvider.shared.featureFlagger
            let vm = SaveLoginViewModel(
                credentialManager: SaveLoginDebugMockManager(layoutType: variant),
                appSettings: appSettings,
                featureFlagger: featureFlagger,
                layoutType: variant
            )
            vm.delegate = delegate
            viewModel.loginViewModel = vm
        }
    }
    
    @ViewBuilder
    private var sheetContent: some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.height(viewModel.contentHeight)])
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if let loginViewModel = viewModel.loginViewModel {
            SaveLoginView(viewModel: loginViewModel)
        } else {
            SwiftUI.ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private final class SaveLoginDebugSheetViewModel: ObservableObject {
    @Published var loginViewModel: SaveLoginViewModel?
    @Published var contentHeight: CGFloat = 300
}

private final class SaveLoginDebugDelegate: NSObject, SaveLoginViewModelDelegate, ObservableObject {

    var onDismiss: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    func saveLoginViewModelDidSave(_ viewModel: SaveLoginViewModel) {
        DispatchQueue.main.async { [weak self] in
            self?.onDismiss?()
        }
    }

    func saveLoginViewModelDidCancel(_ viewModel: SaveLoginViewModel) {
        DispatchQueue.main.async { [weak self] in
            self?.onDismiss?()
        }
    }

    func saveLoginViewModelNeverPrompt(_ viewModel: SaveLoginViewModel) {
        DispatchQueue.main.async { [weak self] in
            self?.onDismiss?()
        }
    }

    func saveLoginViewModelConfirmKeepUsing(_ viewModel: SaveLoginViewModel) {
        DispatchQueue.main.async { [weak self] in
            self?.onDismiss?()
        }
    }

    func saveLoginViewModelDidResizeContent(_ viewModel: SaveLoginViewModel, contentHeight: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            self?.onHeightChange?(max(contentHeight, viewModel.minHeight))
        }
    }
}

private struct SaveLoginDebugMockManager: SaveAutofillLoginManagerProtocol {

    private let layoutType: SaveLoginView.LayoutType

    init(layoutType: SaveLoginView.LayoutType) {
        self.layoutType = layoutType
    }

    var username: String { "dax@duck.com" }
    var visiblePassword: String { "supersecurepasswordquack" }
    var isNewAccount: Bool { layoutType.isNewUserVariant || layoutType == .saveLogin }
    var accountDomain: String { "duck.com" }

    var isPasswordOnlyAccount: Bool {
        layoutType == .savePassword
    }

    var hasOtherCredentialsOnSameDomain: Bool { false }

    var hasSavedMatchingPasswordWithoutUsername: Bool {
        layoutType == .updateUsername
    }

    var hasSavedMatchingUsernameWithoutPassword: Bool { false }

    var hasSavedMatchingUsername: Bool {
        layoutType == .updatePassword
    }

    static func saveCredentials(_ credentials: SecureVaultModels.WebsiteCredentials, with factory: AutofillVaultFactory) throws -> Int64 {
        0
    }
}
