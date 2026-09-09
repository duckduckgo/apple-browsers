//
//  UnifiedToggleInputAttachmentPresenter.swift
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

import AIChat
import Core
import DesignResourcesKit
import DesignResourcesKitIcons
import FoundationExtensions
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class UnifiedToggleInputAttachmentPresenter: NSObject {

    /// Hack phase switch: set to false to restore the existing Add Tabs submenu.
    private static let useTabPickerSheet = true
    private static let isUsingCustomFaviconSize = true
    private static let recentTabsMenuItemLimit = 3
    private static let recentTabTitleCharacterLimit = 28
    private static let recentTabFaviconSize: CGFloat = 16
    private static let menuImageCanvasSize: CGFloat = 20

    struct FileMetadata: Sendable {
        let fileName: String
        let mimeType: String
        let fileSizeBytes: Int?
        let url: URL
    }

    var onExpandIfNeeded: (() -> Void)?
    var onImagePicked: ((UIImage, String) -> Void)?
    var onFilePicked: ((AIChatFileAttachment, FileMetadata) -> Void)?
    var onFileValidationFailed: ((String, FileMetadata) -> Void)?
    var fileMetadataValidationMessage: ((FileMetadata) -> String?)?
    /// Supplies the UTI surface for attachment pixels. Set by the coordinator; defaults to `.addressBar`.
    var pixelSurfaceProvider: (() -> UnifiedToggleInputPixelSurface)?

    nonisolated static func recoverFileAttachment(from metadata: FileMetadata, id: UUID = UUID()) -> AIChatFileAttachment? {
        fileAttachment(from: metadata, id: id)
    }

    /// Builds a file attachment from already-loaded bytes with PDF inspection; shared by the picker and paste flows.
    nonisolated static func makeFileAttachment(
        data: Data,
        fileName: String,
        mimeType: String,
        fileSizeBytes: Int? = nil,
        id: UUID = UUID()
    ) -> AIChatFileAttachment {
        let pdfInspection = AIChatPDFInspector.inspect(data: data, mimeType: mimeType)
        return AIChatFileAttachment(
            id: id,
            data: data,
            fileName: fileName,
            mimeType: mimeType,
            fileSizeBytes: fileSizeBytes ?? data.count,
            pageCount: pdfInspection.pageCount,
            isEncrypted: pdfInspection.isEncrypted
        )
    }

    func makeAttachmentMenu(
        presenterProvider: @escaping () -> UIViewController?,
        photoSelectionLimit: Int,
        canAttachFile: Bool,
        allowedFileTypes: [UTType],
        showsPageContextAction: Bool = false,
        pageContextActionHandler: (() -> Void)? = nil,
        attachableTabs: [MultiTabAttachmentCandidate] = [],
        attachedTabIds: Set<TabUID> = [],
        tabActionHandler: ((MultiTabAttachmentCandidate) -> Bool)? = nil
    ) -> UIMenu? {
        let canAttachPhoto = photoSelectionLimit > 0
        let canTakePhoto = canAttachPhoto && UIImagePickerController.isSourceTypeAvailable(.camera)
        let canAttachAllowedFile = canAttachFile && !allowedFileTypes.isEmpty
        let canAttachPageContext = pageContextActionHandler != nil
        let showsTabAction = !attachableTabs.isEmpty && tabActionHandler != nil
        guard canTakePhoto || canAttachPhoto || canAttachAllowedFile || showsPageContextAction || showsTabAction else { return nil }

        var actions: [UIMenuElement] = [
            UIAction(
                title: UserText.aiChatAttachmentOptionTakePhoto,
                image: DesignSystemImages.Glyphs.Size16.camera,
                attributes: canTakePhoto ? [] : .disabled
            ) { [weak self] _ in
                guard canTakePhoto else { return }
                guard let presenter = presenterProvider() else { return }
                self?.presentCamera(from: presenter)
            },
            UIAction(
                title: UserText.aiChatAttachmentOptionAttachPhoto,
                image: DesignSystemImages.Glyphs.Size16.image,
                attributes: canAttachPhoto ? [] : .disabled
            ) { [weak self] _ in
                guard canAttachPhoto else { return }
                guard let presenter = presenterProvider() else { return }
                self?.presentPhotoPicker(from: presenter, selectionLimit: photoSelectionLimit)
            },
            UIAction(
                title: UserText.aiChatAttachmentOptionAttachFile,
                image: DesignSystemImages.Glyphs.Size16.folder,
                attributes: canAttachAllowedFile ? [] : .disabled
            ) { [weak self] _ in
                guard canAttachAllowedFile else { return }
                guard let presenter = presenterProvider() else { return }
                self?.presentDocumentPicker(from: presenter, allowedFileTypes: allowedFileTypes)
            }
        ]

        if showsPageContextAction {
            actions.append(
                UIAction(
                    title: UserText.aiChatAttachmentOptionAskAboutPage,
                    image: DesignSystemImages.Glyphs.Size16.tabContent,
                    attributes: canAttachPageContext ? [] : .disabled
                ) { _ in
                    guard canAttachPageContext else { return }
                    pageContextActionHandler?()
                }
            )
        }

        if showsTabAction, let tabActionHandler {
            if Self.useTabPickerSheet {
                actions.insert(Self.makeRecentTabsSection(attachableTabs: attachableTabs,
                                                          attachedTabIds: attachedTabIds,
                                                          tabActionHandler: tabActionHandler),
                               at: 0)
                actions.append(
                    makeTabPickerAction(presenterProvider: presenterProvider,
                                        attachableTabs: attachableTabs,
                                        attachedTabIds: attachedTabIds,
                                        tabActionHandler: tabActionHandler)
                )
            } else {
                actions.append(
                    Self.makeTabSubmenu(attachableTabs: attachableTabs,
                                        attachedTabIds: attachedTabIds,
                                        tabActionHandler: tabActionHandler)
                )
            }
        }

        return UIMenu(children: actions)
    }

    /// Hack phase picker: a submenu with one checkmarked entry per open tab.
    ///
    /// Each entry keeps the menu open on iOS 16 and later, so several tabs can be picked in one
    /// pass. The state is flipped on the action itself because the menu is not rebuilt while it
    /// stays open.
    private static func makeTabSubmenu(attachableTabs: [MultiTabAttachmentCandidate],
                                       attachedTabIds: Set<TabUID>,
                                       tabActionHandler: @escaping (MultiTabAttachmentCandidate) -> Bool) -> UIMenu {
        let tabActions: [UIAction] = attachableTabs.map { candidate in
            let favicon = FaviconsHelper.loadFaviconSync(
                forDomain: candidate.url.host,
                usingCache: .tabs,
                useFakeFavicon: true).image?.withRenderingMode(.alwaysOriginal)
            let action = UIAction(title: candidate.title,
                                  image: favicon,
                                  state: attachedTabIds.contains(candidate.tabId) ? .on : .off) { action in
                guard tabActionHandler(candidate) else { return }
                action.state = action.state == .on ? .off : .on
            }
            if #available(iOS 16.0, *) {
                action.attributes.insert(.keepsMenuPresented)
            }
            return action
        }

        return UIMenu(title: UserText.aiChatAttachmentOptionAddTabs,
                      image: DesignSystemImages.Glyphs.Size16.tabContent,
                      children: tabActions)
    }

    private static func makeRecentTabsSection(attachableTabs: [MultiTabAttachmentCandidate],
                                              attachedTabIds: Set<TabUID>,
                                              tabActionHandler: @escaping (MultiTabAttachmentCandidate) -> Bool) -> UIMenu {
        let reachedAttachmentLimit = attachedTabIds.count >= MultiTabAttachmentSelectionPolicy.attachmentLimit
        let tabActions: [UIAction] = attachableTabs.prefix(recentTabsMenuItemLimit).map { candidate in
            let isAttached = attachedTabIds.contains(candidate.tabId)
            let title = candidate.title
                .replacingOccurrences(of: "\n", with: " ")
                .truncated(to: recentTabTitleCharacterLimit, position: .tail)
            let favicon = makeRecentTabMenuFavicon(for: candidate)
            return UIAction(title: title,
                            image: favicon,
                            attributes: reachedAttachmentLimit && !isAttached ? .disabled : [],
                            state: isAttached ? .on : .off) { action in
                guard tabActionHandler(candidate) else { return }
                action.state = action.state == .on ? .off : .on
            }
        }

        let menu = UIMenu(title: UserText.aiChatAttachmentRecentTabsSectionTitle,
                          options: .displayInline,
                          children: tabActions)
        if #available(iOS 16.0, *) {
            menu.preferredElementSize = .large
        }
        if #available(iOS 17.4, *) {
            let displayPreferences = UIMenuDisplayPreferences()
            displayPreferences.maximumNumberOfTitleLines = 1
            menu.displayPreferences = displayPreferences
        }
        return menu
    }

    private static func makeRecentTabMenuFavicon(for candidate: MultiTabAttachmentCandidate) -> UIImage? {
        guard let favicon = FaviconsHelper.loadFaviconSync(
            forDomain: candidate.url.host,
            usingCache: .tabs,
            useFakeFavicon: true).image else { return nil }
        guard isUsingCustomFaviconSize else { return favicon.withRenderingMode(.alwaysOriginal) }

        let canvasSize = CGSize(width: menuImageCanvasSize, height: menuImageCanvasSize)
        let faviconOrigin = (menuImageCanvasSize - recentTabFaviconSize) / 2
        let faviconRect = CGRect(x: faviconOrigin,
                                 y: faviconOrigin,
                                 width: recentTabFaviconSize,
                                 height: recentTabFaviconSize)
        return UIGraphicsImageRenderer(size: canvasSize).image { _ in
            favicon.draw(in: faviconRect)
        }.withRenderingMode(.alwaysOriginal)
    }

    private func makeTabPickerAction(presenterProvider: @escaping () -> UIViewController?,
                                     attachableTabs: [MultiTabAttachmentCandidate],
                                     attachedTabIds: Set<TabUID>,
                                     tabActionHandler: @escaping (MultiTabAttachmentCandidate) -> Bool) -> UIAction {
        UIAction(title: UserText.aiChatAttachmentOptionAddTabs,
                 image: DesignSystemImages.Glyphs.Size16.tabContent) { [weak self] _ in
            guard let presenter = presenterProvider() else { return }
            self?.presentTabPicker(from: presenter,
                                   attachableTabs: attachableTabs,
                                   attachedTabIds: attachedTabIds,
                                   tabActionHandler: tabActionHandler)
        }
    }

    private func presentTabPicker(from presenter: UIViewController,
                                  attachableTabs: [MultiTabAttachmentCandidate],
                                  attachedTabIds: Set<TabUID>,
                                  tabActionHandler: @escaping (MultiTabAttachmentCandidate) -> Bool) {
        let viewModel = MultiTabAttachmentPickerViewModel(
            candidates: attachableTabs,
            selectedTabIds: attachedTabIds,
            attachmentLimit: MultiTabAttachmentSelectionPolicy.attachmentLimit)
        let picker = MultiTabAttachmentPickerView(viewModel: viewModel)
        let hostingController = MultiTabAttachmentPickerHostingController(rootView: picker)
        let navigationController = UINavigationController(rootViewController: hostingController)

        let closeAction = UIAction { [weak navigationController] _ in
            navigationController?.dismiss(animated: true)
        }
        let closeItem = UIBarButtonItem(title: nil,
                                        image: DesignSystemImages.Glyphs.Size24.close,
                                        primaryAction: closeAction,
                                        menu: nil)
        closeItem.tintColor = UIColor(designSystemColor: .textPrimary)
        closeItem.accessibilityLabel = UserText.aiChatChooseTabsCloseAccessibilityLabel
        hostingController.navigationItem.leftBarButtonItem = closeItem

        let confirmAction = UIAction { [weak navigationController] _ in
            Self.applyTabSelection(viewModel.selectedTabIds,
                                   initialTabIds: attachedTabIds,
                                   candidates: attachableTabs,
                                   tabActionHandler: tabActionHandler)
            navigationController?.dismiss(animated: true)
        }
        let confirmItem = UIBarButtonItem(title: nil,
                                          image: DesignSystemImages.Glyphs.Size24.check,
                                          primaryAction: confirmAction,
                                          menu: nil)
        confirmItem.style = .done
        if #available(iOS 26.0, *) {
            confirmItem.style = .prominent
        }
        confirmItem.tintColor = UIColor(designSystemColor: .accentPrimary)
        confirmItem.accessibilityLabel = UserText.aiChatChooseTabsConfirmAccessibilityLabel
        hostingController.navigationItem.rightBarButtonItem = confirmItem

        navigationController.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .formSheet : .pageSheet
        navigationController.preferredContentSize = CGSize(width: 540, height: 720)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }
        presenter.present(navigationController, animated: true)
    }

    private static func applyTabSelection(_ selectedTabIds: Set<TabUID>,
                                          initialTabIds: Set<TabUID>,
                                          candidates: [MultiTabAttachmentCandidate],
                                          tabActionHandler: (MultiTabAttachmentCandidate) -> Bool) {
        let removedTabIds = initialTabIds.subtracting(selectedTabIds)
        let addedTabIds = selectedTabIds.subtracting(initialTabIds)

        for candidate in candidates where removedTabIds.contains(candidate.tabId) {
            tabActionHandler(candidate)
        }
        for candidate in candidates where addedTabIds.contains(candidate.tabId) {
            tabActionHandler(candidate)
        }
    }

    /// Opens the system file picker directly (bypassing the attachment menu) for the promo "add file" CTA.
    func presentFilePicker(from presenter: UIViewController, allowedFileTypes: [UTType]) {
        presentDocumentPicker(from: presenter, allowedFileTypes: allowedFileTypes)
    }
}

