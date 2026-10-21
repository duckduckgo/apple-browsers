//
//  ReaderDocument.swift
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

public enum ReaderDocument {

    /// Extracted content comes from an arbitrary page, so the policy keeps any script that slips through from running.
    static let contentSecurityPolicy = "default-src 'none'; img-src * data:; style-src 'unsafe-inline'"

    public static func html(for article: ReaderArticle) -> String {
        let siteLine = article.siteName.map { "<p class=\"site\">\(escape($0))</p>\n" } ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(article.title))</title>
        <style>
        \(style)
        </style>
        </head>
        <body>
        <article>
        \(siteLine)<h1>\(escape(article.title))</h1>
        \(article.contentHTML)
        </article>
        </body>
        </html>
        """
    }

    static func escape(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
    }

    private static let style = """
    :root {
        color-scheme: light dark;
        --text: #1c1c1e;
        --secondary: #6e6e73;
        --background: #ffffff;
        --link: #3969ef;
        --rule: #e5e5ea;
    }
    @media (prefers-color-scheme: dark) {
        :root {
            --text: #f2f2f7;
            --secondary: #98989d;
            --background: #1c1c1e;
            --link: #7295f6;
            --rule: #3a3a3c;
        }
    }
    html { background: var(--background); }
    body {
        margin: 0;
        padding: 48px 24px 96px;
        color: var(--text);
        background: var(--background);
        font: 19px/1.6 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
        -webkit-font-smoothing: antialiased;
    }
    article { max-width: 680px; margin: 0 auto; overflow-wrap: break-word; }
    .site { margin: 0 0 8px; color: var(--secondary); font-size: 15px; text-transform: uppercase; letter-spacing: 0.04em; }
    h1 { margin: 0 0 32px; font-size: 34px; line-height: 1.2; }
    h2, h3, h4 { line-height: 1.3; margin: 1.6em 0 0.6em; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    img, video, figure { max-width: 100%; height: auto; }
    figure { margin: 1.5em 0; }
    figcaption { color: var(--secondary); font-size: 15px; }
    blockquote { margin: 1.5em 0; padding-left: 1em; border-left: 3px solid var(--rule); color: var(--secondary); }
    pre, code { font: 15px/1.5 ui-monospace, Menlo, monospace; }
    pre { overflow-x: auto; padding: 12px; border-radius: 8px; background: var(--rule); }
    table { border-collapse: collapse; display: block; overflow-x: auto; }
    td, th { border: 1px solid var(--rule); padding: 4px 8px; }
    hr { border: none; border-top: 1px solid var(--rule); }
    """
}
