### Integration

Serve the entire folder found under `build/<PLATFORM>/pages/duckplayer`

### Platform Integrations

So far, the following platforms are supported

- Windows

---

## Contributing

### HTML
The main HTML file is located at `public/index.html`. You can edit this file directly

### CSS
The main stylesheet is located at `public/assets/player.css`. You can edit this file directly

### Javascript
JavaScript source files are located in the `src` directory. The build process will create a bundle and place it inside `public/generated`. 

This is why the `index.html` file has the following `<script>` tag.

```html
<script type="module" src="generated/js/index.js"></script>
```

Don't edit the generated files directly - any changes you make will not be reflected in the final build output. 

Instead, make your changes in `src/' and then run `npm run build.pages` from the `packages/special-pages` folder

