### Integration

Serve the entire folder found under `build/<PLATFORM>/pages/release-notes`

### Platform Integrations

So far, the following platforms are supported

- macOS (Sparkle build only)
- Windows

---

### Release notes payload examples

#### Release notes loading

```json
{
    "status": "loading"
    "currentVersion": "1.0.1",
    "lastUpdate": 1718878097,
}
```

#### Release notes loaded

```json
{
    "status": "loaded",
    "currentVersion": "1.0.1",
    "latestVersion": "1.0.1",
    "lastUpdate": 1718878098,
    "releaseTitle": "May 20 2024",
    "releaseNotes": [
        "Startup Boost Enabled! DuckDuckGo will now run a background task whenever you startup your computer to help it launch faster.",
        "Fixed an issue where Microsoft Teams links wouldn't open the Teams app.",
        "Improved credential autofill on websites in Dutch, French, German, Italian, Spanish, and Swedish."
    ],
    "releaseNotesPrivacyPro": [
        "Personal Information Removal update! The list of data broker sites we can scan and remove your info from is growing.",
        "Privacy Pro is currently available to U.S. residents only"
    ]
}
```

#### Update ready

```json
{
    "status": "updateReady",
    "currentVersion": "1.0.1",
    "latestVersion": "1.2.0",
    "lastUpdate": 1718878099,
    "releaseTitle": "June 20 2024",
    "releaseNotes": [
        "Startup Boost Enabled! DuckDuckGo will now run a background task whenever you startup your computer to help it launch faster.",
        "Fixed an issue where Microsoft Teams links wouldn't open the Teams app.",
        "Improved credential autofill on websites in Dutch, French, German, Italian, Spanish, and Swedish."
    ],
    "releaseNotesPrivacyPro": [
        "Personal Information Removal update! The list of data broker sites we can scan and remove your info from is growing.",
        "Privacy Pro is currently available to U.S. residents only"
    ]
}
```

## Contributing

TODO
