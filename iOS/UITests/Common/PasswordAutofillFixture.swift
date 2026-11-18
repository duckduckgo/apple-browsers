//
//  PasswordAutofillFixture.swift
//  DuckDuckGo
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
import Swifter

final class PasswordAutofillFixture {

    struct Credentials {
        let username: String
        let password: String
    }

    private let server = HttpServer()
    private let credentialsLock = NSLock()
    private var signupCredentials: Credentials?
    private var serverPort: Int?

    var credentialDomain: String {
        guard let serverPort else { return "" }
        return "localhost:\(serverPort)"
    }

    var signupURL: String { url(for: "/signup") }
    var standardLoginURL: String { url(for: "/standard-login") }
    var multistepLoginURL: String { url(for: "/multistep-login") }

    func start() throws {
        server.get["/signup"] = { _ in .ok(.html(Self.signupForm)) }
        server.post["/signup"] = { [weak self] request in
            guard let self else { return .notFound }
            guard let credentials = Self.signupCredentials(from: request) else {
                return .ok(.html(Self.resultPage("Signup was not captured")))
            }

            self.credentialsLock.lock()
            self.signupCredentials = credentials
            self.credentialsLock.unlock()
            return .ok(.html(Self.resultPage("Signup captured")))
        }
        server.get["/standard-login"] = { _ in .ok(.html(Self.standardLoginForm)) }
        server.post["/standard-login"] = { [weak self] request in
            guard let self else { return .notFound }
            return self.loginResponse(
                for: request,
                success: "Standard credentials match",
                failure: "Standard credentials mismatch")
        }
        server.get["/multistep-login"] = { _ in .ok(.html(Self.multistepLoginForm)) }
        server.post["/multistep-password"] = { [weak self] request in
            guard let self else { return .notFound }
            return self.loginResponse(
                for: request,
                success: "Multistep credentials match",
                failure: "Multistep credentials mismatch")
        }
        server.notFoundHandler = { _ in .notFound }

        try server.start(0, forceIPv4: true, priority: .userInitiated)
        serverPort = try server.port()
    }

    func stop() {
        server.stop()
    }

    var submittedSignupCredentials: Credentials? {
        credentialsLock.lock()
        defer { credentialsLock.unlock() }
        return signupCredentials
    }

    private func url(for path: String) -> String {
        guard let serverPort else { return "" }
        return "http://localhost:\(serverPort)\(path)"
    }

    private func loginResponse(for request: HttpRequest, success: String, failure: String) -> HttpResponse {
        let submitted = Self.credentials(from: request)
        let expected = submittedSignupCredentials
        let matches = submitted.map { actual in
            expected.map { actual.username == $0.username && actual.password == $0.password } ?? false
        } ?? false
        let result = matches ? success : failure
        return .ok(.html(Self.resultPage(result)))
    }

    private static func credentials(from request: HttpRequest) -> Credentials? {
        let fields = Dictionary(request.parseUrlencodedForm(), uniquingKeysWith: { _, latest in latest })
        guard let username = username(from: request),
              let password = fields["password"], !password.isEmpty else {
            return nil
        }
        return Credentials(username: username, password: password)
    }

    private static func signupCredentials(from request: HttpRequest) -> Credentials? {
        guard let credentials = credentials(from: request) else { return nil }
        let fields = Dictionary(request.parseUrlencodedForm(), uniquingKeysWith: { _, latest in latest })
        guard fields["confirmation"] == credentials.password else { return nil }
        return credentials
    }

    private static func username(from request: HttpRequest) -> String? {
        let fields = Dictionary(request.parseUrlencodedForm(), uniquingKeysWith: { _, latest in latest })
        guard let username = fields["username"], !username.isEmpty else { return nil }
        return username
    }

    private static let mobileHead = """
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      body { font: 17px -apple-system, sans-serif; margin: 16px; }
      label, input, button { display: block; margin: 12px 0; }
      input { box-sizing: border-box; width: 100%; font: inherit; padding: 8px; }
      button { font: inherit; padding: 8px 16px; }
      [hidden] { display: none; }
    </style>
    """

    private static func resultPage(_ result: String) -> String {
        "<html><head>\(mobileHead)<title>Password Autofill Fixture</title></head><body><h1>\(result)</h1></body></html>"
    }

    private static let signupForm = """
    <html><head>\(mobileHead)<title>Password generation during signup</title></head><body>
      <h2>Password generation during signup</h2>
      <form method="post" action="/signup">
        <label for="username">Email</label><input id="username" name="username" type="email" autocomplete="username">
        <label for="password">Password</label><input id="password" name="password" type="password" autocomplete="new-password" passwordrules="minlength: 5; maxlength: 10">
        <label for="confirmation">Confirm Password</label><input id="confirmation" name="confirmation" type="password" autocomplete="new-password">
        <button type="submit">Sign up</button>
      </form>
    </body></html>
    """

    private static let standardLoginForm = """
    <html><head>\(mobileHead)<title>Standard login</title></head><body>
      <h2>Sign in form</h2>
      <form method="post" action="/standard-login">
        <label for="username">Email</label><input id="username" name="username" type="email" autocomplete="username">
        <label for="password">Password</label><input id="password" name="password" type="password" autocomplete="current-password">
        <button type="submit">Sign in</button>
      </form>
    </body></html>
    """

    private static let multistepLoginForm = """
    <html><head>\(mobileHead)<title>Multistep login</title></head><body>
      <form method="post" action="/multistep-password" id="login">
        <h2>Log in</h2>
        <fieldset>
          <label for="username">Email</label><input id="username" name="username" type="email" autocomplete="username" required>
          <button type="button" id="continue">Continue</button>
        </fieldset>
        <fieldset id="password-container" hidden>
          <label for="password">Password</label><input id="password" name="password" type="password" autocomplete="current-password" required disabled>
          <button type="submit">Log in</button>
        </fieldset>
      </form>
      <script>
        const form = document.forms.login;
        const continueButton = document.getElementById('continue');
        const passwordContainer = document.getElementById('password-container');
        const passwordField = document.getElementById('password');
        continueButton.addEventListener('click', () => {
          if (form.elements.username.validity.valid) {
            passwordContainer.hidden = false;
            continueButton.hidden = true;
            passwordField.disabled = false;
          }
        });
      </script>
    </body></html>
    """
}
