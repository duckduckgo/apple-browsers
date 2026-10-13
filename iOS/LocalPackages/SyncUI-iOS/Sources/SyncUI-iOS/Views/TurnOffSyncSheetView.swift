//
//  TurnOffSyncSheetView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import MetricBuilder
import SwiftUI

#if DEBUG
import PreviewSnapshots
import UIComponents
#endif

struct TurnOffSyncSheetView: View {

    private enum Constants {
        static let horizontalPadding: CGFloat = 24
        static let toolbarPadding: CGFloat = 12
        static let closeButtonIconPadding: CGFloat = 8
        static let headerSpacing: CGFloat = 4
        static let sectionSpacing: CGFloat = 32
        static let rowHeight: CGFloat = 52
        static let rowHorizontalInset: CGFloat = 16
        static let iconSpacing: CGFloat = 8
        static let iconSize: CGFloat = 24
        static let footerTopSpacing: CGFloat = 8
        static let sectionHeaderTopSpacing: CGFloat = 24
        static let sectionHeaderBottomSpacing: CGFloat = 6
    }

    @ObservedObject var model: SyncSettingsViewModel

    @State private var isDeleteServerDataSelected: Bool
    @State private var isRemoveDeviceConfirmationVisible = false
    @State private var isDeleteServerDataConfirmationVisible = false
    @State private var contentHeight: CGFloat = 0
    @State private var actionHeight: CGFloat = 0

    init(model: SyncSettingsViewModel, isDeleteServerDataSelected: Bool = false) {
        self.model = model
        _isDeleteServerDataSelected = State(initialValue: isDeleteServerDataSelected)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack {
                    toolbar
                    VStack {
                        header
                        deleteServerDataToggle
                            .padding(.top, Constants.sectionSpacing)
                        if isDeleteServerDataSelected {
                            devicesSection
                        }
                    }
                    .padding(.horizontal, Constants.horizontalPadding)
                }
                .background(HeightReader<ContentHeightKey>())
            }
            .onPreferenceChange(ContentHeightKey.self) { newValue in
                animateHeightChange(from: contentHeight) { contentHeight = newValue }
            }

