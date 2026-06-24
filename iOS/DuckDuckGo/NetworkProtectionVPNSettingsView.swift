//
//  NetworkProtectionVPNSettingsView.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Core
import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons
import UniformTypeIdentifiers
import VPN

struct NetworkProtectionVPNSettingsView: View {

    private static let supportInfoPasteboardExpirationInterval: TimeInterval = 10 * 60
    private static let supportInfoCopyConfirmationResetDelay: UInt64 = 2_000_000_000

    private enum CopySupportInfoState: Equatable {
        case idle
        case copying
        case copied
        case failed
    }

    @StateObject var viewModel = NetworkProtectionVPNSettingsViewModel()

    @State private var copySupportInfoState = CopySupportInfoState.idle

    private var showsCopyDiagnosticsButton: Bool {
        AppDependencyProvider.shared.featureFlagger.isFeatureOn(.vpnShowCopyDiagnosticsButton)
    }

    var body: some View {
        VStack {
            List {
                switch viewModel.viewKind {
                case .loading: EmptyView()
                case .unauthorized: notificationsUnauthorizedView
                case .authorized: notificationAuthorizedView
                }

                shortcutsView

                toggleSection(
                    text: UserText.netPExcludeLocalNetworksSettingTitle,
                    headerText: UserText.netPExcludeLocalNetworksSettingHeader,
                    footerText: UserText.netPExcludeLocalNetworksSettingFooter
                ) {
                    Toggle("", isOn: $viewModel.excludeLocalNetworks)
                }

                if viewModel.isExcludeCGNATAvailable {
                    toggleSection(
                        text: UserText.netPExcludeCGNATSettingTitle,
                        footerText: UserText.netPExcludeCGNATSettingFooter
                    ) {
                        Toggle("", isOn: $viewModel.excludeCGNAT)
                    }
                }

                if viewModel.isStrictRoutingAvailable {
                    toggleSection(
                        text: UserText.netPStrictRoutingSettingTitle,
                        footerText: UserText.netPStrictRoutingSettingFooter
                    ) {
                        Toggle("", isOn: $viewModel.enforceRoutes)
                    }
                }

                dnsSection()

                if showsCopyDiagnosticsButton {
                    diagnostics()
                }
            }
        }
        .applyInsetGroupedListStyle()
        .navigationTitle(UserText.netPVPNSettingsTitle).onAppear {
            Task {
                await viewModel.onViewAppeared()
            }
        }
    }

    func dnsSection() -> some View {
        Section {
            NavigationLink {
                NetworkProtectionDNSSettingsView()
            } label: {
                HStack {
                    Text(UserText.vpnSettingDNSServerTitle)
                        .daxBodyRegular()
                        .foregroundColor(.init(designSystemColor: .textPrimary))
                    Spacer()
                    Text(viewModel.dnsServers)
                        .daxBodyRegular()
                        .foregroundColor(.init(designSystemColor: .textSecondary))
                }
            }
        } header: {
            Text(UserText.vpnSettingDNSSectionHeader)
        } footer: {
            if viewModel.usesCustomDNS {
                Text(UserText.vpnSettingDNSSectionDisclaimer)
                    .foregroundColor(.init(designSystemColor: .textSecondary))
            } else {
                Text(UserText.netPSecureDNSSettingFooter)
                    .foregroundColor(.init(designSystemColor: .textSecondary))
            }
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    @ViewBuilder
    private func diagnostics() -> some View {
        Section {
            Button {
                Task {
                    await copyVPNSupportInfo()
                }
            } label: {
                HStack {
                    copySupportInfoIcon
                    Text(copySupportInfoTitle)
                        .id(copySupportInfoTitle)
                    Spacer()
                }
                .daxBodyRegular()
                .foregroundColor(.init(designSystemColor: .textPrimary))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(copySupportInfoState != .idle)
            .animation(.easeInOut(duration: 0.18), value: copySupportInfoState)
        } header: {
            Text(UserText.netPStatusViewTroubleshootingSectionTitle).foregroundColor(.init(designSystemColor: .textSecondary))
        } footer: {
            Text(UserText.netPVPNSettingsCopyDiagnosticsCaption)
                .daxFootnoteRegular()
                .foregroundColor(.init(designSystemColor: .textSecondary))
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    private var copySupportInfoIcon: Image {
        switch copySupportInfoState {
        case .copied:
            return Image(uiImage: DesignSystemImages.Glyphs.Size24.check)
        case .failed:
            return Image(uiImage: DesignSystemImages.Glyphs.Size24.alertRecolorable)
        case .idle, .copying:
            return Image(uiImage: DesignSystemImages.Glyphs.Size24.copy)
        }
    }

    private var copySupportInfoTitle: String {
        switch copySupportInfoState {
        case .copied:
            return UserText.netPVPNSettingsCopyDiagnosticsCopiedToClipboard
        case .failed:
            return UserText.netPVPNSettingsCopyDiagnosticsFailedToCopyToClipboard
        case .idle, .copying:
            return UserText.netPVPNSettingsCopyDiagnostics
        }
    }

    @MainActor
    private func copyVPNSupportInfo() async {
        guard copySupportInfoState != .copying else {
            return
        }

        copySupportInfoState = .copying

        guard let metadata = await DefaultVPNMetadataCollector().collectMetadata(),
              let supportInfo = metadata.toPrettyPrintedJSON() else {
            showCopySupportInfoConfirmation(.failed)
            return
        }

        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: supportInfo]],
            options: [.expirationDate: Date().addingTimeInterval(Self.supportInfoPasteboardExpirationInterval)]
        )
        showCopySupportInfoConfirmation(.copied)
    }

    @MainActor
    private func showCopySupportInfoConfirmation(_ state: CopySupportInfoState) {
        withAnimation(.easeInOut(duration: 0.18)) {
            copySupportInfoState = state
        }

        Task {
            try? await Task.sleep(nanoseconds: Self.supportInfoCopyConfirmationResetDelay)

            guard copySupportInfoState == state else {
                return
            }

            withAnimation(.easeInOut(duration: 0.18)) {
                copySupportInfoState = .idle
            }
        }
    }

    @ViewBuilder
    func toggleSection(text: String, headerText: String? = nil, footerText: String, @ViewBuilder toggle: () -> some View) -> some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text)
                        .daxBodyRegular()
                        .foregroundColor(.init(designSystemColor: .textPrimary))
                        .layoutPriority(1)
                }

