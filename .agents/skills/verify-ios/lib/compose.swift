//
//  compose.swift
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

// Image compositor for verify-ios evidence. Uses only macOS frameworks that ship with Xcode, so it needs no installs.
//
//   xcrun swift compose.swift JOBS.json
//
// JOBS.json is a list of jobs, run in order; each failure is reported on its own line and the rest still run:
//   {"kind": "grid", "out": "a.png", "height": 720,
//    "rows": [{"label": "Before" | null, "cells": [{"path": "x.png" | null, "caption": "new-tab"}]}]}
//   {"kind": "poster", "out": "poster.png", "video": "recording.mp4", "height": 720}
// A grid scales every frame to `height`, captions each one below it, and labels each row on its left; a cell without
// a path is drawn as "not captured". A poster is the video's last frame with a play badge. Prints one JSON object:
// {"ok": [outs…], "failed": {out: reason}}. Exit 0 even when jobs fail; non-zero only when JOBS.json is unreadable.
import AppKit
import AVFoundation
import Foundation

struct Cell: Decodable { let path: String?; let caption: String }
struct Row: Decodable { let label: String?; let cells: [Cell] }
struct Job: Decodable {
    let kind: String
    let out: String
    let height: Int?
    let rows: [Row]?
    let video: String?
}

struct ComposeError: Error, CustomStringConvertible { let description: String }

let background = NSColor(calibratedWhite: 0.96, alpha: 1)
let gap = 24, captionHeight = 56, labelWidth = 220, pad = 24

func load(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw ComposeError(description: "cannot read \(path)")
    }
    return image
}

func write(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw ComposeError(description: "cannot write \(path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw ComposeError(description: "cannot write \(path)") }
}

func canvas(_ width: Int, _ height: Int, _ draw: (CGContext) -> Void) throws -> CGImage {
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw ComposeError(description: "cannot allocate a \(width)x\(height) canvas")
    }
    ctx.setFillColor(background.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    guard let image = ctx.makeImage() else { throw ComposeError(description: "cannot render the canvas") }
    return image
}

/// Draws `text` centred in `rect` (y up), wrapping at word boundaries and shrinking until it fits.
func text(_ text: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = NSColor(calibratedWhite: 0.2, alpha: 1)) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    var size = size
    var attrs: [NSAttributedString.Key: Any] = [:]
    var bounds = CGRect.zero
    repeat {
        attrs = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph]
        bounds = (text as NSString).boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                                                 options: .usesLineFragmentOrigin, attributes: attrs)
        size -= 2
    } while (bounds.height > rect.height || bounds.width > rect.width + 0.5) && size >= 10
    let box = CGRect(x: rect.minX, y: rect.midY - bounds.height / 2, width: rect.width, height: bounds.height)
    (text as NSString).draw(with: box, options: .usesLineFragmentOrigin, attributes: attrs)
}

