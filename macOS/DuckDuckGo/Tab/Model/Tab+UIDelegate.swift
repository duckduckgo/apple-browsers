//
//  Tab+UIDelegate.swift
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

import Combine
import Common
import Foundation
import Navigation
import PixelKit
import UniformTypeIdentifiers
import WebKit
import PDFKit
import CommonObjCExtensions

extension Tab: WKUIDelegate, PrintingUserScriptDelegate {

    // "protected" delegate property
    private var delegate: TabDelegate? {
        self.value(forKey: Tab.objcDelegateKeyPath) as? TabDelegate
    }

    @MainActor private static var expectedSaveDataToFileCallback: (@MainActor (URL?) -> Void)?
    @MainActor
    private static func consumeExpectedSaveDataToFileCallback() -> (@MainActor (URL?) -> Void)? {
        defer {
            expectedSaveDataToFileCallback = nil
        }
        return expectedSaveDataToFileCallback
    }

    @objc(_webView:saveDataToFile:suggestedFilename:mimeType:originatingURL:)
    func webView(_ webView: WKWebView, saveDataToFile data: Data, suggestedFilename: String, mimeType: String, originatingURL: URL) {
        Task {
            var result: URL?
            do {
                result = try await saveDownloadedData(data, suggestedFilename: suggestedFilename, mimeType: mimeType, originatingURL: originatingURL)
            } catch {
                assertionFailure("Save web content failed with \(error)")
            }
            // when print function saves a PDF setting the callback, return the saved temporary file to it
            await Self.consumeExpectedSaveDataToFileCallback()?(result)
        }
    }

    @MainActor
    @objc(_webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:completionHandler:)
    func webView(_ webView: WKWebView,
                 createWebViewWithConfiguration configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures,
                 completionHandler: @escaping (WKWebView?) -> Void) {

        guard isCreateWebViewGatingFailsafeEnabled else {
            completionHandler(self.popupHandling?.createWebView(from: webView,
                                                                with: configuration,
                                                                for: navigationAction,
                                                                windowFeatures: windowFeatures))
            return
        }

        // Defer createWebView handling until any in-flight `decidePolicyForNavigationAction` responder-chain work completes.
        // This prevents a race condition where the createWebView callback for a pop-up is called before a PopupHandlingTabExtension decision
        // to open a pop-up is made.
        // https://app.asana.com/1/137249556945/project/1202406491309510/task/1212353379833164?focus=true
        dispatchCreateWebView { [weak self] in
            completionHandler(self?.popupHandling?.createWebView(from: webView,
                                                                 with: configuration,
                                                                 for: navigationAction,
                                                                 windowFeatures: windowFeatures))
        }
    }

