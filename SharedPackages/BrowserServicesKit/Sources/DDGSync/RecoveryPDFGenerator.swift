//
//  RecoveryPDFGenerator.swift
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

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

protocol PDFGeneratorHelping {

    associatedtype XFont
    associatedtype XColor

    var qrCodeYOffset: Int { get }
    var textCodeYOffset: Int { get }
    var textCodeFont: XFont { get }
    var textCodeColor: XColor { get }

    func pushGraphicsContext(_ context: CGContext)
    func popGraphicsContext()
    func flipContextIfNeeded(_ context: CGContext, boxHeight: CGFloat)
    func drawTemplate(_ imageData: Data, in rect: CGRect)

}

public struct RecoveryPDFGenerator {

    static let qrCodeSize = 175

    let helper: any PDFGeneratorHelping

    init(helper: any PDFGeneratorHelping) {
        self.helper = helper
    }

    public init() {
        self.init(helper: Helper())
    }

    public func generate(_ code: String) -> Data {
        let data = NSMutableData()

        let templateURL = Bundle.module.url(forResource: "SyncPDFTemplate", withExtension: "png")!
        guard let templateData = try? Data(contentsOf: templateURL) else {
            fatalError()
        }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &mediaBox, nil)!

        helper.pushGraphicsContext(context)
        defer {
            helper.popGraphicsContext()
        }

        // Prepare the PDF for drawing to
        context.beginPDFPage(nil)
        helper.flipContextIfNeeded(context, boxHeight: mediaBox.size.height)

        // Draw the template image
        helper.drawTemplate(templateData, in: CGRect(x: 0, y: 0, width: 612, height: 792))

        // Draw the text
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.55
        code.draw(in: CGRect(x: 290, y: helper.textCodeYOffset, width: 264, height: 1000), withAttributes: [
                .font: helper.textCodeFont,
                .foregroundColor: helper.textCodeColor,
                .paragraphStyle: paragraphStyle,
                .kern: 2
            ])

        // Draw the QRCode
        let cgImage = qrcode(code, size: Self.qrCodeSize)
        context.draw(cgImage, in: CGRect(x: 75, y: helper.qrCodeYOffset, width: Self.qrCodeSize, height: Self.qrCodeSize))

        // Flush the data to the PDF file
        context.endPDFPage()
        context.closePDF()

        return data as Data
    }

    func qrcode(_ text: String, size: Int) -> CGImage {
        let data = Data(text.utf8)
        let qrCodeFilter: CIFilter = CIFilter(name: "CIQRCodeGenerator")!
        qrCodeFilter.setValue(data, forKey: "inputMessage")
        qrCodeFilter.setValue("H", forKey: "inputCorrectionLevel")

        guard let naturalSize = qrCodeFilter.outputImage?.extent.width else {
            fatalError()
        }

        let scale = CGFloat(size) / naturalSize

        let transform = CGAffineTransform(scaleX: scale, y: scale)
        guard let outputImage = qrCodeFilter.outputImage?.transformed(by: transform) else {
            fatalError()
        }

        let colorParameters: [String: Any] = [
            "inputColor0": CIColor.black,
            "inputColor1": CIColor.white
        ]
        let coloredImage = outputImage.applyingFilter("CIFalseColor", parameters: colorParameters)

        guard let image = CIContext().createCGImage(coloredImage, from: outputImage.extent) else {
            fatalError()
        }
        return image
    }

}

#if os(macOS)

private struct Helper: PDFGeneratorHelping {

    let qrCodeYOffset: Int = 335
    let textCodeYOffset: Int = -480
    let textCodeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    var textCodeColor = NSColor.black

    func pushGraphicsContext(_ context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = .init(cgContext: context, flipped: false)
    }

    func popGraphicsContext() {
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawTemplate(_ imageData: Data, in rect: CGRect) {
        NSImage(data: imageData)?.draw(in: rect)
    }

    func flipContextIfNeeded(_ context: CGContext, boxHeight: CGFloat) {
        // no-op
    }

}

#endif

#if os(iOS)

private struct Helper: PDFGeneratorHelping {

    let qrCodeYOffset: Int = 280
    let textCodeYOffset: Int = 280
    let textCodeFont = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    var textCodeColor = UIColor.black

    func pushGraphicsContext(_ context: CGContext) {
        UIGraphicsPushContext(context)
    }

    func popGraphicsContext() {
        UIGraphicsPopContext()
    }

    func flipContextIfNeeded(_ context: CGContext, boxHeight: CGFloat) {
        let flipVertical: CGAffineTransform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: boxHeight)
        context.concatenate(flipVertical)
    }

    func drawTemplate(_ imageData: Data, in rect: CGRect) {
        UIImage(data: imageData)?.draw(in: rect)
    }

}

#endif
