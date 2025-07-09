This is an Error Page template page used as a placeholder to display a browser loading failure page.

### Integration

Serve the entire folder found under `build/<PLATFORM>/pages/errorpage`

### Platform Integration

So far, the following platforms are supported

- macOS

---

## Contributing

### HTML
The main HTML file is located at `src/index.html`. You can edit this file directly

### CSS
The main stylesheet is located at `src/style.css`. You can edit this file directly

The build process will create a bundle and place it inside `Sources/ContentScopeScripts/dist/pages/onboarding` 
on macOS - other platforms will be under `build/<PLATFORM>/pages/errorpage`

Don't edit the generated files directly - any changes you make will not be reflected in the final build output. 

Instead, make your changes in `src/` and then run `npm run build` from the root folder
  - or to build the special pages only (faster), run `npm run postbuild` instead

