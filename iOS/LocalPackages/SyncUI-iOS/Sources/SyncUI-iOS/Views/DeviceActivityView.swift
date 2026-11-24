//
//  DeviceActivityView.swift
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
import SwiftUI

struct DeviceActivityView: View {

    @ObservedObject var model: DeviceActivityViewModel
    private static let relativeDateFormatter = RelativeDateTimeFormatter()

    private enum RelativeTime {
        static let minute: TimeInterval = 60
        static let hour = 60 * minute
        static let day = 24 * hour
        static let month = 30 * day
        static let year = 365 * day
    }

    var body: some View {
        List {
            if model.isLoading && model.entries.isEmpty {
                Section {
                    ProgressView().frame(maxWidth: .infinity)
                        .listRowBackground(Color(designSystemColor: .background))
                } header: {
                    intro
                }
            } else if model.entries.isEmpty && model.hasLoaded && model.error == nil {
                Section {
                    Text(UserText.deviceActivityEmpty)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .listRowBackground(Color(designSystemColor: .surfaceTertiary))
                } header: {
                    intro
                }
            } else {
                ForEach(model.entries) { entry in
                    Section {
                        activityRow(entry)
                            .task { await model.loadOlderIfNeeded(after: entry.id) }
                    } header: {
                        if entry.id == model.entries.first?.id {
                            intro
                        }
                    }
                }

                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                        .listRowBackground(Color(designSystemColor: .background))
                }
            }

            if model.error != nil {
                Section {
                    Label {
                        Text(UserText.deviceActivityLoadError)
                            .daxBodyRegular()
                    } icon: {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.infoSolid)
                    }
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .listRowBackground(Color(designSystemColor: .surfaceTertiary))
                } header: {
                    if model.entries.isEmpty {
                        intro
                    }
                }
            }
        }
        .navigationTitle(UserText.deviceActivityTitle)
        .navigationBarTitleDisplayMode(.inline)
        .applyListStyle()
        .task { await model.loadIfNeeded() }
        .task(id: model.entries.isEmpty) { await model.markAsReviewedAfterDelay() }
        .onDisappear { model.cancelAndClear() }
    }

    private var intro: some View {
        Text(UserText.deviceActivityIntro)
            .daxBodyRegular()
            .textCase(nil)
            .multilineTextAlignment(.center)
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
            .padding(.bottom, 24)
            .listRowInsets(EdgeInsets())
    }

    static func relativeDateString(for date: Date, relativeTo now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        let components: DateComponents
        switch seconds {
        case ..<RelativeTime.minute:
            return UserText.deviceActivityJustNow
        case ..<RelativeTime.hour:
            components = DateComponents(minute: -Int(seconds / RelativeTime.minute))
        case ..<RelativeTime.day:
            components = DateComponents(hour: -Int(seconds / RelativeTime.hour))
        case ..<RelativeTime.month:
            components = DateComponents(day: -Int(seconds / RelativeTime.day))
        case ..<RelativeTime.year:
            components = DateComponents(month: -Int(seconds / RelativeTime.month))
        default:
            components = DateComponents(year: -Int(seconds / RelativeTime.year))
        }
        return relativeDateFormatter.localizedString(from: components)
    }

    private func activityRow(_ entry: DeviceActivityEntry) -> some View {
        let backgroundColor = model.isSeen(entry) ? Color(designSystemColor: .surfaceTertiary) : Color(designSystemColor: .accentAltPrimary)
        return HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                SyncDeviceTypeImage(device: .init(id: entry.id,
                                                  name: entry.deviceName,
                                                  type: entry.deviceType,
                                                  credentialId: entry.credentialId,
                                                  isThisDevice: false))
                if entry.action == .removed {
                    Circle().fill(Color(designSystemColor: .statusRed))
                        .frame(width: 9, height: 9)
                        .background(
                            Circle().fill(backgroundColor)
                                .padding(-2)
                                .animation(.easeInOut(duration: 1.0), value: model.isSeen(entry))
                        )
                        .offset(x: -2, y: -2)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.relativeDateString(for: entry.date, relativeTo: Date()))
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Text(entry.deviceName)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
            Spacer(minLength: 8)
            Text(entry.action == .synced ? UserText.deviceActivitySynced : UserText.deviceActivityRemoved)
                .daxFootnoteRegular()
                .foregroundColor(Color(designSystemColor: .textSecondary))
        }
        .padding(.vertical, 4)
        .listRowBackground(
            backgroundColor
                .animation(.easeInOut(duration: 1.0), value: model.isSeen(entry))
        )
        .accessibilityElement(children: .combine)
    }
}
