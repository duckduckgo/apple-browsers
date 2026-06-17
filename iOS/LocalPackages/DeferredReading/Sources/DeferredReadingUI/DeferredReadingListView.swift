import DeferredReadingCore
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

public struct DeferredReadingListView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var controller: DeferredReadingController
    private let onOpenURL: (URL) -> Void

    public init(controller: DeferredReadingController,
                onOpenURL: @escaping (URL) -> Void) {
        self.controller = controller
        self.onOpenURL = onOpenURL
    }

    public var body: some View {
        NavigationView {
            List {
                if !controller.unreadItems.isEmpty {
                    Section("Unread") {
                        ForEach(controller.unreadItems) { item in
                            itemRow(item)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        controller.delete(itemID: item.id)
                                    } label: {
                                        Text("Delete")
                                    }
                                }
                        }
                    }
                }

                if !controller.readItems.isEmpty {
                    Section("Read") {
                        ForEach(controller.readItems) { item in
                            itemRow(item)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        controller.delete(itemID: item.id)
                                    } label: {
                                        Text("Delete")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Deferred Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Clear Read") {
                            controller.clearRead()
                        }
                        Button("Clear All", role: .destructive) {
                            controller.clearAll()
                        }
                    } label: {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.moreApple)
                            .foregroundColor(Color(designSystemColor: .icons))
                    }
                    .accessibilityLabel("Actions")
                }
            }
            .listStyle(.insetGrouped)
            .background(Color(designSystemColor: .background))
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func itemRow(_ item: DeferredReadingItem) -> some View {
        Button {
            if let url = controller.open(item) {
                onOpenURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? item.url?.host ?? item.urlString)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .lineLimit(2)
                Text(item.addedAt, style: .date)
                    .font(.caption)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
        }
    }
}
