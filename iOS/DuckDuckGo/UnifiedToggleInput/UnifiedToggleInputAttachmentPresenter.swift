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
import DesignResourcesKitIcons
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class UnifiedToggleInputAttachmentPresenter: NSObject {

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
        pageContextActionHandler: (() -> Void)? = nil
    ) -> UIMenu? {
        let canAttachPhoto = photoSelectionLimit > 0
        let canTakePhoto = canAttachPhoto && UIImagePickerController.isSourceTypeAvailable(.camera)
        let canAttachAllowedFile = canAttachFile && !allowedFileTypes.isEmpty
        let canAttachPageContext = pageContextActionHandler != nil
        guard canTakePhoto || canAttachPhoto || canAttachAllowedFile || showsPageContextAction else { return nil }

        var actions = [
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

        return UIMenu(children: actions)
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
