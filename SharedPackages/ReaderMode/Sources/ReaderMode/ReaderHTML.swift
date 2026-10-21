//
//  ReaderHTML.swift
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

import Foundation
import SwiftSoup

enum ReaderHTML {
    static func render(content: String, title: String, author: String?, sourceURL: URL, theme: ReaderTheme) throws -> String {
        let document = try SwiftSoup.parseBodyFragment(content)
        try document.select("script, style, iframe, frame, frameset, form, input, button, textarea, select, object, embed, svg, math, template").remove()
        for element in try document.select("a[href], img[src]") {
            let attribute = element.tagName() == "a" ? "href" : "src"
            let value = try element.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: value, relativeTo: sourceURL)?.absoluteURL,
               ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                try element.attr(attribute, url.absoluteString)
            } else {
                try element.removeAttr(attribute)
            }
        }
        if let heading = document.body()?.children().first(), heading.tagName() == "h1", try heading.text() == title {
            try heading.remove()
        }
        if let author, let byline = document.body()?.children().first(), byline.tagName() == "p", try byline.text() == author {
            try byline.remove()
        }
        let allowlist = try Whitelist.none()
            .addTags("article", "section", "div", "p", "h1", "h2", "h3", "h4", "h5", "h6", "a", "img",
                     "figure", "figcaption", "blockquote", "pre", "code", "ul", "ol", "li", "dl", "dt", "dd",
                     "strong", "em", "b", "i", "u", "s", "sup", "sub", "br", "hr", "table", "thead", "tbody", "tfoot", "tr", "th", "td", "caption")
            .addAttributes("a", "href")
            .addAttributes("img", "src", "alt")
            .addProtocols("a", "href", "http", "https")
            .addProtocols("img", "src", "http", "https")
        let settings = OutputSettings().prettyPrint(pretty: false)
        let cleaned = try SwiftSoup.clean(document.body()?.html() ?? "", sourceURL.absoluteString, allowlist, settings) ?? ""
        let byline = author.map { "<p class=byline>\(escape($0))</p>" } ?? ""
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="no-referrer">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: http:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-src 'none'; upgrade-insecure-requests">
        <title>\(escape(title))</title><style>
        :root { color-scheme: light dark; font: 20px/1.65 Georgia, serif; }
        html { background: \(theme.background.css); color: \(theme.text.css); }
        body { margin: auto; padding: 24px; max-width: 38em; overflow-wrap: anywhere; }
        h1,h2,h3 { line-height: 1.25; } h1 { font-size: 1.8em; }
        img { max-width: 100%; height: auto; } figure { margin: 1em 0; }
        pre,code { white-space: pre-wrap; font: 0.85em/1.5 monospace; }
        pre,body > article > code { display: block; padding: 1em; background: \(theme.codeBackground.css); }
        table { display: block; overflow-x: auto; border-collapse: collapse; }
        td,th { padding: 0.4em; border: 1px solid \(theme.border.css); } a { color: \(theme.link.css); }
        .byline { font-size: 0.85em; color: \(theme.secondaryText.css); }
        </style></head><body><h1>\(escape(title))</h1>\(byline)<article>\(cleaned)</article></body></html>
        """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

/// Light and dark colors for the rendered reader page.
public struct ReaderTheme: Sendable, Equatable {
    /// An sRGB color with components from 0 to 1.
    public struct Color: Sendable, Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        /// A `#RRGGBBAA` hex string; components are clamped, so the output is always safe to embed in CSS.
        var css: String {
            "#" + [red, green, blue, alpha].map { component in
                let value = component.isFinite ? min(max(component, 0), 1) : 0
                return String(format: "%02X", Int((value * 255).rounded()))
            }.joined()
        }
    }

    /// A color for light appearance and one for dark appearance.
    public struct ColorPair: Sendable, Equatable {
        let light: Color
        let dark: Color

        public init(light: Color, dark: Color) {
            self.light = light
            self.dark = dark
        }

        var css: String { "light-dark(\(light.css),\(dark.css))" }
    }

    let background: ColorPair
    let text: ColorPair
    let secondaryText: ColorPair
    let link: ColorPair
    let codeBackground: ColorPair
    let border: ColorPair

    public init(background: ColorPair, text: ColorPair, secondaryText: ColorPair,
                link: ColorPair, codeBackground: ColorPair, border: ColorPair) {
        self.background = background
        self.text = text
        self.secondaryText = secondaryText
        self.link = link
        self.codeBackground = codeBackground
        self.border = border
    }
}