func grid(_ job: Job) throws -> CGImage {
    let rows = job.rows ?? []
    let height = job.height ?? 720
    guard !rows.isEmpty, rows.allSatisfy({ !$0.cells.isEmpty }) else { throw ComposeError(description: "no frames") }
    let columns = rows.map(\.cells.count).max()!
    // Load every frame once, and size each column by its widest scaled frame so the rows line up.
    let images: [[CGImage?]] = try rows.map { row in try row.cells.map { cell in try cell.path.map(load) } }
    let widths: [Int] = (0..<columns).map { i in
        let scaled = images.compactMap { i < $0.count ? $0[i] : nil }.map { $0.width * height / $0.height }
        return scaled.max() ?? height * 1206 / 2622   // nothing captured in this column: an iPhone portrait frame
    }
    let labelled = rows.contains { $0.label != nil }
    let left = pad + (labelled ? labelWidth + gap : 0)
    let width = left + widths.reduce(0, +) + gap * (columns - 1) + pad
    let rowHeight = height + captionHeight
    let total = pad * 2 + rows.count * rowHeight + (rows.count - 1) * gap
    return try canvas(width, total) { ctx in
        for (r, row) in rows.enumerated() {
            let top = total - pad - r * (rowHeight + gap)   // y grows upwards
            let frameY = top - height
            if let label = row.label {
                text(label, in: CGRect(x: pad, y: frameY, width: labelWidth, height: height), size: 30, weight: .semibold)
            }
            var x = left
            for (i, cell) in row.cells.enumerated() {
                let slot = CGRect(x: x, y: frameY, width: widths[i], height: height)
                if let image = images[r][i] {
                    let w = image.width * height / image.height
                    let rect = CGRect(x: Int(slot.midX) - w / 2, y: frameY, width: w, height: height)
                    ctx.interpolationQuality = .high
                    ctx.draw(image, in: rect)
                    ctx.setStrokeColor(NSColor(calibratedWhite: 0.75, alpha: 1).cgColor)
                    ctx.setLineWidth(2)
                    ctx.stroke(rect.insetBy(dx: -1, dy: -1))
                } else {
                    ctx.setFillColor(NSColor(calibratedWhite: 0.88, alpha: 1).cgColor)
                    ctx.fill(slot)
                    text("not captured", in: slot, size: 26, color: NSColor(calibratedWhite: 0.45, alpha: 1))
                }
                text(cell.caption, in: CGRect(x: slot.minX, y: CGFloat(frameY - captionHeight), width: slot.width,
                                              height: CGFloat(captionHeight)), size: 26)
                x += widths[i] + gap
            }
        }
    }
}

func poster(_ job: Job) async throws -> CGImage {
    guard let video = job.video else { throw ComposeError(description: "no video") }
    let asset = AVURLAsset(url: URL(fileURLWithPath: video))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let duration = CMTimeGetSeconds(try await asset.load(.duration))
    guard duration.isFinite, duration > 0 else { throw ComposeError(description: "\(video) has no frames") }
    let at = CMTime(seconds: max(0, duration - 0.2), preferredTimescale: 600)   // the last frame: the end state
    let frame = try await generator.image(at: at).image
    let height = job.height ?? 720
    let width = frame.width * height / frame.height
    return try canvas(width, height) { ctx in
        ctx.interpolationQuality = .high
        ctx.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
        let d = CGFloat(min(width, height)) * 0.32
        let badge = CGRect(x: CGFloat(width) / 2 - d / 2, y: CGFloat(height) / 2 - d / 2, width: d, height: d)
        ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.55).cgColor)
        ctx.fillEllipse(in: badge)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: badge.minX + d * 0.38, y: badge.minY + d * 0.27))
        ctx.addLine(to: CGPoint(x: badge.minX + d * 0.38, y: badge.maxY - d * 0.27))
        ctx.addLine(to: CGPoint(x: badge.maxX - d * 0.25, y: badge.midY))
        ctx.closePath()
        ctx.fillPath()
    }
}

guard CommandLine.arguments.count == 2,
      let data = FileManager.default.contents(atPath: CommandLine.arguments[1]),
      let jobs = try? JSONDecoder().decode([Job].self, from: data) else {
    FileHandle.standardError.write("usage: compose.swift JOBS.json (a JSON list of jobs)\n".data(using: .utf8)!)
    exit(2)
}
var ok: [String] = [], failed: [String: String] = [:]
for job in jobs {
    do {
        switch job.kind {
        case "grid": try write(grid(job), to: job.out)
        case "poster": try write(await poster(job), to: job.out)
        default: throw ComposeError(description: "unknown kind \(job.kind)")
        }
        ok.append(job.out)
    } catch {
        failed[job.out] = "\(error)"
    }
}
let result = try JSONSerialization.data(withJSONObject: ["ok": ok, "failed": failed], options: [.sortedKeys])
print(String(data: result, encoding: .utf8)!)