            actionButton
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.top, Constants.sectionSpacing)
                .background(HeightReader<ActionHeightKey>())
                .onPreferenceChange(ActionHeightKey.self) { newValue in
                    animateHeightChange(from: actionHeight) { actionHeight = newValue }
                }
        }
        .background(Color(designSystemColor: .backgroundSheets).ignoresSafeArea())
        .fittedSheetDetent(height: contentHeight + actionHeight)
    }

    private func animateHeightChange(from currentHeight: CGFloat, _ update: () -> Void) {
        guard currentHeight > 0 else {
            update()
            return
        }
        withAnimation(.easeInOut(duration: 0.25), update)
    }

    private var toolbar: some View {
        HStack {
            Button {
                model.dismissTurnOffSyncSheet()
            } label: {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                    .padding(Constants.closeButtonIconPadding)
            }
            .buttonStyle(CloseButtonStyle())
            .accessibilityLabel(UserText.simplifiedScanCloseButton)
            Spacer()
        }
        .padding(Constants.toolbarPadding)
    }

    private var header: some View {
        VStack(spacing: Constants.headerSpacing) {
            Text(title)
                .daxHeadline()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .daxSubheadRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))
        }
        .padding(.horizontal)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var title: String {
        isDeleteServerDataSelected ? UserText.simplifiedTurnOffSyncSheetTitle : UserText.simplifiedRemoveDeviceConfirmTitle(thisDeviceName)
    }

    private var message: String {
        isDeleteServerDataSelected ? UserText.simplifiedTurnOffSyncSheetDeleteMessage : UserText.simplifiedManageDeviceRemoveFooter(thisDeviceName)
    }

    private var thisDeviceName: String {
        model.thisDeviceName ?? UIDevice.current.name
    }

    private var deleteServerDataToggle: some View {
        VStack(alignment: .leading, spacing: Constants.footerTopSpacing) {
            HStack(spacing: Constants.iconSpacing) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.trash)
                Toggle(UserText.simplifiedTurnOffSyncSheetDeleteToggle, isOn: $isDeleteServerDataSelected)
                    .daxBodyRegular()
                    .tint(Color(designSystemColor: .accentPrimary))
                    .disabled(model.isBusy)
                    .accessibility(identifier: "DeleteServerDataToggle")
            }
            .padding(.horizontal, Constants.rowHorizontalInset)
            .frame(minHeight: Constants.rowHeight)
            .background(cardBackground)

            Text(isDeleteServerDataSelected ? UserText.simplifiedTurnOffSyncSheetDeleteToggleOnFooter : UserText.simplifiedTurnOffSyncSheetDeleteToggleOffFooter)
                .daxFootnoteRegular()
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Constants.rowHorizontalInset)
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(UserText.simplifiedMyDevicesSectionHeader)
                .daxHeadline()
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .padding(.horizontal, Constants.rowHorizontalInset)
                .padding(.top, Constants.sectionHeaderTopSpacing)
                .padding(.bottom, Constants.sectionHeaderBottomSpacing)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(model.devices.enumerated()), id: \.element.id) { index, device in
                    if index > 0 {
                        Color(designSystemColor: .lines)
                            .frame(height: 1)
                            .padding(.leading, Constants.rowHorizontalInset + Constants.iconSize + Constants.iconSpacing)
                            .padding(.trailing, Constants.rowHorizontalInset)
                    }
                    deviceRow(device)
                }
            }
            .background(cardBackground)
        }
    }

    private func deviceRow(_ device: SyncSettingsViewModel.Device) -> some View {
        HStack(spacing: Constants.iconSpacing) {
            SyncDeviceTypeImage(device: device)
                .foregroundColor(Color(designSystemColor: .icons))
            Text(device.name)
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))
            Spacer()
            if device.isThisDevice {
                Text(UserText.syncedDevicesThisDeviceLabel)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
        }
        .padding(.horizontal, Constants.rowHorizontalInset)
        .frame(minHeight: Constants.rowHeight)
        .accessibilityElement(children: .combine)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: ContainerMetrics.cornerRadius, style: .continuous)
            .fill(Color(designSystemColor: .surfaceTertiary))
    }

    @ViewBuilder
    private var actionButton: some View {
        if isDeleteServerDataSelected {
            Button(UserText.simplifiedTurnOffSyncSheetDeleteButton) {
                model.turnOffSyncSheetDeleteServerDataTapped()
                isDeleteServerDataConfirmationVisible = true
            }
            .buttonStyle(PrimaryDestructiveButtonStyle(disabled: model.isBusy))
            .disabled(model.isBusy)
            .accessibility(identifier: "TurnOffAndDeleteServerDataButton")
            .alert(UserText.simplifiedDeleteServerDataConfirmTitle, isPresented: $isDeleteServerDataConfirmationVisible) {
                Button(UserText.cancelButton, role: .cancel) {
                    model.turnOffSyncSheetDeleteServerDataCancelled()
                }
                Button(UserText.simplifiedDeleteServerDataConfirmAction, role: .destructive) {
                    model.turnOffSyncSheetDeleteServerDataConfirmed()
                }
            } message: {
                Text(UserText.simplifiedTurnOffSyncSheetDeleteMessage)
            }
        } else {
            Button(UserText.removeDeviceButton) {
                model.turnOffSyncSheetRemoveDeviceTapped()
                isRemoveDeviceConfirmationVisible = true
            }
            .buttonStyle(SecondaryDestructiveButtonStyle(disabled: model.isBusy))
            .disabled(model.isBusy)
            .accessibility(identifier: "RemoveThisDeviceButton")
            .removeDeviceConfirmationAlert(isPresented: $isRemoveDeviceConfirmationVisible,
                                           deviceName: thisDeviceName,
                                           isImprovedPairingFlowEnabled: true) {
                model.turnOffSyncSheetRemoveDeviceConfirmed()
            }
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ActionHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct HeightReader<Key: PreferenceKey>: View where Key.Value == CGFloat {
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: Key.self, value: geometry.size.height)
        }
    }
}

private extension View {

    @ViewBuilder
    func fittedSheetDetent(height: CGFloat) -> some View {
        if #available(iOS 16.4, *) {
            presentationDetents(height > 0 ? [.height(height)] : [.medium])
                .presentationDragIndicator(.visible)
                .scrollBounceBehavior(.basedOnSize)
        } else if #available(iOS 16, *) {
            presentationDetents(height > 0 ? [.height(height)] : [.medium])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}

#if DEBUG
struct TurnOffSyncSheetView_Previews: PreviewProvider {

    enum State {
        case removeDevice
        case deleteServerData
    }

    static var previews: some View {
        snapshots.previews
    }

    static let snapshots = PreviewSnapshots<State>(
        configurations: [
            .init(name: "Remove Device", state: .removeDevice),
            .init(name: "Delete Server Data", state: .deleteServerData)
        ],
        configure: { state in
            TurnOffSyncSheetView(
                model: .preview(isSyncEnabled: true, devices: [.thisDevice, .desktop, .otherMobile]),
                isDeleteServerDataSelected: state == .deleteServerData
            )
            .applyRebranding()
        }
    )
}
#endif
