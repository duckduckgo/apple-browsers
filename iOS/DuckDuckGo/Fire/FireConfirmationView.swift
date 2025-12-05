//
//  FireConfirmationView.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import DesignResourcesKit
import DesignResourcesKitIcons
import Core
import DuckUI

struct FireConfirmationView: View {
    
    @ObservedObject var viewModel: FireConfirmationViewModel
    
    var body: some View {
        VStack(spacing: Constants.mainSectionSpacing) {
            headerSection
            optionsList
            footerButtons
        }
        .padding(.horizontal, Constants.mainViewPadding.leading)
        .padding(.vertical, Constants.mainViewPadding.top)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(designSystemColor: .backgroundTertiary))
    }
    
    /// Header with title and large icon
    private var headerSection: some View {
        VStack(spacing: Constants.headerSectionSpacing) {
            Image(uiImage: DesignSystemImages.Color.Size72.fire)
                .resizable()
                .frame(width: Constants.headerIconSize, height: Constants.headerIconSize)
            
            Text(UserText.fireConfirmationTitle)
                .font(Constants.headerTitleFont)
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private var optionsList: some View {
        VStack(spacing: Constants.optionsListSpacing) {
            ToggleRow(
                icon: DesignSystemImages.Glyphs.Size24.tabsMobile,
                title: UserText.fireConfirmationTabsTitle,
                subtitle: viewModel.clearTabsSubtitle(),
                isOn: $viewModel.clearTabs
            )
            .accessibilityIdentifier("fire.confirmation.toggle.tabs")
            
            shiftedDivider
            
            ToggleRow(
                icon: DesignSystemImages.Glyphs.Size24.cookie,
                title: UserText.fireConfirmationDataTitle,
                subtitle: viewModel.clearDataSubtitle(),
                isOn: $viewModel.clearData
            )
            .accessibilityIdentifier("fire.confirmation.toggle.data")
            
            if viewModel.showAIChatsOption {
                shiftedDivider
                
                ToggleRow(
                    icon: DesignSystemImages.Glyphs.Size24.aiChat,
                    title: UserText.fireConfirmationAIChatsTitle,
                    subtitle: viewModel.clearAIChatsSubtitle(),
                    isOn: $viewModel.clearAIChats
                )
                .accessibilityIdentifier("fire.confirmation.toggle.aichats")
            }
        }
        .background(Color(designSystemColor: .surface))
        .cornerRadius(Constants.optionsListCornerRadius)
    }
    
    private var shiftedDivider: some View {
        Rectangle()
            .fill(Color(designSystemColor: .lines))
            .frame(height: Constants.dividerHeight)
            .padding(.leading, Constants.dividerLeadingSpace)
    }
    
    private var footerButtons: some View {
        VStack(spacing: Constants.footerButtonsSpacing) {
            // Delete button
            Button(action: {
                viewModel.confirm()
            }) {
                Text(UserText.actionDelete)
                    .font(Constants.footerButtonFont)
                    .foregroundColor(Color(designSystemColor: .buttonsWhite))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Constants.footerButtonMinHeight)
                    .background(Color(designSystemColor: .destructivePrimary))
                    .cornerRadius(Constants.footerButtonCornerRadius)
            }
            .accessibilityIdentifier("fire.confirmation.button.delete")
            // TODO: - Create a PrimaryDestructive button style and use it here. Pending on design.
            
            // Cancel button
            Button(action: {
                viewModel.cancel()
            }) {
                Text(UserText.actionCancel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GhostAltButtonStyle())
            .accessibilityIdentifier("fire.confirmation.button.cancel")
        }
    }
}

private extension FireConfirmationView {
    enum Constants {
        // Main View
        static let mainSectionSpacing: CGFloat = 24
        static let mainViewPadding: EdgeInsets = .init(top: 24, leading: 32, bottom: 24, trailing: 32)
        
        // Header section
        static let headerSectionSpacing: CGFloat = 8
        static let headerIconSize: CGFloat = 96
        static let headerTitleFont: Font = .system(size: 20, weight: .bold)
        
        // Options List
        static let optionsListSpacing: CGFloat = 0
        static let optionsListCornerRadius: CGFloat = 10
        static let dividerHeight: CGFloat = 0.5
        static let dividerLeadingSpace: CGFloat = 52
        
        // Footer Buttons
        static let footerButtonsSpacing: CGFloat = 8
        static let footerButtonFont: Font = .system(size: 15, weight: .semibold, design: .default)
        static let footerButtonMinHeight: CGFloat = 50
        static let footerButtonCornerRadius: CGFloat = 12
    }
}

private struct ToggleRow: View {
    let icon: DesignSystemImage
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: Constants.horizontalSpacing) {
            // Icon
            Image(uiImage: icon)
                .padding(.leading, Constants.iconPadding.leading)
                .padding(.trailing, Constants.iconPadding.trailing)
            
            // Text content
            VStack(alignment: .leading, spacing: Constants.titlesVerticalSpacing) {
                Text(title)
                    .font(Constants.titleFont)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(subtitle)
                    .font(Constants.subtitleFont)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Constants.titlesVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Toggle
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .padding(.trailing, Constants.toggleTrailingPadding)
                .tint(Color(designSystemColor: .accent))
        }
    }
    
    enum Constants {
        static let horizontalSpacing: CGFloat = 0
        static let iconPadding: EdgeInsets = .init(top: 0, leading: 16, bottom: 0, trailing: 12)
        static let titlesVerticalSpacing: CGFloat = 2
        static let titleFont: Font = .system(size: 16, weight: .regular, design: .default)
        static let subtitleFont: Font = .system(size: 13, weight: .regular, design: .default)
        static let titlesVerticalPadding: CGFloat = 10.5
        static let toggleTrailingPadding: CGFloat = 16
    }
}

#Preview {
    let viewModel = FireConfirmationViewModel(onConfirm: {}, onCancel: {})
    return FireConfirmationView(viewModel: viewModel)
}