                toggle()
                    .toggleStyle(SwitchToggleStyle(tint: .init(designSystemColor: .accentPrimary)))
            }
        } header: {
            if let headerText {
                Text(headerText)
            }
        } footer: {
            Text(LocalizedStringKey(footerText))
                .foregroundColor(.init(designSystemColor: .textSecondary))
                .accentColor(Color(designSystemColor: .accentPrimary))
                .daxFootnoteRegular()
                .padding(.top, 6)
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    @ViewBuilder
    private var notificationsUnauthorizedView: some View {
        Section {
            Button(UserText.netPTurnOnNotificationsButtonTitle) {
                viewModel.turnOnNotifications()
            }
            .foregroundColor(.init(designSystemColor: .accentPrimary))
        } footer: {
            Text(UserText.netPTurnOnNotificationsSectionFooter)
                .foregroundColor(.init(designSystemColor: .textSecondary))
                .daxFootnoteRegular()
                .padding(.top, 6)
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    @ViewBuilder
    private var notificationAuthorizedView: some View {
        Section {
            Toggle(
                UserText.netPVPNAlertsToggleTitle,
                isOn: Binding(
                    get: { viewModel.alertsEnabled },
                    set: viewModel.didToggleAlerts(to:)
                )
            )
            .toggleStyle(SwitchToggleStyle(tint: .init(designSystemColor: .accentPrimary)))
        } header: {
            Text(UserText.netPVPNAlertsSectionHeader)
        } footer: {
            Text(UserText.netPVPNAlertsToggleSectionFooter)
                .foregroundColor(.init(designSystemColor: .textSecondary))
                .daxFootnoteRegular()
                .padding(.top, 6)
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    @ViewBuilder
    private var shortcutsView: some View {
        // Widget only available for iOS 17 and up
        if #available(iOS 17.0, *) {
            Section {
                NavigationLink {
                    WidgetEducationView.vpn
                } label: {
                    Label {
                        Text(UserText.vpnSettingsAddWidget)
                    } icon: {
                        Image(uiImage: DesignSystemImages.Color.Size24.addWidget)
                            .frame(width: 24, height: 24)
                    }.daxBodyRegular()
                }

                if #available(iOS 18.0, *) {
                    NavigationLink {
                        ControlCenterWidgetEducationView(navBarTitle: "Add DuckDuckGo VPN Shortcut to Your Control Center",
                                                         widget: .vpnToggle)
                    } label: {
                        Label {
                            Text(UserText.vpnSettingsAddControlCenterWidget)
                        } icon: {
                            Image(uiImage: DesignSystemImages.Color.Size24.settings)
                                .frame(width: 24, height: 24)
                        }.daxBodyRegular()
                    }
                }

                NavigationLink {
                    SiriEducationView()
                } label: {
                    Label {
                        Text(UserText.vpnSettingsControlWithSiri)
                    } icon: {
                        Image(uiImage: DesignSystemImages.Color.Size24.askSiri)
                            .frame(width: 24, height: 24)
                    }.daxBodyRegular()
                }
            } header: {
                Text(UserText.netPVPNShortcutsSectionHeader)
            }
            .listRowBackground(Color(designSystemColor: .surface))
        }
    }
}

@available(iOS 17.0, *)
private extension WidgetEducationView {

    static var vpn: Self {
        WidgetEducationView(
            navBarTitle: UserText.settingsAddVPNWidget,
            thirdParagraphText: UserText.addVPNWidgetSettingsThirdParagraph,
            thirdParagraphDetail: .image(
                Image(.widgetEducationVPNWidgetExample),
                maxWidth: 164,
                horizontalOffset: -7,
                dropsShadow: true
            )
        )
    }
}
