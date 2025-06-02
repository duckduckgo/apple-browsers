//
//  QRCodeView.swift
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

import Foundation
import UIKit
import SwiftUI

struct QRCodeView: View {
    let string: String
    let desiredSize: Int

    var body: some View {
        Image(uiImage: generateQRCode(from: string, renderSize: 2 * desiredSize))
            .resizable()
            .interpolation(.none)
            .padding(4)
            .background(Color.white)
            .frame(width: CGFloat(desiredSize), height: CGFloat(desiredSize))
    }

    func generateQRCode(from text: String, renderSize: Int) -> UIImage {
        let context = CIContext()
        let data = Data(text.utf8)

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else {
            assertionFailure("Failed to generate QR code")
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }

        let baseSize = outputImage.extent.size.width
        let scaleFactor = floor(CGFloat(renderSize) / baseSize)

        guard scaleFactor >= 1 else {
            assertionFailure("Render size too small for sharp QR code")
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }

        let transformed = outputImage.transformed(by: .init(scaleX: scaleFactor, y: scaleFactor))
        let colored = transformed.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(color: .black),
            "inputColor1": CIColor(color: .white)
        ])

        if let cgImage = context.createCGImage(colored, from: colored.extent) {
            return UIImage(cgImage: cgImage)
        }

        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }
}
