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
    private let previewContentBuilder: ((URL) -> AnyView)?
    private let onPreviewDismissed: ((URL) -> Void)?
    @State private var isShowingSettings = false
    @State private var previewSheet: PreviewSheet?

    public init(controller: DeferredReadingController,
                faviconLoader: ((URL, @escaping (UIImage?) -> Void) -> Void)? = nil,
                previewContentBuilder: ((URL) -> AnyView)? = nil,
                onPreviewDismissed: ((URL) -> Void)? = nil,
                onOpenURL: @escaping (URL) -> Void) {
        self.controller = controller
        self.faviconLoader = faviconLoader
        self.previewContentBuilder = previewContentBuilder
        self.onPreviewDismissed = onPreviewDismissed
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
            .sheet(item: $previewSheet) { sheet in
                DeferredReadingPreviewSheetView(url: sheet.url,
                                               content: sheet.content,
                                               onClose: {
                    onPreviewDismissed?(sheet.url)
                    previewSheet = nil
                },
                                               onOpenInTab: {
                    onOpenURL(sheet.url)
                    previewSheet = nil
                })
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func itemRow(_ item: DeferredReadingItem) -> some View {
        Button {
            if let url = controller.open(item) {
                if let previewContentBuilder {
                    previewSheet = PreviewSheet(url: url,
                                                content: previewContentBuilder(url))
                } else {
                    onOpenURL(url)
                }
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

private struct PreviewSheet: Identifiable {
    let id = UUID()
    let url: URL
    let content: AnyView
}

private struct DeferredReadingPreviewSheetView: View {
    let url: URL
    let content: AnyView
    let onClose: () -> Void
    let onOpenInTab: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(DeferredReadingOpaqueNavigationBarConfigurator())
            .background(Color(designSystemColor: .backgroundSheets))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onClose()
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(url.host ?? "Page")
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onOpenInTab) {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.tabNew)
                            .foregroundColor(Color(designSystemColor: .icons))
                    }
                    .accessibilityLabel("Open in New Tab")
                }
            }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(true)
    }
}

private struct DeferredReadingOpaqueNavigationBarConfigurator: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.applyAppearanceIfPossible()
    }

    final class Controller: UIViewController {

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyAppearanceIfPossible()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyAppearanceIfPossible()
        }

        func applyAppearanceIfPossible() {
            guard let navigationBar = navigationController?.navigationBar else { return }

            let backgroundColor = UIColor(designSystemColor: .backgroundSheets)
            let foregroundColor = UIColor(designSystemColor: .textPrimary)

            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = backgroundColor
            appearance.shadowColor = .clear
            appearance.titleTextAttributes = [.foregroundColor: foregroundColor]
            appearance.largeTitleTextAttributes = [.foregroundColor: foregroundColor]

            navigationBar.tintColor = foregroundColor
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
            navigationBar.compactAppearance = appearance
            if #available(iOS 15.0, *) {
                navigationBar.compactScrollEdgeAppearance = appearance
            }
            navigationController?.view.backgroundColor = backgroundColor
        }
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
