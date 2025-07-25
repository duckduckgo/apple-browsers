# DuckDuckGo Apple Browsers

This repo contains the source code for the DuckDuckGo iOS and macOS browsers, and the libraries that are shared between them to provide cross-platform features.

## Building

### Submodules

We use submodules, so you will need to bring them into the project in order to build and run it:

Run `git submodule update --init --recursive`

### iOS developer details

If you're not part of the DuckDuckGo team, you should provide your Apple developer account id, app id, and group id prefix in an `ExternalDeveloper.xcconfig` file. To do that:

1. Run `cp iOS/Configuration/DuckDuckGoDeveloper.xcconfig iOS/Configuration/ExternalDeveloper.xcconfig`
2. Edit `iOS/Configuration/ExternalDeveloper.xcconfig` and change the values of all fields
3. Clean and rebuild the project

### macOS developer details

If you're not part of the DuckDuckGo team, go to Signing & Capabilities to select your team and custom bundle identifier.

### Dependencies

We use Swift Package Manager for dependency management, which shouldn't require any additional set up.

### SwiftLint

We use [SwifLint](https://github.com/realm/SwiftLint) for enforcing Swift style and conventions, so you'll need to [install it](https://github.com/realm/SwiftLint#installation).

## Terminology

We have taken steps to update our terminology and remove words with problematic racial connotations, most notably the change to `main` branches, `allow lists`, and `blocklists`.

## Contribute

Please refer to the [contributing](CONTRIBUTING.md) doc.

## Discuss

Contact us at https://duckduckgo.com/feedback if you have feedback, questions or want to chat. You can also use the feedback forms embedded within our mobile & desktop apps - to do so please navigate to the app's settings menu and select "Send Feedback".

## License

DuckDuckGo is distributed under the Apache 2.0 [license](https://github.com/duckduckgo/apple-browsers/blob/master/LICENSE.md).