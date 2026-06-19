import DeferredReadingCore
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI
import UIKit

public struct DeferredReadingListView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var controller: DeferredReadingController
    private let onOpenURL: (URL) -> Void
    private let faviconLoader: ((URL, @escaping (UIImage?) -> Void) -> Void)?
    @State private var isShowingSettings = false

    public init(controller: DeferredReadingController,
                faviconLoader: ((URL, @escaping (UIImage?) -> Void) -> Void)? = nil,
                onOpenURL: @escaping (URL) -> Void) {
        self.controller = controller
        self.faviconLoader = faviconLoader
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
                        Button("Settings") {
                            isShowingSettings = true
                        }
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
            .sheet(isPresented: $isShowingSettings) {
                NavigationView {
                    DeferredReadingSettingsView(settingsController: controller.settingsController)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    isShowingSettings = false
                                }
                            }
                        }
                }
                .navigationViewStyle(.stack)
            }
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
            HStack(alignment: .top, spacing: 10) {
                faviconView(for: item)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(primaryTitle(for: item))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .lineLimit(2)
                    Text(secondaryURLText(for: item))
                        .font(.caption)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.addedAt, style: .date)
                        .font(.caption)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func faviconView(for item: DeferredReadingItem) -> some View {
        if let itemURL = item.url, let faviconLoader {
            DeferredReadingFaviconView(url: itemURL,
                                       faviconLoader: faviconLoader)
        } else {
            placeholderFaviconView
        }
    }

    private var placeholderFaviconView: some View {
        Image(uiImage: DesignSystemImages.Glyphs.Size24.globe)
            .resizable()
            .scaledToFit()
            .foregroundColor(Color(designSystemColor: .icons))
            .padding(3)
            .background(Color(designSystemColor: .surface))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func primaryTitle(for item: DeferredReadingItem) -> String {
        if let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        return item.url?.host ?? item.urlString
    }

    private func secondaryURLText(for item: DeferredReadingItem) -> String {
        item.url?.absoluteString ?? item.urlString
    }

}

private struct DeferredReadingFaviconView: View {

    let url: URL
    let faviconLoader: (URL, @escaping (UIImage?) -> Void) -> Void

    @State private var image: UIImage?
    @State private var requested = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderFaviconView
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task {
            guard !requested else { return }
            requested = true
            faviconLoader(url) { loadedImage in
                guard let loadedImage else { return }
                DispatchQueue.main.async {
                    image = loadedImage
                }
            }
        }
    }

    private var placeholderFaviconView: some View {
        Image(uiImage: DesignSystemImages.Glyphs.Size24.globe)
            .resizable()
            .scaledToFit()
            .foregroundColor(Color(designSystemColor: .icons))
            .padding(3)
            .background(Color(designSystemColor: .surface))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
