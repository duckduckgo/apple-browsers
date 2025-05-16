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
    let context = CIContext()

    let string: String
    let desiredSize: Int

    init(string: String, desiredSize: Int) {
        self.string = string
        self.desiredSize = desiredSize
    }

    var body: some View {
        let qrCode = generateQRCode(from: string, desiredSize: desiredSize)
        Image(uiImage: qrCode)
            .resizable()
            .interpolation(.none)
            .frame(width: qrCode.size.width, height: qrCode.size.height)
    }

    func generateQRCode(from text: String, desiredSize: Int) -> UIImage {
        var qrImage = UIImage(systemName: "xmark.circle") ?? UIImage()

        let data = Data(text.utf8)
        guard let qrCodeFilter = CIFilter(name: "CIQRCodeGenerator") else { return qrImage }
        qrCodeFilter.setValue(data, forKey: "inputMessage")
        qrCodeFilter.setValue("L", forKey: "inputCorrectionLevel")

        guard let outputImage = qrCodeFilter.outputImage else {
            assertionFailure("Failed to generate QR code")
            return qrImage
        }

        let baseSize = outputImage.extent.size.width
        let size = CGFloat(desiredSize)

        let scaleFactor = floor(size / baseSize)

        guard scaleFactor >= 1 else {
            assertionFailure("Desired size too small for sharp QR code")
            return qrImage
        }

        // Scale the QR code using integer scaling
        let transform = CGAffineTransform(scaleX: scaleFactor, y: scaleFactor)
        let scaledImage = outputImage.transformed(by: transform)

        let imageWithBlackWhiteColor = scaledImage.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(color: .black),
            "inputColor1": CIColor(color: .white)
        ])

        if let image = context.createCGImage(imageWithBlackWhiteColor, from: imageWithBlackWhiteColor.extent) {
            qrImage = UIImage(cgImage: image)
        }

        return qrImage
    }

}
