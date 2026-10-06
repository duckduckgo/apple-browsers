//
//  DownloadsList.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

struct DownloadsList: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var viewModel: DownloadsListViewModel
    @State var editMode: EditMode = .inactive
    @State private var selectedRowModelToCancel: OngoingDownloadRowViewModel?

    var body: some View {
        NavigationView {
            listOrEmptyState
                .navigationBarTitle(Text(UserText.downloadsScreenTitle), displayMode: .inline)
                .navigationBarItems(trailing: doneButton)
        }
        .navigationViewStyle(.stack)
        .alert(item: $selectedRowModelToCancel) { rowModel in
            makeCancelDownloadAlert(for: rowModel)
        }
    }

    @ViewBuilder
    private var doneButton: some View {
        if editMode == .inactive {
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            },
                   label: { Text(UserText.navigationTitleDone).foregroundColor(.barButton).bold() })
        }
    }
    
    @ViewBuilder
    private var listOrEmptyState: some View {
        if viewModel.sections.isEmpty {
            emptyState
        } else {
            if #available(iOS 26, *) {
                listWithBottomToolbarLiquidGlass
            } else {
                listWithBottomToolbar
            }
        }
    }
    
    private var emptyState: some View {
        VStack {
            Spacer()
                .frame(height: 32)
            Text(UserText.emptyDownloads)
                .font(Font(uiFont: Const.Font.emptyState))
                .foregroundColor(.emptyState)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.background)
        .edgesIgnoringSafeArea(.bottom)
    }

    @available(iOS 26, *)
    private var listWithBottomToolbarLiquidGlass: some View {
        listWithBackground.toolbar {
            if editMode == .active {
                ToolbarItem(placement: .bottomBar) {
                    deleteAllButton
                }
            }

            ToolbarSpacer(.flexible, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                editButton
            }
        }
    }

    @ViewBuilder
    private var listWithBottomToolbar: some View {
        listWithBackground.toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                toolbarButtons
            }
        }
    }

    @ViewBuilder
    private var listWithBackground: some View {
        if #available(iOS 16.0, *) {
            list
                .background(Color.background)
                .scrollContentBackground(.hidden)
        } else {
            list
        }
    }

    private var deleteAllButton: some View {
        Button {
            self.deleteAll()
        } label: {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.trash)
        }
        .buttonStyle(.plain)
    }

    private var editButton: some View {

        EditButton().environment(\.editMode, $editMode)
            .foregroundColor(.barButton)
            .buttonStyle(.plain)

    }

    @ViewBuilder
    private var toolbarButtons: some View {
        if editMode == .active {
            deleteAllButton
        }

        Spacer()

        editButton
    }

    private var list: some View {
        List {
            ForEach(viewModel.sections) { section in
                Section(header: Text(section.header)) {
                    ForEach(section.rows) { rowModel in
                        row(for: rowModel)
                    }
                    .onDelete { offset in
                        self.delete(at: offset, in: section)
                    }
                }
                .listRowBackground(Color.rowBackground)
            }
        }
        .environment(\.editMode, $editMode)
        .listStyle(.insetGrouped)
    }
    
    @ViewBuilder
    private func row(for rowModel: DownloadsListRowViewModel) -> some View {
        if let rowModel = rowModel as? OngoingDownloadRowViewModel {
            OngoingDownloadRow(rowModel: rowModel,
                               cancelButtonAction: { self.selectedRowModelToCancel = rowModel })
                .deleteDisabled(true)
        } else if let rowModel = rowModel as? CompleteDownloadRowViewModel {
            CompleteDownloadRow(rowModel: rowModel,
                                shareButtonAction: { buttonFrame in share(rowModel, from: buttonFrame) })
        }
    }
    
    private func cancelDownload(for rowModel: OngoingDownloadRowViewModel) {
        viewModel.cancelDownload(for: rowModel)
    }
    
    private func delete(at offsets: IndexSet, in section: DownloadsListSectionViewModel) {
        guard let sectionIndex = viewModel.sections.firstIndex(of: section) else { return }
        viewModel.deleteDownload(at: offsets, in: sectionIndex)
    }
    
    private func deleteAll() {
        editMode = .inactive
        viewModel.deleteAllDownloads()
    }
    
    private func share(_ rowModel: CompleteDownloadRowViewModel, from rectangle: CGRect) {
        viewModel.showActivityView(for: rowModel, from: rectangle)
    }
}

extension DownloadsList {
    private func makeCancelDownloadAlert(for row: OngoingDownloadRowViewModel) -> Alert {
        Alert(
            title: Text(UserText.cancelDownloadAlertTitle),
            message: Text(UserText.cancelDownloadAlertDescription),
            primaryButton: .cancel(Text(UserText.cancelDownloadAlertNoAction)),
            secondaryButton: .destructive(Text(UserText.cancelDownloadAlertYesAction), action: {
                cancelDownload(for: row)
            })
        )
    }
}

private enum Const {
    enum Font {
        static let emptyState = UIFont.appFont(ofSize: 16)
    }
}

private extension Color {
    static let barButton = Color(designSystemColor: .icons)
    static let emptyState = Color(baseColor: .gray60)
    static let deleteAll = Color(designSystemColor: .buttonsDeleteGhostText)
    static let background = Color(designSystemColor: .background)
    static let rowBackground = Color(designSystemColor: .surface)
}
