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
    @State private var previewSheet: DeferredReadingPreviewSheet?
    @StateObject private var previewCoordinator: DeferredReadingPreviewCoordinator

    public init(controller: DeferredReadingController,
                faviconLoader: ((URL, @escaping (UIImage?) -> Void) -> Void)? = nil,
                previewSessionProvider: (any DeferredReadingPreviewSessionProviding)? = nil,
                onOpenURL: @escaping (URL) -> Void) {
        self.controller = controller
        self.faviconLoader = faviconLoader
        self.onOpenURL = onOpenURL
        _previewCoordinator = StateObject(wrappedValue: DeferredReadingPreviewCoordinator(previewSessionProvider: previewSessionProvider))
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
                                               content: AnyView(DeferredReadingViewControllerContainer(controller: sheet.previewController)),
                                               onClose: {
                    previewCoordinator.closeActivePreview()
                    previewSheet = nil
                },
                                               onOpenInTab: {
                    previewSheet = nil
                    dismiss()
                    DispatchQueue.main.async {
                        if !previewCoordinator.openActivePreviewInTab(for: sheet.url) {
                            onOpenURL(sheet.url)
                        }
                    }
                })
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func itemRow(_ item: DeferredReadingItem) -> some View {
        Button {
            if let url = controller.open(item) {
                if let sheet = previewCoordinator.previewSheet(for: url) {
                    previewSheet = sheet
                } else {
                    dismiss()
                    DispatchQueue.main.async {
                        onOpenURL(url)
                    }
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
        private var hasCapturedAppearance = false
        private var previousTintColor: UIColor?
        private var previousNavigationControllerBackgroundColor: UIColor?
        private var previousStandardAppearance: UINavigationBarAppearance?
        private var previousScrollEdgeAppearance: UINavigationBarAppearance?
        private var previousCompactAppearance: UINavigationBarAppearance?
        private var previousCompactScrollEdgeAppearance: UINavigationBarAppearance?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyAppearanceIfPossible()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restoreAppearanceIfNeeded()
        }

        deinit {
            restoreAppearanceIfNeeded()
        }

        func applyAppearanceIfPossible() {
            guard let navigationController else { return }
            let navigationBar = navigationController.navigationBar

            if !hasCapturedAppearance {
                hasCapturedAppearance = true
                previousTintColor = navigationBar.tintColor
                previousNavigationControllerBackgroundColor = navigationController.view.backgroundColor
                previousStandardAppearance = navigationBar.standardAppearance
                previousScrollEdgeAppearance = navigationBar.scrollEdgeAppearance
                previousCompactAppearance = navigationBar.compactAppearance
                if #available(iOS 15.0, *) {
                    previousCompactScrollEdgeAppearance = navigationBar.compactScrollEdgeAppearance
                }
            }

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
            navigationController.view.backgroundColor = backgroundColor
        }

        private func restoreAppearanceIfNeeded() {
            guard hasCapturedAppearance,
                  let navigationController else { return }
            let navigationBar = navigationController.navigationBar

            if let previousTintColor {
                navigationBar.tintColor = previousTintColor
            }
            if let previousStandardAppearance {
                navigationBar.standardAppearance = previousStandardAppearance
            }
            if let previousScrollEdgeAppearance {
                navigationBar.scrollEdgeAppearance = previousScrollEdgeAppearance
            }
            if let previousCompactAppearance {
                navigationBar.compactAppearance = previousCompactAppearance
            }
            if #available(iOS 15.0, *), let previousCompactScrollEdgeAppearance {
                navigationBar.compactScrollEdgeAppearance = previousCompactScrollEdgeAppearance
            }
            navigationController.view.backgroundColor = previousNavigationControllerBackgroundColor

            hasCapturedAppearance = false
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
