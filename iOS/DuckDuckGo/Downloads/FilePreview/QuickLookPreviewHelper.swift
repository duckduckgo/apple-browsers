//
//  QuickLookPreviewHelper.swift
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

import QuickLook
import UIKit

class QuickLookPreviewHelper: NSObject, FilePreview {
    private weak var viewController: UIViewController?
    private let filePath: URL

    /// QLPreviewController holds its data source weakly; self-retain until dismissal.
    private var selfRetain: QuickLookPreviewHelper?

    private lazy var qlPreview: QLPreviewController = {
        let preview = QLPreviewController()
        preview.dataSource = self
        preview.delegate = self
        return preview
    }()

    required init(_ filePath: URL, viewController: UIViewController) {
        self.filePath = filePath
        self.viewController = viewController
        super.init()
    }

    func preview() {
        preview(modalPresentationStyle: nil, completion: nil)
    }

    /// `completion` fires after QL animates in.
    /// Pass a non-nil `modalPresentationStyle` to override QL's default full-screen.
    func preview(modalPresentationStyle: UIModalPresentationStyle? = nil,
                 completion: (() -> Void)?) {
        guard let viewController else { return }
        selfRetain = self
        if let modalPresentationStyle {
            qlPreview.modalPresentationStyle = modalPresentationStyle
        }
        viewController.present(qlPreview, animated: true, completion: completion)
    }

    static func canPreview(_ url: URL) -> Bool {
        let previewItem = url as NSURL
        return QLPreviewController.canPreview(previewItem)
    }

    static func presentAsFallback(_ filePath: URL,
                                  from viewController: UIViewController,
                                  completion: @escaping () -> Void) {
        let presentQuickLook = {
            let iPadFormSheet: UIModalPresentationStyle? = UIDevice.current.userInterfaceIdiom == .pad ? .formSheet : nil
            QuickLookPreviewHelper(filePath, viewController: viewController)
                .preview(modalPresentationStyle: iPadFormSheet, completion: completion)
        }
        if let presented = viewController.presentedViewController {
            presented.dismiss(animated: false, completion: presentQuickLook)
        } else {
            presentQuickLook()
        }
    }
}

extension QuickLookPreviewHelper: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        let string = self.filePath.absoluteString
        return NSURL(string: string)!
    }
}

extension QuickLookPreviewHelper: QLPreviewControllerDelegate {
    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        selfRetain = nil
    }
}
