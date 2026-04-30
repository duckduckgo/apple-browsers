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
import DesignResourcesKit
import DesignResourcesKitIcons
import PDFKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class UnifiedToggleInputAttachmentPresenter: NSObject {

    private enum MenuConstants {
        static let width: CGFloat = 270
        static let itemHeight: CGFloat = 44
        static let verticalPadding: CGFloat = 10
        static let horizontalPadding: CGFloat = 16
        static let itemLeadingInset: CGFloat = 6
        static let itemTrailingInset: CGFloat = 8
        static let iconSize: CGFloat = 24
        static let iconLabelGap: CGFloat = 8
        static let cornerRadius: CGFloat = 32
        static let shadowRadius: CGFloat = 40
        static let shadowOpacity: Float = 0.12
        static let shadowOffset = CGSize(width: 0, height: 8)
    }

    private struct MenuAction {
        let title: String
        let icon: UIImage
        let handler: () -> Void
    }

    private final class MenuItemButton: UIButton {

        private let iconView = UIImageView()
        private let menuTitleLabel = UILabel()

        init(action: MenuAction) {
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            accessibilityLabel = action.title
            accessibilityTraits = .button
            setupUI()
            configure(action: action)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupUI() {
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = UIColor(designSystemColor: .iconsSecondary)
            iconView.translatesAutoresizingMaskIntoConstraints = false

            menuTitleLabel.font = .daxBodyRegular()
            menuTitleLabel.adjustsFontForContentSizeCategory = true
            menuTitleLabel.textColor = UIColor(designSystemColor: .textPrimary)
            menuTitleLabel.translatesAutoresizingMaskIntoConstraints = false

            addSubview(iconView)
            addSubview(menuTitleLabel)

            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuConstants.itemLeadingInset),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: MenuConstants.iconSize),
                iconView.heightAnchor.constraint(equalToConstant: MenuConstants.iconSize),

                menuTitleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: MenuConstants.iconLabelGap),
                menuTitleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                menuTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -MenuConstants.itemTrailingInset),
            ])
        }

        private func configure(action: MenuAction) {
            iconView.image = action.icon.withRenderingMode(.alwaysTemplate)
            menuTitleLabel.text = action.title
        }
    }

    private final class AttachmentMenuViewController: UIViewController {

        private let actions: [MenuAction]

        private let blurView: UIVisualEffectView = {
            let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
            view.translatesAutoresizingMaskIntoConstraints = false
            view.layer.cornerRadius = MenuConstants.cornerRadius
            view.layer.cornerCurve = .continuous
            view.clipsToBounds = true
            return view
        }()

        private let stackView: UIStackView = {
            let stack = UIStackView()
            stack.axis = .vertical
            stack.spacing = 0
            stack.translatesAutoresizingMaskIntoConstraints = false
            return stack
        }()

        init(actions: [MenuAction]) {
            self.actions = actions
            super.init(nibName: nil, bundle: nil)
            modalPresentationStyle = .popover
            preferredContentSize = CGSize(
                width: MenuConstants.width,
                height: (MenuConstants.verticalPadding * 2) + (CGFloat(actions.count) * MenuConstants.itemHeight)
            )
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.layer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
            view.layer.shadowOpacity = MenuConstants.shadowOpacity
            view.layer.shadowRadius = MenuConstants.shadowRadius
            view.layer.shadowOffset = MenuConstants.shadowOffset

            view.addSubview(blurView)
            blurView.contentView.addSubview(stackView)

            NSLayoutConstraint.activate([
                blurView.topAnchor.constraint(equalTo: view.topAnchor),
                blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                stackView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: MenuConstants.verticalPadding),
                stackView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: MenuConstants.horizontalPadding),
                stackView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -MenuConstants.horizontalPadding),
                stackView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -MenuConstants.verticalPadding),
            ])

            actions.enumerated().forEach { index, action in
                let button = MenuItemButton(action: action)
                button.heightAnchor.constraint(equalToConstant: MenuConstants.itemHeight).isActive = true
                button.tag = index
                button.addTarget(self, action: #selector(menuButtonPressed(_:)), for: .touchUpInside)
                stackView.addArrangedSubview(button)
            }
        }

        @objc
        private func menuButtonPressed(_ sender: UIButton) {
            let handler = actions[sender.tag].handler
            dismiss(animated: true) {
                handler()
            }
        }
    }

    var onExpandIfNeeded: (() -> Void)?
    var onImagePicked: ((UIImage, String) -> Void)?
    var onFilePicked: ((AIChatFileAttachment) -> Void)?

    func presentAttachmentOptions(
        from sourceView: UIView,
        presenter: UIViewController,
        photoSelectionLimit: Int,
        canAttachFile: Bool,
        allowedFileTypes: [UTType]
    ) {
        let canAttachPhoto = photoSelectionLimit > 0
        guard canAttachPhoto || canAttachFile else { return }

        var actions = [MenuAction]()

        if canAttachPhoto {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                actions.append(
                    MenuAction(
                        title: UserText.aiChatAttachmentOptionTakePhoto,
                        icon: DesignSystemImages.Glyphs.Size24.camera
                    ) { [weak self] in
                        self?.presentCamera(from: presenter)
                    }
                )
            }

            actions.append(
                MenuAction(
                    title: UserText.aiChatAttachmentOptionAttachPhoto,
                    icon: DesignSystemImages.Glyphs.Size24.image
                ) { [weak self] in
                    self?.presentPhotoPicker(from: presenter, selectionLimit: photoSelectionLimit)
                }
            )
        }

        if canAttachFile, !allowedFileTypes.isEmpty {
            actions.append(
                MenuAction(
                    title: UserText.aiChatAttachmentOptionAttachFile,
                    icon: DesignSystemImages.Glyphs.Size24.folder
                ) { [weak self] in
                    self?.presentDocumentPicker(from: presenter, allowedFileTypes: allowedFileTypes)
                }
            )
        }

        let menuViewController = AttachmentMenuViewController(actions: actions)
        menuViewController.popoverPresentationController?.delegate = self

        if let popover = menuViewController.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
            popover.permittedArrowDirections = []
        }

        presenter.present(menuViewController, animated: true)
    }

    private func presentCamera(from presenter: UIViewController) {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    private func presentPhotoPicker(from presenter: UIViewController, selectionLimit: Int) {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = selectionLimit
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    private func presentDocumentPicker(from presenter: UIViewController, allowedFileTypes: [UTType]) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedFileTypes, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    nonisolated private static func fileAttachment(from url: URL) -> AIChatFileAttachment? {
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
            let data = try Data(contentsOf: url)
            let pageCount = Self.pdfPageCount(data: data, mimeType: mimeType)

            return AIChatFileAttachment(
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                fileSizeBytes: values.fileSize ?? data.count,
                pageCount: pageCount,
                fileURL: url
            )
        } catch {
            return nil
        }
    }

    nonisolated private static func pdfPageCount(data: Data, mimeType: String) -> Int? {
        guard mimeType == "application/pdf" else { return nil }
        return PDFDocument(data: data)?.pageCount
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

        Task { [url] in
            let fileAttachment = await Task.detached(priority: .userInitiated) {
                Self.fileAttachment(from: url)
            }.value
            guard let fileAttachment else { return }

            onFilePicked?(fileAttachment)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true)
        onExpandIfNeeded?()
    }
}

extension UnifiedToggleInputAttachmentPresenter: UIPopoverPresentationControllerDelegate {

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }
}