/// Keeps picker navigation actions visible while SwiftUI search is active.
private final class MultiTabAttachmentPickerHostingController: UIHostingController<MultiTabAttachmentPickerView> {

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureSearchPresentation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configureSearchPresentation()
    }

    private func configureSearchPresentation() {
        navigationItem.searchController?.hidesNavigationBarDuringPresentation = false
    }
}

private extension UnifiedToggleInputAttachmentPresenter {

    func presentCamera(from presenter: UIViewController) {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    func presentPhotoPicker(from presenter: UIViewController, selectionLimit: Int) {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = selectionLimit
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    func presentDocumentPicker(from presenter: UIViewController, allowedFileTypes: [UTType]) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedFileTypes, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    nonisolated static func fileMetadata(from url: URL) -> FileMetadata? {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .nameKey])
            let fileName = values.name ?? url.lastPathComponent
            let mimeType = values.contentType?.preferredMIMEType ?? "application/octet-stream"
            return FileMetadata(fileName: fileName, mimeType: mimeType, fileSizeBytes: values.fileSize, url: url)
        } catch {
            return nil
        }
    }

    nonisolated static func fallbackFileMetadata(from url: URL) -> FileMetadata {
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return FileMetadata(fileName: url.lastPathComponent, mimeType: mimeType, fileSizeBytes: nil, url: url)
    }

    nonisolated static func fileAttachment(from metadata: FileMetadata, id: UUID = UUID()) -> AIChatFileAttachment? {
        guard !Task.isCancelled else { return nil }

        let hasScopedAccess = metadata.url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                metadata.url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: metadata.url)
            guard !Task.isCancelled else { return nil }

            return makeFileAttachment(
                data: data,
                fileName: metadata.fileName,
                mimeType: metadata.mimeType,
                fileSizeBytes: metadata.fileSizeBytes,
                id: id
            )
        } catch {
            return nil
        }
    }

}

