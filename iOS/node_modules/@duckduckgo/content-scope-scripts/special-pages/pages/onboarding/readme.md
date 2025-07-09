### Integration

Serve the entire folder found under `build/<PLATFORM>/pages/onboarding`

### Platform Integrations

So far, the following platforms are supported

- Windows
- macOS

### Translations

The languages currently supported are: de, en, es, fr, it, nl, pl, pt, ru.

When submitting translation jobs, make sure to only include those.

## Contributing

### HTML
The main HTML file is located at `public/index.html`. You can edit this file directly

### CSS
The main stylesheet is located at `public/assets/styles.css`. You can edit this file directly

### Javascript
JavaScript source files are located in the `src` directory. The build process will create a bundle and place it inside `public/generated`.

This is why the `index.html` file has the following `<script>` tag.

```html
<script type="module" src="generated/js/index.js"></script>
```

Don't edit the generated files directly - any changes you make will not be reflected in the final build output.

Instead, make your changes in `src/' and then run `npm run build.pages` from the `packages/special-pages` folder

### Test URL params

URL parameters can be used to override the default values of the onboarding flow's configuration. Supported parameters are:

- `locale` - Specifies the language to use for translations. Expects a language code (e.g., `en`, `de`, `fr`).
- `textLength` - Adjusts the length of translated strings, for testing layout with different text sizes (e.g., `short`, `long`).
- `display` - Controls which view is rendered. `app` renders the main onboarding flow, `components` renders the component showcase page.
- `platform` - Overrides the detected platform, for testing platform-specific styling (e.g., `macos`, `windows`).
- `order` - Specifies which predefined set of onboarding steps to use (e.g., `v1`, `v2`, `v3`).
- `exclude` - Removes specific steps from the onboarding flow. Can be used multiple times (e.g., `&exclude=welcome&exclude=systemSettings`).
- `page` - Sets the initial step to start the onboarding flow on (e.g., `systemSettings`).
- `adBlocking` - If set to `enabled`, adds a step for enabling ad blocking. If set to `youtube`, adds a step for enabling YouTube-only ad blocking.
