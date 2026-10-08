//
//  QRCodeScannerView.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import SwiftUI
import AVFoundation

struct QRCodeScannerView: UIViewRepresentable {

    let scanningQueue: ScanningQueue

    let onCameraUnavailable: () -> Void

    init(onQRCodeScanned: @escaping (String) async -> Bool, onCameraUnavailable: @escaping () -> Void) {
        scanningQueue = ScanningQueue(onQRCodeScanned)
        self.onCameraUnavailable = onCameraUnavailable
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = AutoResizeLayersView()
        context.coordinator.start(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {

        let session: AVCaptureSession
        let metadataOutput = AVCaptureMetadataOutput()
        let cameraView: QRCodeScannerView
        var captureCodes = true

        private let sessionQueue = DispatchQueue(label: "com.duckduckgo.sync.qrCodeScanner.session", qos: .userInitiated)

        init(_ cameraView: QRCodeScannerView) {
            self.cameraView = cameraView
            self.session = AVCaptureSession()
            super.init()
        }

        func start(_ uiView: UIView) {
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            uiView.layer.addSublayer(previewLayer)
            previewLayer.frame = uiView.bounds
            previewLayer.videoGravity = .resizeAspectFill

            sessionQueue.async {
                guard self.configureSession() else {
                    DispatchQueue.main.async {
                        self.cameraView.onCameraUnavailable()
                    }
                    return
                }
                self.session.startRunning()
            }
        }

        func stop() {
            sessionQueue.async {
                self.session.stopRunning()
            }
        }

        private func configureSession() -> Bool {
            guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: backCamera) else {
                return false
            }

            session.beginConfiguration()
            defer { session.commitConfiguration() }

            session.sessionPreset = .high
            guard session.canAddInput(input), session.canAddOutput(metadataOutput) else {
                return false
            }
            session.addInput(input)
            session.addOutput(metadataOutput)
            metadataOutput.metadataObjectTypes = [.qr]
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            return true
        }

        // This gets get called on the main queue
        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {

            assert(Thread.isMainThread)

            guard captureCodes,
                  metadataObjects.count == 1,
                  let codeObject = metadataObjects[0] as? AVMetadataMachineReadableCodeObject,
                  let code = codeObject.stringValue else { return }

            captureCodes = false
            Task { @MainActor in
                let codeAccepted = await cameraView.scanningQueue.codeScanned(code)
                if !codeAccepted {
                    captureCodes = true
                }
            }
        }
    }

}

private class AutoResizeLayersView: UIView {

    override var frame: CGRect {
        didSet {
            layer.sublayers?.forEach {
                $0.frame = self.bounds
                if let preview = $0 as? AVCaptureVideoPreviewLayer {
                    preview.connection?.videoOrientation = UIDevice.current.orientation.avCapture
                }
            }
        }
    }

}

private extension UIDeviceOrientation {

    var avCapture: AVCaptureVideoOrientation {
        switch self {
        // For some reason if the device orientenation is landscape left, the video needs to be landscape right and visa-versa
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        case .portrait: return .portrait
        default: return .portrait
        }
    }

}

actor ScanningQueue {

    var onQRCodeScanned: (String) async -> Bool

    init(_ onQRCodeScanned: @escaping (String) async -> Bool) {
        self.onQRCodeScanned = onQRCodeScanned
    }

    /// Returns true if scanning should stop
    func codeScanned(_ code: String) async -> Bool {
        return await onQRCodeScanned(code)
    }

}