extension UnifiedToggleInputAttachmentPresenter: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        onExpandIfNeeded?()

        for result in results {
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
            let suggestedName = provider.suggestedName ?? "image"

            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }

                Task { @MainActor in
                    let surface = self?.pixelSurfaceProvider?() ?? .addressBar
                    DailyPixel.fireDailyAndCount(
                        pixel: .unifiedToggleInputImageAttached,
                        withAdditionalParameters: ["source": "photo_library", "surface": surface.rawValue]
                    )
                    self?.onImagePicked?(image, suggestedName)
                }
            }
        }
    }
}

extension UnifiedToggleInputAttachmentPresenter: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        onExpandIfNeeded?()
        guard let image = info[.originalImage] as? UIImage else { return }
        DailyPixel.fireDailyAndCount(
            pixel: .unifiedToggleInputImageAttached,
            withAdditionalParameters: ["source": "camera", "surface": (pixelSurfaceProvider?() ?? .addressBar).rawValue]
        )
        onImagePicked?(image, "photo")
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        onExpandIfNeeded?()
    }
}

extension UnifiedToggleInputAttachmentPresenter: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        controller.dismiss(animated: true)
        onExpandIfNeeded?()
        guard let url = urls.first else { return }

        Task { [weak self, url] in
            guard let self else { return }
            let metadata = await Task.detached(priority: .userInitiated) {
                Self.fileMetadata(from: url)
            }.value
            guard let metadata else {
                onFileValidationFailed?(UserText.aiChatAttachmentFileUnreadable, Self.fallbackFileMetadata(from: url))
                return
            }

            if let validationMessage = fileMetadataValidationMessage?(metadata) {
                onFileValidationFailed?(validationMessage, metadata)
                return
            }

            let fileAttachment = await Task.detached(priority: .userInitiated) {
                Self.fileAttachment(from: metadata)
            }.value
            guard let fileAttachment else {
                onFileValidationFailed?(UserText.aiChatAttachmentFileUnreadable, metadata)
                return
            }

            onFilePicked?(fileAttachment, metadata)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true)
        onExpandIfNeeded?()
    }
}
