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
import DuckUI
import SwiftUI

struct DeviceActivityView: View {

    @Environment(\.dismiss) private var dismiss
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
            Text(UserText.deviceActivityIntro)
                .daxBodyRegular()
                .multilineTextAlignment(.center)
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .frame(maxWidth: .infinity)
                .listRowBackground(Color(designSystemColor: .background))
                .listRowSeparator(.hidden)

            if model.isLoading && model.entries.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
                    .listRowBackground(Color(designSystemColor: .background))
            } else if model.entries.isEmpty && model.hasLoaded {
                Section {
                    Text(UserText.deviceActivityEmpty)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .listRowBackground(Color(designSystemColor: .surfaceTertiary))
                }
            } else {
                ForEach(model.entries) { entry in
                    Section {
                        activityRow(entry)
                            .task { await model.loadOlderIfNeeded(after: entry.id) }
                    }
                }

                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                        .listRowBackground(Color(designSystemColor: .background))
                }
            }
        }
        .navigationTitle(UserText.deviceActivityTitle)
        .navigationBarTitleDisplayMode(.inline)
        .applyListStyle()
        .alert(isPresented: Binding(get: { model.error != nil }, set: { isPresented in
            if !isPresented { model.dismissError() }
        })) {
            Alert(title: Text(UserText.deviceActivityLoadError),
                  message: Text(UserText.deviceActivityLoadErrorMessage),
                  primaryButton: .default(Text(UserText.deviceActivityRetry)) {
                      Task { await model.retry() }
                  },
                  secondaryButton: .cancel(Text(model.entries.isEmpty ? UserText.backButton : UserText.cancelButton)) {
                      if model.entries.isEmpty { dismiss() }
                  })
        }
        .task { await model.loadIfNeeded() }
        .task(id: model.entries.isEmpty) { await model.markAsReviewedAfterDelay() }
        .onDisappear { model.cancelAndClear() }
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
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                SyncDeviceTypeImage(device: .init(id: entry.id,
                                                  name: entry.deviceName,
                                                  type: entry.deviceType,
                                                  credentialId: entry.credentialId,
                                                  isThisDevice: false))
                if entry.action == .removed {
                    Circle().fill(Color(designSystemColor: .statusRed))
                        .frame(width: 8, height: 8)
                        .offset(x: 1, y: 1)
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
            (model.isSeen(entry) ? Color(designSystemColor: .surfaceTertiary) : Color(designSystemColor: .accentAltPrimary))
                .animation(.easeInOut(duration: 1.0), value: model.isSeen(entry))
        )
        .accessibilityElement(children: .combine)
    }
}
