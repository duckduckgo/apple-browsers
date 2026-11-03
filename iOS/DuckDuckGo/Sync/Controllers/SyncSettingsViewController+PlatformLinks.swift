//
//  SyncSettingsViewController+PlatformLinks.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Core
import PixelKit
import SyncUI_iOS

extension SyncSettingsViewController {
    
    func shareLink(for url: URL, with message: String, from sourceView: UIView) {
        PlatformLinksActions(presenter: self, pixelFiring: pixelFiring).shareLinkPressed(for: url, with: message, from: sourceView)
    }
}

struct PlatformLinksActions: PlatformLinksHandling {

    weak var presenter: UIViewController?
    let pixelFiring: (any PixelKitFiring)?

    func shareLinkPressed(for url: URL, with message: String, from sourceView: UIView) {
        let itemSource = ShareItemSource(url: url, message: message)
        let activityViewController = UIActivityViewController(activityItems: [itemSource], applicationActivities: nil)

        if UIDevice.current.userInterfaceIdiom == .pad {
            activityViewController.popoverPresentationController?.sourceView = sourceView
            activityViewController.popoverPresentationController?.sourceRect = sourceView.bounds
        }

        presenter?.present(activityViewController, animated: true, completion: nil)
    }

    func fireOtherPlatformLinksPixel(for event: SyncSettingsViewModel.PlatformLinksPixelEvent, source: SyncSettingsViewModel.PlatformLinksPixelSource) {
        let params = ["source": source.rawValue]

        switch event {
        case .appear:
            pixelFiring?.fire(Pixel.Event.syncGetOtherDevices, options: .parameters(params))
        case .copy:
            pixelFiring?.fire(Pixel.Event.syncGetOtherDevicesCopy, options: .parameters(params))
        case .share:
            pixelFiring?.fire(Pixel.Event.syncGetOtherDevicesShare, options: .parameters(params))
        }
    }
}

private class ShareItemSource: NSObject, UIActivityItemSource {
    var url: URL
    var message: String

    init(url: URL, message: String) {
        self.url = url
        self.message = message
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        if activityType == .mail || activityType == .message {
            return "\(message) \(url.absoluteString)"
        }
        return url
    }

}
