//
//  FireModeEmptyStateView.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI

struct FireModeEmptyStateView: View {
    
    // MARK: - Types

    typealias NewFireTabBlock =  () -> Void
    
    enum ViewType {
        case tab
        case tabSwitcher(onNewFireTab: NewFireTabBlock)
        
        var title: String {
            switch self {
            case .tab:
                return UserText.fireTabEmptyStateTitle
            case .tabSwitcher:
                return UserText.fireModeEmptyStateTitle
            }
        }
    }

    // MARK: - Variables

    private let type: ViewType
    private let escapeHatch: EscapeHatchModel?
    private let onEscapeHatchTap: (() -> Void)?

    private var onNewFireTab: NewFireTabBlock? {
        if case .tabSwitcher(let onNewFireTab) = type {
            return onNewFireTab
        }
        return nil
    }

    // MARK: - Initializer
    
    init(type: ViewType,
         escapeHatch: EscapeHatchModel? = nil,
         onEscapeHatchTap: (() -> Void)? = nil) {
        self.type = type
        self.escapeHatch = escapeHatch
        self.onEscapeHatchTap = onEscapeHatchTap
    }
    
    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Constants.mainSectionSpacing) {
                escapeHatchSection
                headerSection
                contentCard
            }
            .padding(.top, Constants.mainTopPadding)
            .padding(.horizontal, Constants.mainHorizontalPadding)
            .frame(maxWidth: Constants.maxViewWidth)
        }
        .modifier(ScrollBounceBehaviorModifier())
    }

    // MARK: - Escape Hatch

    @ViewBuilder
    private var escapeHatchSection: some View {
        if let escapeHatch, let onEscapeHatchTap {
            ReturnToTabCard(model: escapeHatch, onTap: onEscapeHatchTap)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Constants.headerSectionSpacing) {
            Image(uiImage: DesignSystemImages.Color.Size96.fireTab)

            Text(type.title)
                .daxHeadline()
                .foregroundColor(Color(designSystemColor: .textPrimary))
        }
    }

    // MARK: - Content Card

    private var contentCard: some View {
        VStack(spacing: Constants.cardContentSpacing) {
            bulletPoints
            separator
            infoFooter
            newFireTabButton
        }
        .padding(Constants.cardPadding)
        .background(Color(designSystemColor: .surface))
        .clipShape(RoundedRectangle(cornerRadius: Constants.cardCornerRadius))
    }

    // MARK: - Bullet Points

    private var bulletPoints: some View {
        HStack {
            VStack(alignment: .leading, spacing: Constants.bulletSpacing) {
                bulletRow(icon: DesignSystemImages.Glyphs.Size16.history,
                          text: UserText.fireModeEmptyStateBulletHistory)
                bulletRow(icon: DesignSystemImages.Glyphs.Size16.multipleAccounts,
                          text: UserText.fireModeEmptyStateBulletAccount)
                bulletRow(icon: DesignSystemImages.Glyphs.Size16.searchGlobe,
                          text: UserText.fireModeEmptyStateBulletTroubleshoot)
            }
            Spacer()
        }
    }

    private func bulletRow(icon: UIImage, text: String) -> some View {
        HStack(alignment: .top, spacing: Constants.iconTextSpacing) {
            Image(uiImage: icon)
                .padding(.top, Constants.iconTopPadding)
                .foregroundColor(Color(designSystemColor: .icons))
            Text(text)
                .daxSubheadRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))
        }
    }

    // MARK: - Separator

    private var separator: some View {
        Color(designSystemColor: .lines)
            .frame(height: Constants.separatorHeight)
    }

    // MARK: - Info Footer

    private var infoFooter: some View {
        HStack(alignment: .top, spacing: Constants.iconTextSpacing) {
            Image(uiImage: DesignSystemImages.Glyphs.Size16.infoSolid)
                .padding(.top, Constants.iconTopPadding)
                .foregroundColor(Color(designSystemColor: .iconsTertiary))
            Text(UserText.fireModeEmptyStateDescription)
                .daxFootnoteRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))
            Spacer()
        }
    }

    // MARK: - New Fire Tab Button

    @ViewBuilder
    private var newFireTabButton: some View {
        if let onNewFireTab {
            Button(action: onNewFireTab) {
                HStack(spacing: Constants.iconTextSpacing) {
                    Image(uiImage: DesignSystemImages.Glyphs.Size16.add)
                    Text(UserText.fireModeEmptyStateNewFireTab)
                        .daxButton()
                }
                .foregroundColor(Color(designSystemColor: .accentContentPrimary))
                .frame(height: Constants.buttonHeight)
                .padding(.horizontal, Constants.buttonHorizontalPadding)
                .background(Color(singleUseColor: .fireModeAccent))
                .clipShape(RoundedRectangle(cornerRadius: Constants.buttonCornerRadius))
            }
        }
    }

    // MARK: - Constants

    enum Constants {
        static let maxViewWidth: CGFloat = 552
        static let mainSectionSpacing: CGFloat = 16
        static let mainTopPadding: CGFloat = 24
        static let mainHorizontalPadding: CGFloat = 24
        
        static let headerSectionSpacing: CGFloat = 0

        static let cardContentSpacing: CGFloat = 24
        static let cardPadding: CGFloat = 24
        static let cardCornerRadius: CGFloat = 16

        static let bulletSpacing: CGFloat = 12
        static let iconTextSpacing: CGFloat = 8
        static let iconTopPadding: CGFloat = 2
        static let separatorHeight: CGFloat = 1

        static let buttonHeight: CGFloat = 40
        static let buttonHorizontalPadding: CGFloat = 16
        static let buttonCornerRadius: CGFloat = 12
    }
}
