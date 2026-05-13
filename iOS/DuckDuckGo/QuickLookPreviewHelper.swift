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

import UIKit
import QuickLook

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
        guard let viewController else { return }
        selfRetain = self
        // Front-of-stack modals (address-bar editing, etc.) make UIKit drop our present silently.
        let present = { [qlPreview] in viewController.present(qlPreview, animated: true) }
        if let presented = viewController.presentedViewController {
            presented.dismiss(animated: false, completion: present)
        } else {
            present()
        }
    }

    static func canPreview(_ url: URL) -> Bool {
        let previewItem = url as NSURL
        return QLPreviewController.canPreview(previewItem)
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
