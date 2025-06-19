//
//  QRCodeView.swift
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
import CoreImage.CIFilterBuiltins

struct QRCode: View {
    let string: String
    let desiredSize: Int

    var body: some View {
        Image(nsImage: generateQRCode(from: string, renderSize: 2 * desiredSize))
            .resizable()
            .interpolation(.none)
            .padding(4)
            .background(Color.white)
            .frame(width: CGFloat(desiredSize), height: CGFloat(desiredSize))
    }

    func generateQRCode(from text: String, renderSize: Int) -> NSImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else {
            return NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil) ?? NSImage()
        }

        let baseSize = outputImage.extent.size.width
        let scaleFactor = floor(CGFloat(renderSize) / baseSize)

        guard scaleFactor >= 1 else {
            return NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil) ?? NSImage()
        }

        let scaledImage = outputImage.transformed(by: .init(scaleX: scaleFactor, y: scaleFactor))

        let colored = scaledImage.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(color: .black) as Any,
            "inputColor1": CIColor(color: .white) as Any
        ])

        guard let cgImage = context.createCGImage(colored, from: colored.extent) else {
            return NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil) ?? NSImage()
        }

        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let nsImage = NSImage(cgImage: cgImage, size: size)
        return nsImage
    }

}
