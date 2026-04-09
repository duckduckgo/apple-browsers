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

import PhotosUI
import UIKit

@MainActor
final class UnifiedToggleInputAttachmentPresenter: NSObject {

    var onExpandIfNeeded: (() -> Void)?
    var onImagePicked: ((UIImage, String) -> Void)?

    func presentAttachmentOptions(from sourceView: UIView, presenter: UIViewController, remaining: Int) {
        guard remaining > 0 else { return }

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            sheet.addAction(UIAlertAction(title: UserText.aiChatAttachmentOptionTakePhoto, style: .default) { [weak self] _ in
                self?.presentCamera(from: presenter)
            })
        }

        sheet.addAction(UIAlertAction(title: UserText.aiChatAttachmentOptionChoosePhoto, style: .default) { [weak self] _ in
            self?.presentPhotoPicker(from: presenter, remaining: remaining)
        })

        sheet.addAction(UIAlertAction(title: UserText.actionCancel, style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView
        }

        presenter.present(sheet, animated: true)
    }

    private func presentCamera(from presenter: UIViewController) {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    private func presentPhotoPicker(from presenter: UIViewController, remaining: Int) {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = remaining
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }
}

extension UnifiedToggleInputAttachmentPresenter: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        onExpandIfNeeded?()

        for result in results {
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else { continue }

            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }
                let fileName = provider.suggestedName ?? "image"

                Task { @MainActor in
                    self?.onImagePicked?(image, fileName)
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