    @MainActor
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        self.popupHandling?.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)
    }

    @objc(_webView:checkUserMediaPermissionForURL:mainFrameURL:frameIdentifier:decisionHandler:)
    func webView(_ webView: WKWebView,
                 checkUserMediaPermissionFor url: NSURL?,
                 mainFrameURL: NSURL?,
                 frameIdentifier: UInt64,
                 decisionHandler: @escaping (String, Bool) -> Void) {
        self.permissions.checkUserMediaPermission(for: url as? URL, mainFrameURL: mainFrameURL as? URL, decisionHandler: decisionHandler)
    }

    // https://github.com/WebKit/WebKit/blob/995f6b1595611c934e742a4f3a9af2e678bc6b8d/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegate.h#L147
    @objc(webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:)
    @available(macOS 12, *)
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard let permissions = [PermissionType](devices: type) else {
            assertionFailure("Could not decode PermissionType")
            decisionHandler(.deny)
            return
        }

        self.permissions.permissions(permissions, requestedForDomain: origin.host, decisionHandler: decisionHandler)
    }

    // https://github.com/WebKit/WebKit/blob/9d7278159234e0bfa3d27909a19e695928f3b31e/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h#L126
    @objc(_webView:requestUserMediaAuthorizationForDevices:url:mainFrameURL:decisionHandler:)
    func webView(_ webView: WKWebView,
                 requestUserMediaAuthorizationFor devices: _WKCaptureDevices,
                 url: URL,
                 mainFrameURL: URL,
                 decisionHandler: @escaping (Bool) -> Void) {
        guard let permissions = [PermissionType](devices: devices),
              let host = url.isFileURL ? .localhost : url.host,
              !host.isEmpty else {
            decisionHandler(false)
            return
        }

        self.permissions.permissions(permissions, requestedForDomain: host, decisionHandler: decisionHandler)
    }

    @objc(_webView:mediaCaptureStateDidChange:)
    func webView(_ webView: WKWebView, mediaCaptureStateDidChange state: _WKMediaCaptureStateDeprecated) {
        self.permissions.mediaCaptureStateDidChange()
    }

    // https://github.com/WebKit/WebKit/blob/9d7278159234e0bfa3d27909a19e695928f3b31e/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h#L131
    @objc(_webView:requestGeolocationPermissionForFrame:decisionHandler:)
    func webView(_ webView: WKWebView, requestGeolocationPermissionFor frame: WKFrameInfo, decisionHandler: @escaping (Bool) -> Void) {
        let url = frame.safeRequest?.url ?? .empty
        let host = url.isFileURL ? .localhost : (url.host ?? "")
        self.permissions.permissions(.geolocation, requestedForDomain: host, decisionHandler: decisionHandler)
    }

    // https://github.com/WebKit/WebKit/blob/9d7278159234e0bfa3d27909a19e695928f3b31e/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h#L132
    @objc(_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:)
    @available(macOS 12, *)
    func webView(_ webView: WKWebView,
                 requestGeolocationPermissionFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let url = frame.safeRequest?.url ?? .empty
        let host = url.isFileURL ? .localhost : (url.host ?? "")
        self.permissions.permissions(.geolocation, requestedForDomain: host) { granted in
            decisionHandler(granted ? .grant : .deny)
        }
    }

    @objc(_webView:requestStorageAccessPanelForDomain:underCurrentDomain:completionHandler:)
    @available(macOS 10.14, iOS 12.0, *)
    func webView(_ webView: WKWebView,
                 requestStorageAccessPanelForDomain requestingDomain: String,
                 underCurrentDomain currentDomain: String,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert.storageAccessAlert(currentDomain: currentDomain,
                                               requestingDomain: requestingDomain)
        let response = alert.runModal()
        completionHandler(response == .alertFirstButtonReturn)
    }

    @objc(_webView:requestStorageAccessPanelForDomain:underCurrentDomain:forQuirkDomains:completionHandler:)
    @available(macOS 15.0, iOS 18.0, visionOS 2.0, *)
    func webView(_ webView: WKWebView,
                 requestStorageAccessPanelForDomain requestingDomain: String,
                 underCurrentDomain currentDomain: String,
                 forQuirkDomains quirkDomains: [String: [String]],
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert.storageAccessAlertForQuirkDomains(requestingDomain: requestingDomain,
                                                              currentDomain: currentDomain,
                                                              quirkDomains: Array(quirkDomains.keys))
        let response = alert.runModal()
        completionHandler(response == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let dialog = UserDialogType.openPanel(.init(parameters) { result in
            completionHandler(try? result.get())
        })
        let url = frame.safeRequest?.url ?? .empty
        let host = url.isFileURL ? .localhost : (url.host ?? "")
        userInteractionDialog = UserDialog(sender: .page(domain: host), dialog: dialog)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        createAlertDialog(initiatedByFrame: frame, prompt: message) { parameters in
            .alert(.init(parameters, callback: { result in
                switch result {
                case .failure:
                    completionHandler()
                case .success:
                    completionHandler()
                }
            }))
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        createAlertDialog(initiatedByFrame: frame, prompt: message) { parameters in
            .confirm(.init(parameters, callback: { result in
                switch result {
                case .failure:
                    completionHandler(false)
                case .success(let alertResult):
                    completionHandler(alertResult)
                }
            }))
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        createAlertDialog(initiatedByFrame: frame, prompt: prompt, defaultInputText: defaultText) { parameters in
            .textInput(.init(parameters, callback: { result in
                switch result {
                case .failure:
                    completionHandler(nil)
                case .success(let alertResult):
                    completionHandler(alertResult)
                }
            }))
        }
    }

    private func createAlertDialog(initiatedByFrame frame: WKFrameInfo, prompt: String, defaultInputText: String? = nil, queryCreator: (JSAlertParameters) -> JSAlertQuery) {
        let parameters = JSAlertParameters(
            domain: frame.safeRequest?.url?.host ?? "",
            prompt: prompt,
            defaultInputText: defaultInputText
        )
        let alertQuery = queryCreator(parameters)
        let dialog = UserDialogType.jsDialog(alertQuery)
        let url = frame.safeRequest?.url ?? .empty
        let host = url.isFileURL ? .localhost : (url.host ?? "")
        userInteractionDialog = UserDialog(sender: .page(domain: host), dialog: dialog)
    }

    func webViewDidClose(_ webView: WKWebView) {
        delegate?.closeTab(self)
    }

    func runPrintOperation(for frameHandle: FrameHandle?, in webView: WKWebView, completionHandler: ((Bool) -> Void)? = nil) {
        guard let printOperation = webView.printOperation(for: frameHandle) else { return }

        if printOperation.view?.frame.isEmpty == true {
            printOperation.view?.frame = webView.bounds
        }

        runPrintOperation(printOperation, completionHandler: completionHandler)
    }

    func runPrintOperation(_ printOperation: NSPrintOperation, completionHandler: ((Bool) -> Void)? = nil) {
        let dialog = UserDialogType.print(.init(printOperation) { result in
            completionHandler?((try? result.get()) ?? false)
        })
        userInteractionDialog = UserDialog(sender: .user, dialog: dialog)
    }

    @objc(_webView:printFrame:)
    func webView(_ webView: WKWebView, printFrame frameHandle: FrameHandle?) {
        self.runPrintOperation(for: frameHandle, in: webView)
    }

    @objc(_webView:printFrame:pdfFirstPageSize:completionHandler:)
    func webView(_ webView: WKWebView, printFrame frameHandle: FrameHandle?, pdfFirstPageSize size: CGSize, completionHandler: @escaping () -> Void) {
        self.runPrintOperation(for: frameHandle, in: webView) { _ in completionHandler() }
    }

    @preconcurrency @MainActor
    func print(pdfHUD: WKPDFHUDViewWrapper? = nil) {
        if let pdfHUD {
            Self.expectedSaveDataToFileCallback = { [weak self] url in
                guard let self, let url,
                      let pdfDocument = PDFDocument(url: url) else {
                    assertionFailure("Could not load PDF document from \(url?.path ?? "<nil>")")
                    return
                }
                // Set up NSPrintOperation
                guard let printOperation = pdfDocument.printOperation(for: .shared, scalingMode: .pageScaleNone, autoRotate: false) else {
                    assertionFailure("Could not print PDF document")
                    return
                }

                self.runPrintOperation(printOperation) { _ in
                    try? FileManager.default.removeItem(at: url)
                }
            }
            saveWebContent(pdfHUD: pdfHUD, location: .temporary)
            return
        }

        self.runPrintOperation(for: nil, in: self.webView)
    }

}

extension Tab: WKInspectorDelegate {
    @MainActor
    func inspector(_ inspector: NSObject, openURLExternally url: NSURL?) {
        let tab = Tab(content: url.map { Tab.Content.url($0 as URL, source: .link) } ?? .none,
                      burnerMode: BurnerMode(isBurner: burnerMode.isBurner),
                      webViewSize: webView.superview?.bounds.size ?? .zero)
        delegate?.tab(self, createdChild: tab, of: .window(active: true, burner: burnerMode.isBurner))
    }

    // Private WebKit delegate method to detect when developer tools inspector is attached
    @objc(_webView:didAttachLocalInspector:)
    func webView(_ webView: WKWebView, didAttachLocalInspector inspector: NSObject) {
        // Fire pixel when developer tools are opened
        PixelKit.fire(GeneralPixel.developerToolsOpened, frequency: .dailyAndCount)
    }

    @objc(_webView:hasVideoInPictureInPictureDidChange:)
    func webView(_ webView: WKWebView, hasVideoInPictureInPictureDidChange hasVideoInPictureInPicture: Bool) {
        if hasVideoInPictureInPicture {
            // Fire pixel when Picture-in-Picture is activated
            PixelKit.fire(GeneralPixel.pictureInPictureVideoPlayback, frequency: .dailyAndCount)
        }
    }

}
