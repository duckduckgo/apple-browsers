// PROTOTYPE - throwaway, do not ship.
//
// Inline selection toolbar: selecting text shows a Duck.ai toolbar just above the selection (or floating over it at the
// bottom of the viewport when the selection runs past the screen). "Ask Duck.ai…" leads, then the selection skills that
// fit the selection - single word, code, question, long passage or plain text, in another language or not, on the page
// or in an editable field - and every action opens in the Duck.ai sidebar. Ask attaches the selection to the sidebar
// without a prompt. After an action, or on right-click, the toolbar collapses to the Duck.ai icon, which re-expands it
// while the text stays selected. The AI Chat settings toggles turn the tools off, or make them open collapsed.
//
// Runs in an isolated content world (WritingAssistanceUserScript), so the page can't reach the native bridge. Top frame
// only. F9 freezes the UI for screenshots.
(() => {
  // Duck.ai (including the sidebar) and DuckDuckGo's own pages get no toolbar: the sidebar is where the toolbar's
  // actions land, and offering them inside it again would be circular.
  const isOwnPage = /(^|\.)(duck\.ai|duckduckgo\.com)$/.test(location.hostname) || location.protocol === 'duck:';
  if (window.top !== window || isOwnPage || window.__ddgWritingAssistPrototype) {
    return;
  }
  window.__ddgWritingAssistPrototype = true;

  const bridge = window.webkit?.messageHandlers?.writingAssistance;
  const MIN_CHARS = 2;

  // Screenshot mode: F9 freezes the prototype UI exactly as it is - no click-away, key or selection changes.
  const FREEZE_KEY = 'F9';
  let frozen = false;

  // 16x16 outline path data, drawn with a 1.4px round stroke.
  const ICON_PATHS = {
    summarize: 'M3 4h10M3 8h10M3 12h6',
    explain: 'M1.75 8a6.25 6.25 0 1 0 12.5 0a6.25 6.25 0 1 0 -12.5 0M6.3 6.2a1.8 1.8 0 1 1 2.5 1.7c-.5.2-.8.6-.8 1.1v.4M8 11.6v.1',
    translate: 'M2 3.5h7M5.5 2v1.5M3.5 3.5c.5 2.5 2.5 4.5 5 5.5M7.5 3.5c-.5 2.5-2.5 4.5-5 5.5M8.5 14l3-7 3 7M9.5 12h4',
    grammar: 'M3 8.5l3 3 7-7',
    shorten: 'M1.5 8h5M9.5 8h5M4 5.5L6.5 8 4 10.5M12 5.5L9.5 8l2.5 2.5',
    expand: 'M1.5 8h4M10.5 8h4M4 5.5L1.5 8 4 10.5M12 5.5l2.5 2.5-2.5 2.5M8 4v8',
    tone: 'M2.5 4h2M7.5 4h6M2.5 8h6.5M12 8h1.5M2.5 12h1M6.5 12h7M4.5 4a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0 -3 0M9 8a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0 -3 0M3.5 12a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0 -3 0',
    keypoints: 'M6 4h8M6 8h8M6 12h8M2.8 4h.01M2.8 8h.01M2.8 12h.01',
    answer: 'M2.5 3.5h11v7h-6l-3 2.5v-2.5h-2z',
    define: 'M3 2.5h7.5a2 2 0 0 1 2 2v9H5a2 2 0 0 1-2-2zM3 11.5a2 2 0 0 1 2-2h7.5',
    code: 'M5.5 4.5L2 8l3.5 3.5M10.5 4.5L14 8l-3.5 3.5',
    bug: 'M5.5 6.5a2.5 2.5 0 0 1 5 0V10a2.5 2.5 0 0 1-5 0zM8 6.5v6M5.5 8.5H2.5M13.5 8.5h-3M3 5l2.5 1.5M13 5l-2.5 1.5M3 12.5l2.5-1M13 12.5l-2.5-1M6.5 4.5L5.5 3M9.5 4.5l1-1.5',
    comment: 'M2.5 12.5l3-9M7 6h6.5M7 9h6.5M7 12h4',
    word: 'M2 12.5L5 4l3 8.5M3 9.5h4M10 7.5h4M10 10.5h3',
    chevronDown: 'M4 6l4 4 4-4',
    check: 'M3 8.5l3 3 7-7',
  };

  // The address bar's Duck.ai toggle icon (DesignSystemImages AIChat-Toggle-Color-16).
  const DUCK_AI_ICON = `<svg viewBox="0 0 16 16" class="duckai" fill="none"><defs>
    <linearGradient id="wa-b" x1="8" x2="8" y1="0" y2="15.944" gradientUnits="userSpaceOnUse"><stop stop-color="#a7b7fd"/><stop offset="1" stop-color="#3969ef"/></linearGradient>
    <linearGradient id="wa-c" x1="8" x2="8" y1="15.944" y2="0" gradientUnits="userSpaceOnUse"><stop stop-color="#2b55ca"/><stop offset="1" stop-color="#557ff3"/></linearGradient>
    <linearGradient id="wa-d" x1="8" x2="8" y1="2.5" y2="11.5" gradientUnits="userSpaceOnUse"><stop stop-color="#839df9"/><stop offset="1" stop-color="#3969ef"/></linearGradient></defs>
    <path fill="url(#wa-b)" d="M1.164 14.763c-.441.51-.014 1.284.65 1.17 2.655-.457 7.306-1.338 9.199-2.206C13.938 12.667 16 10.111 16 7.125 16 3.19 12.418 0 8 0S0 3.19 0 7.125c0 1.974.902 3.76 2.358 5.051.32.283.38.773.1 1.095z"/>
    <path fill="url(#wa-c)" d="M15 7.125c0 2.495-1.729 4.72-4.328 5.662l-.039.014-.037.017c-.838.384-2.376.803-4.114 1.19a99 99 0 0 1-4.03.797l.762-.878c.68-.785.487-1.898-.193-2.5-1.227-1.087-1.973-2.55-2.019-4.147L1 7.125C1 3.848 4.022 1 8 1V0l-.207.003C3.54.099.11 3.153.003 6.94L0 7.125c0 1.913.846 3.649 2.223 4.929l.135.122c.32.283.38.773.1 1.096l-1.293 1.491c-.442.51-.015 1.284.65 1.17 2.654-.456 7.305-1.338 9.198-2.206C13.938 12.667 16 10.111 16 7.125l-.002-.184C15.888 3.091 12.349.001 8 .001v1c3.916 0 6.905 2.759 6.998 5.97z"/>
    <path fill="#fff" d="M7.632 2.787c.096-.383.64-.383.736 0l.438 1.753c.203.815.84 1.45 1.654 1.654l1.753.438c.383.096.383.64 0 .736l-1.753.438c-.815.203-1.45.84-1.654 1.654l-.438 1.753c-.096.383-.64.383-.736 0L7.194 9.46A2.27 2.27 0 0 0 5.54 7.806l-1.753-.438c-.383-.096-.383-.64 0-.736l1.753-.438A2.27 2.27 0 0 0 7.194 4.54z"/>
    <path fill="url(#wa-d)" d="M6.662 2.544C7 1.195 8.867 1.154 9.3 2.418l.038.126.438 1.753c.114.457.47.813.927.927l1.753.438c1.392.348 1.392 2.328 0 2.676l-1.753.438c-.457.114-.813.47-.927.927l-.438 1.753c-.348 1.392-2.328 1.392-2.676 0l-.438-1.753a1.27 1.27 0 0 0-.927-.927l-1.753-.438c-1.392-.348-1.392-2.328 0-2.676l1.753-.438c.457-.114.813-.47.927-.927zM8 5.271A3.27 3.27 0 0 1 6.27 7 3.27 3.27 0 0 1 8 8.729 3.27 3.27 0 0 1 9.729 7 3.27 3.27 0 0 1 8 5.27Z"/>
    <path fill="#fff" d="M7.632 2.787c.096-.383.64-.383.736 0l.438 1.753c.203.815.84 1.45 1.654 1.654l1.753.438c.383.096.383.64 0 .736l-1.753.438c-.815.203-1.45.84-1.654 1.654l-.438 1.753c-.096.383-.64.383-.736 0L7.194 9.46A2.27 2.27 0 0 0 5.54 7.806l-1.753-.438c-.383-.096-.383-.64 0-.736l1.753-.438A2.27 2.27 0 0 0 7.194 4.54z"/>
  </svg>`;

  const CSS = `
    * { box-sizing: border-box; }
    .layer {
      position: fixed; inset: 0; pointer-events: none;
      font: 13px/1.4 -apple-system, BlinkMacSystemFont, system-ui, sans-serif; color: var(--text);
      --surface: #ffffff; --hover: rgba(0,0,0,.06); --text: #1c1c1c; --muted: #6b6b6b;
      --border: rgba(0,0,0,.12);
      --shadow: 0 8px 28px rgba(0,0,0,.16), 0 1px 3px rgba(0,0,0,.12);
    }
    @media (prefers-color-scheme: dark) {
      .layer {
        --surface: #2b2b2b; --hover: rgba(255,255,255,.08); --text: #f2f2f2; --muted: #a6a6a6;
        --border: rgba(255,255,255,.14);
        --shadow: 0 8px 28px rgba(0,0,0,.5), 0 1px 3px rgba(0,0,0,.4);
      }
    }
    .layer > * { pointer-events: auto; }
    [hidden] { display: none !important; }
    button { font: inherit; color: inherit; background: none; border: 0; padding: 0; margin: 0; cursor: pointer; }
    svg { width: 16px; height: 16px; flex: none; display: block; }
    .ico { fill: none; stroke: currentColor; stroke-width: 1.4; stroke-linecap: round; stroke-linejoin: round; }
    .float { position: fixed; left: 0; top: 0; }
    .fade { animation: fade .12s ease-out; }
    @keyframes fade { from { transform: translateY(-4px); opacity: 0; } to { transform: none; opacity: 1; } }
    .panel { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; box-shadow: var(--shadow); }

    .tb-bar { display: flex; align-items: center; height: 36px; padding: 0 4px; border-radius: 10px; white-space: nowrap; }
    .tb-divider { width: 1px; height: 20px; background: var(--border); margin: 0 4px; }
    .tb-action { display: inline-flex; align-items: center; gap: 6px; height: 28px; padding: 0 10px; border-radius: 7px; }
    .tb-action:hover, .tb-action.active { background: var(--hover); }
    .tb-action .chev-down { width: 12px; height: 12px; color: var(--muted); }
    .tb-ask { padding-left: 4px; }
    .tb-options { display: flex; flex-direction: column; gap: 2px; min-width: 168px; max-height: 320px; overflow-y: auto; padding: 4px; border-radius: 10px; }
    .tb-option { display: flex; align-items: center; height: 30px; padding: 0 12px; border-radius: 6px; text-align: left; white-space: nowrap; }
    .tb-option:hover { background: var(--hover); }
    .tb-reopen { width: 28px; height: 28px; display: grid; place-items: center; border-radius: 7px; }
    .tb-reopen:hover { background: var(--hover); }
    .tb-fold { display: flex; align-items: center; gap: 2px; overflow: hidden; white-space: nowrap; transition: max-width .2s ease, opacity .15s ease; }
    .tb-fold.folded { opacity: 0; }
    .tb-sent { gap: 4px; color: var(--muted); font-size: 12px; }
    .tb-sent .ico { width: 14px; height: 14px; margin-left: 4px; }
    .tb-sent span { padding-right: 8px; }

    .toast { position: fixed; left: 50%; bottom: 60px; transform: translateX(-50%); max-width: min(520px, calc(100vw - 32px)); padding: 10px 14px; border-radius: 8px; background: #111; color: #fff; font: 12px/1.4 system-ui, sans-serif; box-shadow: 0 4px 18px rgba(0,0,0,.35); }
    .toast b { display: block; margin-bottom: 2px; }
  `;

  // ---------- Selection skills ----------
  //
  // `types` is matched against the selection's shape, `editable` (when set) against whether the selection is in an
  // editable field.
  const SKILLS = [
    { name: 'fix-grammar', label: 'Fix Grammar', icon: 'grammar', order: 11, types: ['word', 'text', 'long', 'question'], editable: true, prompt: 'Fix the spelling and grammar of the selected text. Reply with only the corrected text.' },
    { name: 'shorten', label: 'Shorten', icon: 'shorten', order: 12, types: ['text', 'long'], editable: true, prompt: 'Rewrite the selected text to be shorter, keeping its meaning. Reply with only the rewritten text.' },
    { name: 'expand', label: 'Expand', icon: 'expand', order: 13, types: ['text', 'question'], editable: true, prompt: 'Rewrite the selected text to be longer and more detailed, keeping its meaning. Reply with only the rewritten text.' },
    { name: 'change-tone', label: 'Tone', icon: 'tone', order: 14, types: ['text', 'long', 'question'], editable: true, parameter: 'tone', prompt: 'Rewrite the selected text in a {tone} tone. Reply with only the rewritten text.' },
    { name: 'reword', label: 'Reword', icon: 'word', order: 15, types: ['word'], editable: true, prompt: 'Suggest a few better alternatives for the selected word, each with a short note on when to use it.' },
    { name: 'add-comments', label: 'Add Comments', icon: 'comment', order: 16, types: ['code'], editable: true, prompt: 'Rewrite the selected code with clear comments added. Keep the code itself unchanged.' },
    { name: 'summarize', label: 'Summarize', icon: 'summarize', order: 20, types: ['text', 'long'], prompt: 'Summarize the selected text.' },
    { name: 'translate', label: 'Translate', icon: 'translate', order: 30, types: ['word', 'text', 'long', 'question'], parameter: 'language', prompt: 'Translate the selected text into {language}.' },
    { name: 'explain', label: 'Explain', icon: 'explain', order: 40, types: ['text', 'long', 'question'], editable: false, prompt: 'Explain the selected text in plain language.' },
    { name: 'key-points', label: 'Key Points', icon: 'keypoints', order: 50, types: ['long'], editable: false, prompt: 'List the key points of the selected text.' },
    { name: 'define', label: 'Define', icon: 'define', order: 60, types: ['word'], prompt: 'Define the selected word and give a short example sentence.' },
    { name: 'answer', label: 'Answer', icon: 'answer', order: 70, types: ['question'], editable: false, prompt: 'Answer the selected question.' },
    { name: 'explain-code', label: 'Explain Code', icon: 'code', order: 80, types: ['code'], prompt: 'Explain what the selected code does, step by step.' },
    { name: 'find-bugs', label: 'Find Bugs', icon: 'bug', order: 90, types: ['code'], prompt: 'Review the selected code and point out bugs or risky behavior, with suggested fixes.' },
  ];
  const ASK = { name: 'ask', label: 'Ask Duck.ai…' };

  const TONES = ['Professional', 'Casual', 'Friendly', 'Confident', 'Direct'];
  // Offered after the user's own language, which always comes first.
  const LANGUAGES = ['en', 'es', 'fr', 'de', 'it', 'pt', 'ja', 'zh', 'ko'];
  const USER_TAG = navigator.language || 'en';

  function languageName(tag, locale) {
    try {
      return new Intl.DisplayNames([locale], { type: 'language' }).of(tag) ?? tag;
    } catch {
      return tag;
    }
  }

  const LANGUAGE_OPTIONS = [USER_TAG, ...LANGUAGES.filter(tag => tag !== USER_TAG.split('-')[0])].map(value => ({ value, label: languageName(value, USER_TAG) }));
  const TONE_OPTIONS = TONES.map(tone => ({ value: tone, label: tone }));

  // Prompts are English, so the target language is named in English too.
  function promptFor(skill, parameter) {
    switch (skill.parameter) {
      case 'tone':
        return skill.prompt.replace('{tone}', parameter.toLowerCase());
      case 'language':
        return skill.prompt.replace('{language}', languageName(parameter.split('-')[0], 'en'));
      default:
        return skill.prompt;
    }
  }

  // The AI Chat settings toggles (enabled, expanded). Null until the browser answers, so a page never shows the toolbar
  // before it knows the tools are on.
  let settings = null;

  function requestSettings(onLoaded) {
    if (!bridge) {
      return;
    }
    bridge.postMessage({ name: 'getSettings' }).then(result => {
      settings = result ?? null;
      if (!settings?.enabled) {
        ui.hide();
      }
      onLoaded?.();
    }).catch(() => {});
  }

  // ---------- Selection model ----------

  function deepActiveElement() {
    let active = document.activeElement;
    while (active?.shadowRoot?.activeElement) {
      active = active.shadowRoot.activeElement;
    }
    return active;
  }

  // Password fields are excluded on purpose: the real feature must never offer to send them anywhere.
  function isTextField(node) {
    if (node instanceof HTMLTextAreaElement) {
      return !node.readOnly && !node.disabled;
    }
    return node instanceof HTMLInputElement && ['text', 'search', 'email', 'url', ''].includes(node.type) && !node.readOnly && !node.disabled;
  }

  function editableHostOf(node) {
    const element = node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement;
    if (!element?.isContentEditable) {
      return null;
    }
    let hostElement = element;
    while (hostElement.parentElement?.isContentEditable) {
      hostElement = hostElement.parentElement;
    }
    return hostElement;
  }

  function pointRect(x, y) {
    return { left: x, right: x, top: y, bottom: y, width: 0, height: 0 };
  }

  // Text fields expose no geometry for their selection, so lay the field's text out again in a hidden mirror with the same
  // box and font, wrap the selected part in a span, and map the span's line boxes back onto the field.
  const MIRROR_STYLES = [
    'boxSizing', 'width', 'borderTopWidth', 'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth', 'borderStyle',
    'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft', 'fontStyle', 'fontVariant', 'fontWeight', 'fontStretch',
    'fontSize', 'fontFamily', 'lineHeight', 'letterSpacing', 'wordSpacing', 'textTransform', 'textIndent', 'tabSize',
  ];

  function fieldSelectionRects(field, start, end) {
    const style = getComputedStyle(field);
    const mirror = document.createElement('div');
    MIRROR_STYLES.forEach(name => (mirror.style[name] = style[name]));
    Object.assign(mirror.style, {
      position: 'fixed', left: '0', top: '0', height: 'auto', overflow: 'hidden', visibility: 'hidden', borderColor: 'transparent',
      whiteSpace: field instanceof HTMLInputElement ? 'pre' : 'pre-wrap',
      overflowWrap: 'break-word',
    });
    mirror.textContent = field.value.slice(0, start);
    const marked = document.createElement('span');
    marked.textContent = field.value.slice(start, end);
    mirror.append(marked);
    // Inside our shadow root so the page never sees the extra element.
    layer.append(mirror);
    const origin = mirror.getBoundingClientRect();
    const box = field.getBoundingClientRect();
    const dx = box.left - origin.left - field.scrollLeft;
    const dy = box.top - origin.top - field.scrollTop;
    // Clipped to the field, since part of the selection can be scrolled out of view inside it.
    const lines = [...marked.getClientRects()]
      .map(r => ({ left: Math.max(r.left + dx, box.left), right: Math.min(r.right + dx, box.right), top: Math.max(r.top + dy, box.top), bottom: Math.min(r.bottom + dy, box.bottom) }))
      .filter(r => r.right > r.left && r.bottom > r.top)
      .map(r => ({ ...r, width: r.right - r.left, height: r.bottom - r.top }));
    mirror.remove();
    if (!lines.length) {
      return { bounds: pointRect(box.left + 12, box.top + 12) };
    }
    const bounds = {
      left: Math.min(...lines.map(r => r.left)),
      right: Math.max(...lines.map(r => r.right)),
      top: Math.min(...lines.map(r => r.top)),
      bottom: Math.max(...lines.map(r => r.bottom)),
    };
    return { bounds: { ...bounds, width: bounds.right - bounds.left, height: bounds.bottom - bounds.top } };
  }

  function readSelection() {
    const active = deepActiveElement();
    if (isTextField(active)) {
      const { selectionStart: start, selectionEnd: end } = active;
      const text = start == null ? '' : active.value.slice(start, end);
      if (text.trim().length < MIN_CHARS) {
        return null;
      }
      return { text, kind: 'field', editable: true, element: active, rects: () => fieldSelectionRects(active, start, end) };
    }
    if (active instanceof HTMLInputElement || active instanceof HTMLTextAreaElement) {
      return null;
    }

    const selection = window.getSelection();
    if (!selection || selection.isCollapsed || selection.rangeCount === 0) {
      return null;
    }
    const text = selection.toString();
    if (text.trim().length < MIN_CHARS) {
      return null;
    }
    const range = selection.getRangeAt(0).cloneRange();
    const editableHost = editableHostOf(range.commonAncestorContainer);
    return { text, kind: editableHost ? 'richtext' : 'page', editable: !!editableHost, element: editableHost, range, rects: () => ({ bounds: range.getBoundingClientRect() }) };
  }

  // ---------- Classifying the selection ----------

  const USER_LANGUAGE = languageName(USER_TAG.split('-')[0], 'en');

  const SCRIPT_LANGUAGES = [
    [/\p{Script=Han}/gu, 'Chinese'],
    [/\p{Script=Hangul}/gu, 'Korean'],
    [/\p{Script=Cyrillic}/gu, 'Russian'],
    [/\p{Script=Arabic}/gu, 'Arabic'],
    [/\p{Script=Hebrew}/gu, 'Hebrew'],
    [/\p{Script=Greek}/gu, 'Greek'],
    [/\p{Script=Devanagari}/gu, 'Hindi'],
    [/\p{Script=Thai}/gu, 'Thai'],
  ];
  const KANA = /[\p{Script=Hiragana}\p{Script=Katakana}]/gu;
  // English is listed first so it wins ties.
  const STOPWORDS = {
    English: ['the', 'and', 'is', 'of', 'to', 'in', 'that', 'it', 'you', 'for', 'with', 'this', 'are', 'was', 'be'],
    Spanish: ['el', 'la', 'los', 'las', 'de', 'que', 'y', 'en', 'es', 'por', 'una', 'con', 'para', 'del', 'sus'],
    French: ['le', 'la', 'les', 'de', 'et', 'est', 'une', 'des', 'que', 'pour', 'dans', 'pas', 'qui', 'avec', 'nous'],
    German: ['der', 'die', 'das', 'und', 'ist', 'nicht', 'ein', 'eine', 'zu', 'mit', 'den', 'sich', 'auch', 'von', 'wir'],
    Italian: ['il', 'di', 'che', 'e', 'la', 'per', 'non', 'sono', 'una', 'con', 'gli', 'del', 'della', 'questo'],
    Portuguese: ['o', 'a', 'de', 'que', 'e', 'do', 'da', 'em', 'um', 'para', 'não', 'uma', 'com', 'os', 'você'],
  };
  const LANGUAGE_TAGS = {
    English: 'en', Spanish: 'es', French: 'fr', German: 'de', Italian: 'it', Portuguese: 'pt', Japanese: 'ja', Chinese: 'zh',
    Korean: 'ko', Russian: 'ru', Arabic: 'ar', Hebrew: 'he', Greek: 'el', Hindi: 'hi', Thai: 'th',
  };
  const ACCENT_HINTS = { Spanish: /[ñ¿¡]/i, French: /[çœèêàù]/i, German: /[ßäöü]/i, Portuguese: /[ãõ]/i };
  const CODE_SIGNALS = /[{};]|=>|\(\)|===?|!==?|\b(function|const|let|var|def|return|import|public|private|async|await)\b/g;

  // A writing system only decides the language when most letters use it, so one Japanese sentence inside a long English
  // selection doesn't make the whole selection "Japanese". Japanese mixes kana with Han, so any kana tips Han to Japanese.
  function detectLanguage(text) {
    const count = pattern => text.match(pattern)?.length ?? 0;
    const majority = (text.match(/\p{L}/gu)?.length ?? 0) / 2;
    const kana = count(KANA);
    if (kana && kana + count(SCRIPT_LANGUAGES[0][0]) > majority) {
      return 'Japanese';
    }
    const [language, letters] = SCRIPT_LANGUAGES.map(([pattern, name]) => [name, count(pattern)]).reduce((a, b) => (b[1] > a[1] ? b : a));
    if (letters > majority) {
      return language;
    }
    const words = text.toLowerCase().match(/\p{L}+/gu) ?? [];
    if (words.length < 3) {
      return USER_LANGUAGE;
    }
    const scored = Object.entries(STOPWORDS).map(([language, list]) => [language, words.filter(w => list.includes(w)).length + (ACCENT_HINTS[language]?.test(text) ? 2 : 0)]);
    const [best, score] = scored.reduce((winner, next) => (next[1] > winner[1] ? next : winner));
    return score >= 2 ? best : USER_LANGUAGE;
  }

  // Classified once per selection, from the selected text and its element only - nothing is sent anywhere to decide.
  function contextOf(selection) {
    if (selection.context) {
      return selection.context;
    }
    const text = selection.text.trim();
    const words = text.split(/\s+/);
    const node = selection.kind === 'field' ? selection.element : selection.range.commonAncestorContainer;
    const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
    // Indented lines catch languages like Python that have few of the punctuation signals. Signals must also be dense,
    // so a long mixed selection that merely contains a snippet reads as prose rather than code.
    const codeSignals = (text.match(CODE_SIGNALS)?.length ?? 0) + (text.match(/^[ \t]{2,}\S/gm)?.length ?? 0);
    const isCode = !!element?.closest('pre, code, kbd, samp') || (codeSignals >= 3 && codeSignals * 25 >= text.length);
    const language = detectLanguage(text);
    const sentenceCount = text.match(/[.!?](\s|$)/g)?.length ?? 0;
    const shape = isCode
      ? 'code'
      : words.length === 1 && language === USER_LANGUAGE && /^[\p{L}'’-]{2,30}$/u.test(text)
        ? 'word'
        : /\?\s*$/.test(text)
          ? 'question'
          : text.length > 280 || sentenceCount > 2
            ? 'long'
            : 'text';
    selection.context = { shape, language, differentLanguage: !isCode && language !== USER_LANGUAGE };
    return selection.context;
  }

  function fits(skill, selection) {
    return skill.types.includes(contextOf(selection).shape) && (skill.editable == null || skill.editable === selection.editable);
  }

  // Skill order, except that translating leads when the selection is in another language.
  function actionsFor(selection) {
    const { differentLanguage } = contextOf(selection);
    const rank = skill => (differentLanguage && skill.parameter === 'language' ? -1 : skill.order);
    return SKILLS.filter(skill => fits(skill, selection)).sort((a, b) => rank(a) - rank(b));
  }

  // Text in another language has one obvious target, the user's own, so translating runs straight away instead of
  // opening a dropdown. Text already in the user's language offers the other languages.
  function directParameter(skill, selection) {
    return skill.parameter === 'language' && contextOf(selection).differentLanguage ? USER_TAG : undefined;
  }

  // The selection's own language is no use as a translation target.
  function optionsFor(skill, selection) {
    if (skill.parameter === 'tone') {
      return TONE_OPTIONS;
    }
    if (skill.parameter !== 'language' || directParameter(skill, selection)) {
      return [];
    }
    const sourceTag = LANGUAGE_TAGS[contextOf(selection).language];
    return LANGUAGE_OPTIONS.filter(option => option.value.split('-')[0] !== sourceTag);
  }

  // Page script can call click() on our buttons; only a real user click may open the sidebar.
  const trusted = handler => event => event.isTrusted && handler(event);

  function openInSidebar(selection, skill, parameter) {
    if (!bridge) {
      toast('Duck.ai sidebar not reachable', 'Browser messaging is not available on this page.');
      return;
    }
    bridge.postMessage({
      name: 'run',
      data: skill === ASK ? { action: 'ask', text: selection.text } : { action: 'skill', prompt: promptFor(skill, parameter), text: selection.text },
    }).catch(() => {});
  }

  // ---------- DOM helpers ----------

  // Sites that enforce Trusted Types reject plain strings in innerHTML.
  let htmlPolicy = null;
  try {
    htmlPolicy = window.trustedTypes?.createPolicy('ddg-wa-prototype', { createHTML: s => s }) ?? null;
  } catch {
    // Policy names can be restricted by CSP; the UI then only works on pages without Trusted Types.
  }
  const html = markup => (htmlPolicy ? htmlPolicy.createHTML(markup) : markup);

  function el(tag, className, markup) {
    const node = document.createElement(tag);
    if (className) {
      node.className = className;
    }
    if (markup != null) {
      node.innerHTML = html(markup);
    }
    return node;
  }

  function icon(name, extraClass = '') {
    return `<svg viewBox="0 0 16 16" class="ico ${extraClass}"><path d="${ICON_PATHS[name] ?? ''}"/></svg>`;
  }

  // Places a fixed element at (left, top), flipping so its bottom edge sits at `flipBottom` when it would overflow the viewport.
  function place(node, { left, top, flipBottom }) {
    const { width, height } = node.getBoundingClientRect();
    const margin = 8;
    let y = top;
    if (y + height > innerHeight - margin && flipBottom != null) {
      y = flipBottom - height;
    }
    node.style.left = `${Math.round(Math.min(Math.max(left, margin), innerWidth - width - margin))}px`;
    node.style.top = `${Math.round(Math.min(Math.max(y, margin), innerHeight - height - margin))}px`;
  }

  function retrigger(node, className) {
    node.classList.remove(className);
    void node.offsetWidth;
    node.classList.add(className);
  }

  // ---------- Inline toolbar ----------

  const SENT_VISIBLE_MS = 1500;

  function createToolbar(layer) {
    const bar = el('div', 'tb-bar panel float');
    const optionsRow = el('div', 'tb-options panel float');
    layer.append(bar, optionsRow);
    // A toolbar that grows near the right edge of the window is pulled back on screen once it has finished growing.
    bar.addEventListener('transitionend', () => reposition());
    let selection = null;
    let collapsed = false;
    let sentTimer = 0;
    // Built once per selection; collapsing and expanding only fold these open and shut, so nothing is re-rendered.
    let logo = null;
    let actions = null;
    let sent = null;

    function show(next, { expanded = true } = {}) {
      selection = next;
      // Visible before rendering, so the folds can measure their content.
      bar.hidden = false;
      closeOptions();
      renderBar(expanded);
      retrigger(bar, 'fade');
      reposition();
    }

    function hide() {
      selection = null;
      clearTimeout(sentTimer);
      bar.hidden = true;
      closeOptions();
    }

    // After an action the toolbar shrinks to the Duck.ai icon instead of disappearing, so the selection - still selected -
    // keeps a way back to its actions. A brief "Sent to Duck.ai" confirms an action, then folds away.
    function collapse({ confirm = false } = {}) {
      collapsed = true;
      clearTimeout(sentTimer);
      closeOptions();
      fold(actions, false);
      fold(sent, confirm);
      logo.setAttribute('aria-label', 'Show Duck.ai actions');
      if (confirm) {
        sentTimer = setTimeout(() => fold(sent, false), SENT_VISIBLE_MS);
      }
    }

    function expand() {
      collapsed = false;
      clearTimeout(sentTimer);
      fold(actions, true);
      fold(sent, false);
      logo.setAttribute('aria-label', 'Hide Duck.ai actions');
    }

    // Animates between zero and the content's own width, which a max-width transition can do and a width:auto cannot.
    function fold(node, open) {
      node.style.maxWidth = open ? `${node.scrollWidth}px` : '0px';
      node.classList.toggle('folded', !open);
    }

    // Ask leads, without an icon of its own: it sits against the Duck.ai icon, so the two read as one "Ask Duck.ai…" item.
    function renderBar(expanded) {
      const [ask, ...buttons] = [ASK, ...actionsFor(selection)].map(skill => {
        const options = skill === ASK ? [] : optionsFor(skill, selection);
        const glyph = skill === ASK ? '' : icon(skill.icon);
        const node = el('button', 'tb-action', `${glyph}<span></span>${options.length ? icon('chevronDown', 'chev-down') : ''}`);
        node.querySelector('span').textContent = skill.label;
        node.addEventListener('click', trusted(() => (options.length ? toggleOptions(skill, options, node) : run(skill, skill === ASK ? undefined : directParameter(skill, selection)))));
        return node;
      });
      ask.classList.add('tb-ask');
      collapsed = !expanded;
      clearTimeout(sentTimer);
      logo = el('button', 'tb-reopen', DUCK_AI_ICON);
      logo.setAttribute('aria-label', expanded ? 'Hide Duck.ai actions' : 'Show Duck.ai actions');
      logo.addEventListener('click', trusted(() => (collapsed ? expand() : collapse())));
      actions = el('div', 'tb-fold');
      actions.append(ask, ...buttons.flatMap(button => [el('div', 'tb-divider'), button]));
      sent = el('div', 'tb-fold tb-sent folded', `${icon('check')}<span>Sent to Duck.ai</span>`);
      sent.style.maxWidth = '0px';
      bar.replaceChildren(logo, actions, sent);
      // From max-width "none" the first size is not animated, so a fresh toolbar appears at its starting size: full, or
      // just the icon when the tools are set to open collapsed.
      fold(actions, expanded);
    }

    function toggleOptions(skill, options, button) {
      const wasOpen = button.classList.contains('active');
      closeOptions();
      if (wasOpen) {
        return;
      }
      button.classList.add('active');
      optionsRow.replaceChildren(
        ...options.map(option => {
          const chip = el('button', 'tb-option');
          chip.textContent = option.label;
          chip.addEventListener('click', trusted(() => run(skill, option.value)));
          return chip;
        }),
      );
      optionsRow.hidden = false;
      retrigger(optionsRow, 'fade');
      reposition();
    }

    function closeOptions() {
      bar.querySelectorAll('.tb-action.active').forEach(b => b.classList.remove('active'));
      optionsRow.hidden = true;
    }

    function run(skill, parameter) {
      openInSidebar(selection, skill, parameter);
      collapse({ confirm: true });
    }

    // Just above the selection, left-aligned with it. A selection at the top of the screen gets the toolbar below it;
    // one that runs past the bottom of the viewport gets it floating over the selection at the bottom of the viewport.
    function reposition() {
      if (!selection) {
        return;
      }
      const margin = 8;
      const gap = 8;
      const { bounds } = selection.rects();
      bar.style.visibility = bounds.bottom > 0 && bounds.top < innerHeight ? '' : 'hidden';
      const { height } = bar.getBoundingClientRect();
      const above = bounds.top - gap - height;
      const below = bounds.bottom + gap;
      const pinned = innerHeight - margin - height;
      const top = bounds.bottom > innerHeight
        ? pinned
        : above >= margin
          ? above
          : below + height <= innerHeight - margin
            ? below
            : pinned;
      place(bar, { left: bounds.left, top });
      if (!optionsRow.hidden) {
        const barBox = bar.getBoundingClientRect();
        const active = bar.querySelector('.tb-action.active')?.getBoundingClientRect() ?? barBox;
        place(optionsRow, { left: active.left - 4, top: barBox.bottom + 4, flipBottom: barBox.top - 4 });
      }
    }

    // The same selection reported again (a Shift key-up, say) keeps the toolbar as it is rather than re-rendering it,
    // which would undo a collapse.
    const isShowing = next => selection !== null && !bar.hidden && selection.text === next.text;

    function track(next) {
      selection = next;
      reposition();
    }

    function shrink(next) {
      if (isShowing(next)) {
        track(next);
        collapse();
      } else {
        show(next, { expanded: false });
      }
    }

    hide();
    return {
      show,
      hide,
      track,
      shrink,
      reposition,
      isShowing,
      isPinned: () => !optionsRow.hidden,
    };
  }

  // ---------- Shadow host, toast ----------

  const host = document.createElement('ddg-writing-assist-prototype');
  host.style.cssText = 'all: initial; position: fixed; inset: 0; pointer-events: none; z-index: 2147483647;';
  const shadow = host.attachShadow({ mode: 'closed' });
  // A constructed stylesheet isn't subject to the page's style-src CSP, unlike a <style> element.
  try {
    const sheet = new CSSStyleSheet();
    sheet.replaceSync(CSS);
    shadow.adoptedStyleSheets = [sheet];
  } catch {
    shadow.innerHTML = html(`<style>${CSS}</style>`);
  }
  const layer = el('div', 'layer');
  const chrome = el('div', 'layer');
  shadow.append(layer, chrome);

  // Clicking our UI must not collapse the page selection or steal focus from the field being edited.
  shadow.addEventListener('mousedown', event => event.preventDefault());
  // Keep pages from treating keystrokes or clicks in our UI as their own (e.g. "/" focusing a site's search box).
  ['keydown', 'keyup', 'keypress', 'mousedown', 'mouseup', 'click'].forEach(type => shadow.addEventListener(type, event => event.stopPropagation()));

  let toastTimer = 0;
  const toastNode = el('div', 'toast');
  toastNode.hidden = true;
  chrome.append(toastNode);
  function toast(title, detail) {
    toastNode.innerHTML = html('<b></b><div></div>');
    toastNode.querySelector('b').textContent = title;
    toastNode.querySelector('div').textContent = detail;
    toastNode.hidden = false;
    retrigger(toastNode, 'fade');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => (toastNode.hidden = true), 4000);
  }

  const ui = createToolbar(layer);

  // ---------- Page wiring ----------

  const isOurs = event => event.composedPath().includes(host);

  const offerToolbar = selection => {
    if (!settings?.enabled) {
      ui.hide();
    } else if (ui.isShowing(selection)) {
      ui.track(selection);
    } else {
      ui.show(selection, { expanded: settings.expanded });
    }
  };

  function refreshFromSelection() {
    const current = readSelection();
    if (current && settings === null) {
      requestSettings(() => readSelection()?.text === current.text && offerToolbar(current));
    } else if (current) {
      offerToolbar(current);
    } else if (!ui.isPinned()) {
      ui.hide();
    }
  }

  // Ctrl-click opens the context menu on macOS, so it's left to the contextmenu listener like a right-click.
  const isMenuClick = event => event.button === 2 || (event.button === 0 && event.ctrlKey);

  // A right-click leaves the toolbar to the contextmenu listener, which shrinks it rather than hiding it.
  document.addEventListener('mousedown', event => !frozen && !isOurs(event) && !isMenuClick(event) && ui.hide(), true);
  // Only a primary-button release can finish a selection.
  document.addEventListener('mouseup', event => !frozen && !isOurs(event) && event.button === 0 && !event.ctrlKey && setTimeout(refreshFromSelection, 0), true);
  // The native menu has its own Duck.ai items, so the toolbar shrinks to the Duck.ai icon while it is open, and the
  // icon brings the actions back afterwards.
  document.addEventListener(
    'contextmenu',
    event => {
      if (!frozen && !isOurs(event)) {
        const selection = readSelection();
        if (selection && settings?.enabled) {
          ui.shrink(selection);
        } else {
          ui.hide();
        }
      }
    },
    true,
  );
  document.addEventListener(
    'keyup',
    event => {
      const selectAll = (event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'a';
      if (!frozen && !isOurs(event) && (event.shiftKey || event.key === 'Shift' || selectAll)) {
        refreshFromSelection();
      }
    },
    true,
  );
  document.addEventListener('selectionchange', () => {
    if (frozen || ui.isPinned()) {
      return;
    }
    const active = deepActiveElement();
    const collapsed = isTextField(active) ? active.selectionStart === active.selectionEnd : (window.getSelection()?.isCollapsed ?? true);
    if (collapsed) {
      ui.hide();
    }
  });
  window.addEventListener(
    'keydown',
    event => {
      if (event.key === FREEZE_KEY) {
        event.preventDefault();
        event.stopPropagation();
        frozen = !frozen;
        return;
      }
      if (!frozen && event.key === 'Escape') {
        ui.hide();
      }
    },
    true,
  );

  let frame = 0;
  const scheduleReposition = () => {
    cancelAnimationFrame(frame);
    frame = requestAnimationFrame(() => ui.reposition());
  };
  // Picks up settings changed while the page was open.
  document.addEventListener('visibilitychange', () => document.visibilityState === 'visible' && requestSettings());
  window.addEventListener('focus', () => requestSettings());
  window.addEventListener('scroll', scheduleReposition, { capture: true, passive: true });
  window.addEventListener('resize', scheduleReposition);

  const mount = () => {
    document.documentElement.append(host);
    requestSettings();
  };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', mount, { once: true });
  } else {
    mount();
  }
})();
