// Cra ▸ Settings (pane://settings). The page reads and writes Cra's settings through
// window.craSettings, a bridge to the app (SettingsPageBrowser): state() reads everything,
// set(key, value) writes one setting, action(name, args) asks Cra to do something (a sheet, a file
// picker, another page). Cra calls craSettings._update(state) whenever a setting changes, here or
// anywhere else, so the page always shows what is saved.
(() => {
  'use strict';

  // MARK: Bridge

  const handler = () => window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.craSettings;
  const call = (message) => {
    const h = handler();
    return h ? h.postMessage(message) : Promise.reject(new Error('Settings opens in Pane.'));
  };
  const bridge = {
    state: () => call({ op: 'state' }),
    set: (key, value) => call({ op: 'set', key, value }),
    action: (name, args = {}) => call({ op: 'action', name, args }),
    section: (section) => call({ op: 'section', section }),
    _update: (state) => apply(state),
  };
  window.craSettings = bridge;

  // MARK: Icons (16 pt line glyphs, after SF Symbols)

  const ICONS = {
    general: '<circle cx="8" cy="8" r="2.2"/><path d="M8 1.8v1.6M8 12.6v1.6M14.2 8h-1.6M3.4 8H1.8M12.4 3.6l-1.1 1.1M4.7 11.3l-1.1 1.1M12.4 12.4l-1.1-1.1M4.7 4.7 3.6 3.6"/>',
    'search-engines': '<circle cx="7" cy="7" r="4.6"/><path d="M10.4 10.4 14 14"/>',
    appearance: '<path d="M8 1.8a6.2 6.2 0 1 0 0 12.4c.9 0 1.4-.6 1.4-1.3 0-.9-.7-1.2-.7-2 0-.8.6-1.3 1.4-1.3h1.5a2.6 2.6 0 0 0 2.6-2.6C14.2 4.1 11.4 1.8 8 1.8Z"/><circle cx="5" cy="7" r=".7"/><circle cx="7.4" cy="4.6" r=".7"/><circle cx="10.6" cy="5.2" r=".7"/>',
    'tabs-and-spaces': '<rect x="2" y="4.5" width="9.5" height="9.5" rx="2"/><path d="M4.5 2h7.5a2 2 0 0 1 2 2v7.5"/>',
    shortcuts: '<rect x="1.8" y="4" width="12.4" height="8" rx="1.8"/><path d="M4.5 6.6h.01M7 6.6h.01M9.5 6.6h.01M12 6.6h.01M5 9.6h6"/>',
    privacy: '<path d="M8 1.8 3 3.7v4c0 3.1 2.1 5.4 5 6.5 2.9-1.1 5-3.4 5-6.5v-4L8 1.8Z"/>',
    advanced: '<path d="M2.5 4.5h7M12.5 4.5h1M2.5 11.5h1M6.5 11.5h7"/><circle cx="11" cy="4.5" r="1.5"/><circle cx="5" cy="11.5" r="1.5"/>',
    profiles: '<circle cx="8" cy="5.6" r="2.8"/><path d="M2.8 14c.6-2.7 2.7-4.2 5.2-4.2s4.6 1.5 5.2 4.2"/>',
    extensions: '<path d="M6.2 2.5h3v1.2a1.3 1.3 0 1 0 2.6 0V2.5h1.7v4h-1.2a1.3 1.3 0 1 0 0 2.6h1.2v4.4H2.5V9.1h1.2a1.3 1.3 0 1 0 0-2.6H2.5v-4h3.7Z"/>',
    plugins: '<path d="M2 4.2c0-.7.5-1.2 1.2-1.2h3l1.4 1.6h5.2c.7 0 1.2.5 1.2 1.2v6.4c0 .7-.5 1.2-1.2 1.2H3.2c-.7 0-1.2-.5-1.2-1.2V4.2Z"/>',
    max: '<path d="M8 2.2 9.3 6.7 13.8 8l-4.5 1.3L8 13.8 6.7 9.3 2.2 8l4.5-1.3L8 2.2Z"/>',
    performance: '<path d="M2.4 11a5.6 5.6 0 1 1 11.2 0"/><path d="m8 11 2.6-3.4"/>',
    external: '<path d="M6 3h7v7M13 3 4 12"/>',
    edit: '<path d="M10.8 2.7 13.3 5.2 5.6 12.9 2.6 13.4l.5-3 7.7-7.7Z"/>',
    trash: '<path d="M3 4.5h10M6.4 4.5V3h3.2v1.5M4.4 4.5l.6 8.6c0 .5.5.9 1 .9h4c.5 0 1-.4 1-.9l.6-8.6"/>',
    reset: '<path d="M3 8a5 5 0 1 0 1.5-3.6"/><path d="M3 2.6v2.6h2.6"/>',
    check: '<path d="M3.5 8.5 6.5 11.5 12.5 4.5"/>',
    plus: '<path d="M8 3v10M3 8h10"/>',
    minus: '<circle cx="8" cy="8" r="5.6"/><path d="M5.5 8h5"/>',
    link: '<path d="M6.8 9.2a2.6 2.6 0 0 0 3.7 0l2-2a2.6 2.6 0 0 0-3.7-3.7l-.8.8M9.2 6.8a2.6 2.6 0 0 0-3.7 0l-2 2a2.6 2.6 0 0 0 3.7 3.7l.8-.8"/>',
    broom: '<path d="M11.5 2.5 8 7M5.2 8.4l3.4 2.6-1.6 2.6c-.4.6-1.2.8-1.8.4L2.8 12.3c-.6-.4-.7-1.2-.3-1.8l1.7-2.4 1 .3Z"/>',
  };
  const icon = (name, cls = '') => `<svg viewBox="0 0 16 16" class="${cls}" aria-hidden="true">${ICONS[name] || ''}</svg>`;

  const SECTIONS = [
    { id: 'general', title: 'General' },
    { id: 'search-engines', title: 'Search Engines' },
    { id: 'appearance', title: 'Appearance' },
    { id: 'tabs-and-spaces', title: 'Tabs & Spaces' },
    { id: 'shortcuts', title: 'Shortcuts' },
    { id: 'privacy', title: 'Privacy' },
    { id: 'advanced', title: 'Advanced' },
  ];
  // Under "More" in the sidebar; sections of the page like the rest (11 Nov 2026).
  const MORE = [
    { id: 'profiles', title: 'Profiles' },
    { id: 'extensions', title: 'Extensions' },
    { id: 'plugins', title: 'Plugins' },
    { id: 'max', title: 'Max' },
    { id: 'performance', title: 'Performance' },
  ];
  const ALL = SECTIONS.concat(MORE);

  // MARK: State

  let S = null;
  let current = 'general';
  let query = '';
  let controls = [];
  const listShown = new Map();

  const $ = (sel, root = document) => root.querySelector(sel);
  const value = (key) => (S && key in (S.extra || {})) ? S.extra[key] : (S && S.settings ? S.settings[key] : undefined);

  function el(tag, attrs = {}, ...children) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null || v === false) continue;
      if (k === 'class') e.className = v;
      else if (k === 'html') e.innerHTML = v;
      else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
      else if (k === 'dataset') Object.assign(e.dataset, v);
      else e.setAttribute(k, v === true ? '' : v);
    }
    for (const c of children.flat()) {
      if (c == null || c === false) continue;
      e.append(c instanceof Node ? c : document.createTextNode(String(c)));
    }
    return e;
  }

  let toastTimer = 0;
  function toast(text) {
    const t = $('#toast');
    t.textContent = text;
    t.classList.add('shown');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove('shown'), 2200);
  }

  window.craSettingsToast = (text) => toast(text);
  const fail = (e) => toast(typeof e === 'string' ? e : (e && e.message) || 'Pane couldn’t change that.');

  function write(key, v) {
    return bridge.set(key, v).then((s) => { if (s) apply(s); }).catch((e) => { fail(e); update(); });
  }
  function run(name, args) {
    return bridge.action(name, args).then((s) => { if (s) { apply(s); askPrompt(s.prompt); } return s; }).catch((e) => { fail(e); throw e; });
  }

  // MARK: Questions (11 Nov 2026): asked in Cra's own dialog, the one Quit Cra? and every alert use,
  // in the space's colours, so the page's questions look like the rest of Cra.

  /// {title, message, input, placeholder, confirmLabel, destructive, requiresInput} → Promise<{ok, value}>.
  function pageDialog(o) {
    return call({ op: 'dialog', title: o.title, message: o.message || '', input: o.input == null ? null : String(o.input),
      placeholder: o.placeholder || '', confirmLabel: o.confirmLabel || 'OK', destructive: !!o.destructive, requiresInput: !!o.requiresInput })
      .then((r) => ({ ok: !!(r && r.ok), value: r && typeof r.value === 'string' ? r.value.trim() : null }))
      .catch(() => ({ ok: false, value: null }));
  }

  /// A question Cra asks after an action (a plugin to add, settings to import): yes runs its action.
  let promptShown = null;
  function askPrompt(p) {
    if (!p || promptShown === p.confirm + p.title) return;
    promptShown = p.confirm + p.title;
    pageDialog({ title: p.title, message: p.message, confirmLabel: p.confirmLabel }).then((r) => {
      promptShown = null;
      run(r.ok ? p.confirm : 'dismissPrompt').catch(() => {});
    });
  }

  /// Create Profile…: Cra's own Create a new Profile dialog (its name, then which spaces use it).
  function createProfileDialog() { run('newProfileDialog').catch(() => {}); }

  // MARK: Rows

  function row({ title, detail, trailing, cls, search, onclick }) {
    const label = el('div', { class: 'label' }, el('div', { class: 'title' }, title), detail != null ? el('div', { class: 'detail' }, detail) : null);
    const r = el('div', { class: `row${cls ? ' ' + cls : ''}${onclick ? ' clickable' : ''}`, onclick, dataset: { search: [title, typeof detail === 'string' ? detail : '', search || ''].join(' ').toLowerCase() } },
      label, trailing ? el('div', { class: 'trailing' }, trailing) : null);
    return r;
  }

  function control(update) { controls.push(update); }

  function toggle(key, title, detail, { disabled, onchange } = {}) {
    const input = el('input', { type: 'checkbox', role: 'switch', 'aria-label': title });
    const sw = el('label', { class: 'switch' }, input, el('span', { class: 'track' }), el('span', { class: 'knob' }));
    const detailEl = typeof detail === 'function' ? el('span') : detail;
    const r = row({ title, detail: detailEl, trailing: sw, search: typeof detail === 'string' ? detail : '' });
    input.addEventListener('change', () => (onchange ? onchange(input.checked) : write(key, input.checked)));
    r.addEventListener('click', (e) => { if (e.target === r || e.target.closest('.label')) { if (!input.disabled) { input.checked = !input.checked; input.dispatchEvent(new Event('change')); } } });
    control(() => {
      input.checked = !!value(key);
      const off = typeof disabled === 'function' ? disabled() : !!disabled;
      input.disabled = off;
      r.classList.toggle('disabled', off);
      if (typeof detail === 'function') { const d = detail(); detailEl.textContent = d || ''; detailEl.parentElement && detailEl.parentElement.classList.toggle('hidden', !d); }
    });
    return r;
  }

  function select(key, title, options, detail, { disabled, onchange, current: get } = {}) {
    const s = el('select', { 'aria-label': title });
    s.addEventListener('change', () => (onchange ? onchange(s.value) : write(key, s.value)));
    control(() => {
      const opts = typeof options === 'function' ? options() : options;
      const sig = JSON.stringify(opts);
      if (s.dataset.sig !== sig) {
        s.dataset.sig = sig;
        s.replaceChildren(...opts.map((o) => o.separator ? el('hr') : el('option', { value: o.value, disabled: o.disabled }, o.label)));
      }
      s.value = get ? get() : String(value(key));
      s.disabled = typeof disabled === 'function' ? disabled() : !!disabled;
    });
    const r = row({ title, detail, trailing: s, search: (typeof options === 'function' ? [] : options).map((o) => o.label).join(' ') });
    control(() => r.classList.toggle('disabled', s.disabled));
    return r;
  }

  function button(title, detail, label, action, args, { primary } = {}) {
    const b = el('button', { class: `btn${primary ? ' primary' : ''}`, type: 'button' }, label);
    b.addEventListener('click', () => run(action, typeof args === 'function' ? args() : args).catch(() => {}));
    const detailEl = typeof detail === 'function' ? el('span') : detail;
    if (typeof detail === 'function') control(() => { detailEl.textContent = detail() || ''; });
    return row({ title, detail: detailEl, trailing: b });
  }

  function card(header, rows, { footnote, trailing } = {}) {
    const head = header ? el('div', { class: 'section-header' }, el('h3', {}, header), trailing || null) : null;
    const body = el('div', { class: 'card' }, rows);
    const foot = footnote ? el('p', { class: 'footnote' }) : null;
    if (foot) {
      if (typeof footnote === 'function') control(() => { const t = footnote(); foot.textContent = t || ''; foot.classList.toggle('hidden', !t); });
      else foot.textContent = footnote;
    }
    return el('section', { class: 'block' }, head, body, foot);
  }

  const options = (name) => () => (S && S.options && S.options[name]) || [];

  // MARK: Sections

  const build = {
    general() {
      const sys = () => (S && S.system) || {};
      const defaultTrailing = el('span');
      control(() => {
        const s = sys();
        if (s.isDefaultBrowser) defaultTrailing.replaceChildren(el('span', { class: 'status', html: icon('check') + 'Pane is your default browser' }));
        else {
          const b = el('button', { class: 'btn primary', type: 'button', disabled: s.isPromptingDefault }, s.isPromptingDefault ? 'Confirm in the Dialog…' : 'Set Pane as Default');
          b.addEventListener('click', () => run('defaultBrowser').catch(() => {}));
          defaultTrailing.replaceChildren(...(s.defaultBrowserName ? [el('span', { class: 'value' }, s.defaultBrowserName)] : []), b);
        }
      });
      const dockTrailing = el('span');
      control(() => {
        if (sys().inDock) dockTrailing.replaceChildren(el('span', { class: 'status', html: icon('check') + 'In the Dock' }));
        else {
          const b = el('button', { class: 'btn', type: 'button' }, 'Add Pane to Dock');
          b.addEventListener('click', () => run('addToDock').catch(() => {}));
          dockTrailing.replaceChildren(b);
        }
      });
      const updates = () => (S && S.updates) || {};
      return [
        card('System', [
          row({ title: 'Default browser', detail: 'Links from other apps open in Pane.', trailing: defaultTrailing }),
          row({ title: 'Dock', trailing: dockTrailing }),
          toggle('launchesAtLogin', 'Open Pane at login', 'Pane opens by itself when you log in to your Mac.'),
        ]),
        card('Startup', [
          toggle('restoreWindows', 'Restore windows from the previous session', 'When Pane opens, the windows you had open last time come back.'),
          toggle('startOnNewTab', 'Start on a new tab', 'When Pane opens, it starts on a new tab instead of the tab you used last.'),
        ]),
        card('Downloads', [
          select('downloadChoice', 'Download location', () => {
            const d = (S && S.downloads) || {};
            return [{ value: 'folder', label: d.folderName || 'Downloads' }, { value: 'ask', label: 'Ask where to save each file' }, { value: 'other', label: 'Other…' }];
          }, (() => { const d = el('span'); control(() => { d.textContent = (S && S.downloads && S.downloads.path) || ''; }); return d; })(), {
            current: () => (S && S.downloads && S.downloads.ask) ? 'ask' : 'folder',
            onchange: (v) => run('downloadLocation', { choice: v }).catch(() => {}).finally(update),
          }),
        ], { footnote: 'Each profile can save somewhere else (Profiles).' }),
        card('Quitting', [
          toggle('warnBeforeQuitting', 'Warn before quitting', '⌘Q asks “Quit Pane?” first, so pressing it by mistake doesn’t close everything.', { disabled: () => !!value('keepInMenuBar') }),
          toggle('keepInMenuBar', 'Keep Pane in the menu bar', 'In the menu bar, ⌘Q closes Pane’s windows but leaves it running.'),
        ]),
        card('Sleeping tabs', [
          toggle('tabSleepTimerEnabled', 'Force tabs out of memory', 'A tab you haven’t used for a while is forced out of memory and reloads when you open it.'),
          select('tabSleepAfter', 'After a tab is hidden for', options('tabSleepAfter'), null, { disabled: () => !value('tabSleepTimerEnabled') }),
          toggle('tabSleepOnMemoryPressure', 'When the Mac is short of memory', 'While macOS is short of memory, the tabs hidden longest are forced out of it, a few at a time.'),
        ], { footnote: 'A tab forced out of memory reloads when you open it. Tabs playing sound, recording, holding text you typed or set to Load on Start stay.' }),
        card('Updates', [
          toggle('automaticallyUpdates', 'Automatically update Pane', 'Pane downloads new versions in the background and installs them the next time it opens.', { disabled: () => !updates().available }),
          button('Check for updates', () => updates().summary || '', 'Check Now', 'checkForUpdates'),
        ]),
        syncCard(),
      ];
    },

    'search-engines'() {
      const engines = () => (S && S.engines) || { list: [] };
      const engineIcon = favicon('', '');
      control(() => {
        const e = engines().list.find((x) => x.keyword === engines().selected);
        setFavicon(engineIcon, e ? e.host : '', e ? e.name : '');
      });
      const engineSelect = select('engine', 'Search engine', () => engines().list.map((e) => ({ value: e.keyword, label: e.name })), 'Used for what you type in the command bar that isn’t an address.', {
        current: () => engines().selected || '',
        onchange: (v) => run('setEngine', { keyword: v }).catch(() => {}),
      });
      engineSelect.querySelector('.trailing').prepend(engineIcon);
      const add = el('button', { class: 'btn small', type: 'button' }, 'Add Site Search…');
      add.addEventListener('click', () => openSiteDialog(null));
      const customList = el('div');
      const siteList = el('div');
      list(customList, () => S && S.custom, renderCustom);
      const restore = el('button', { class: 'btn small', type: 'button' }, 'Restore Removed');
      restore.addEventListener('click', () => run('restoreSites').then(() => toast('Built-in sites restored')).catch(() => {}));
      control(() => { const n = ((S && S.hiddenSites) || []).length; restore.classList.toggle('hidden', !n); restore.textContent = `Restore Removed (${n})`; });
      list(siteList, () => S && S.sites, renderSites);
      return [
        card('Default search engine', [
          engineSelect,
          toggle('searchSuggestions', 'Show search suggestions', 'Suggestions come from the search engine as you type.'),
          button('Manage search engines', 'Chromium’s list, for keywords and engines of your own.', 'Open…', 'openURL', { url: 'chrome://settings/searchEngines' }),
        ]),
        card('Your site searches', [customList], { trailing: add }),
        card('Sites', [siteList], { trailing: restore, footnote: 'Type the start of a site (yo for YouTube) or its shortcut, then Tab: the command bar searches that site, its badge in the color shown. A site without one of its own takes its icon’s. Editing a site keeps your copy under Your site searches.' }),
      ];
    },

    appearance() {
      const opacity = el('input', { type: 'range', min: '0.2', max: '1', step: '0.01', 'aria-label': 'Default opacity' });
      const shown = el('span', { class: 'value' });
      const label = (v) => (v >= 1 ? 'Opaque' : `${Math.round(v * 100)} %`);
      opacity.addEventListener('input', () => { shown.textContent = label(Number(opacity.value)); });
      opacity.addEventListener('change', () => write('defaultSpaceOpacity', Number(opacity.value)));
      control(() => { if (document.activeElement !== opacity) opacity.value = value('defaultSpaceOpacity'); shown.textContent = label(Number(opacity.value)); });
      return [
        card('Theme', [
          button('Space theme', 'The colors, gradient and grain of the space on screen.', 'Edit Theme…', 'editTheme'),
          select('websiteAppearance', 'Websites', options('websiteAppearance'), 'Websites, Easels and this page use light or dark.'),
        ]),
        // Appearance ▸ App Icon (12 Nov 2026, with Pane's icons; was under General).
        appIconCard(),
        card('Spaces', [
          defaultTintRow(),
          row({ title: 'Default opacity', detail: 'How much of the desktop a new space’s theme lets through.', trailing: el('div', { class: 'slider' }, opacity, shown), search: 'transparency vibrancy' }),
        ]),
        card('Sidebar', [
          toggle('animateSidebarDocking', 'Animate sidebar docking', 'Showing and hiding the sidebar glides, the page easing into place. Off, it snaps as in Arc.'),
        ]),
        card('Pages', [
          toggle('toolbarShowsFullURL', 'Show full URLs', 'The toolbar shows a page’s whole address instead of only its site.', { disabled: () => !value('showToolbar') }),
          toggle('edgeToEdgeContent', 'Pages fill the window edge to edge', 'Pages fill the window, with no margin or rounded corners around them.'),
          button('Fonts', 'Sizes and typefaces websites use.', 'Customize Fonts…', 'openURL', { url: 'chrome://settings/fonts' }),
        ]),
        card('Sound & websites', [
          toggle('soundEffects', 'Play Pane sound effects', 'A camera shutter sounds when you capture a screenshot of a page.'),
          toggle('shareThemeWithWebsites', 'Allow websites to get your theme data', 'Sites that ask can read your space’s colors and match their pages to them.'),
        ]),
      ];
    },

    'tabs-and-spaces'() {
      // #305: onboarding's "Choose where the address bar goes" (CraCore AddressBarPlacement), saved
      // as showToolbar. The View menu's Show Toolbar switches it too.
      const toolbarKeys = () => {
        const a = S && (S.shortcuts || []).find((x) => x.id === 'toggleToolbar');
        return a && a.keys.length ? a.keys[0] : null;
      };
      return [
        card('Address Bar', [
          select('showToolbar', 'Address bar', [
            { value: 'sidebar', label: 'At the top of the sidebar' },
            { value: 'toolbar', label: 'In a toolbar above the page' },
          ], (() => { const d = el('span'); control(() => { const k = toolbarKeys(); d.textContent = `${k ? k + ' in any window, or ' : ''}View ▸ Show Toolbar switches it too.`; }); return d; })(), {
            current: () => (value('showToolbar') ? 'toolbar' : 'sidebar'),
            onchange: (v) => write('showToolbar', v === 'toolbar'),
          }),
        ]),
        card('Tabs', [
          toggle('newTabsAtTop', 'Add new tabs to the top', 'A new tab goes above your other tabs instead of below them.'),
          toggle('newTabButtonAtTop', 'Show the New Tab button above tabs', 'The + New Tab row sits at the top of the tab list, where you can always reach it.'),
          toggle('hapticFeedbackOnReorder', 'Haptic feedback when reordering tabs', 'The trackpad taps as a dragged tab moves past another one.'),
          toggle('middleClickUnloadsTab', 'Middle-click a tab to unload it instead of closing it', 'The tab stays in the sidebar with its memory freed, and loads again when you open it.'),
          toggle('folderPreviews', 'Preview a folder’s tabs when hovering over it', 'Hover over a closed folder to see the tabs inside it.'),
          toggle('autoPictureInPicture', 'Enable Picture in Picture when you leave a video tab', 'For every site you haven’t switched yourself: a site switched in its Extensions menu keeps that until you switch it again.'),
        ], { footnote: 'Right-click a tab ▸ Load on Start to have it load when Pane opens and stay in memory.' }),
        card('Favorites', [
          toggle('favoritePreviews', 'Preview unread Gmail when hovering its favorite', 'Hover over Gmail in your Favorites to see your unread mail.'),
          toggle('favoriteLogoOutline', 'Outline the open favorite in its logo’s colors', 'The open favorite gets a rim in its logo’s colors instead of a plain one.'),
          toggle('sharedFavorites', 'Share favorites across spaces', 'Spaces on the same profile show the same Favorites, as in Arc. Turning it on combines their Favorites; turning it off gives each Space its own copy.'),
        ]),
        card('Spaces', [
          toggle('showSpaceHeaderOnSingleSpace', 'Show the space header with only one space', 'Show the space’s name at the top and its icon at the bottom of the sidebar, even while you have only one space.'),
          button('Your spaces', 'Rename, reorder, theme and delete spaces in the Library.', 'Manage Spaces…', 'manageSpaces'),
        ]),
        card('Archive', [
          toggle('autoArchiveEnabled', 'Archive tabs you haven’t used', 'Today tabs you haven’t opened for a while move to the archive. Pinned tabs and Favorites stay.'),
          select('autoArchive', 'After', options('autoArchive'), null, { disabled: () => !value('autoArchiveEnabled') }),
        ]),
        card('Little Windows & Peek', [
          toggle('openExternalLinksInLittleWindow', 'Links from other apps open in a Little Window', 'A link you click in Mail, Slack or another app opens in a small window you can read and close, instead of a new tab in your sidebar.'),
          toggle('littleWindowShortcutEverywhere', 'Open a Little Window from any app with its shortcut', 'Press its shortcut wherever you are to open a Little Window, even while Pane isn’t in front.'),
          select('littleWindowArchiveAfter', 'Archive Little Windows after', options('littleWindowArchiveAfter'), 'A Little Window you leave alone closes into the archive, where you can find it again.'),
          toggle('peekLinksToOtherSites', 'Open a Peek window when clicking on links to other sites', 'A link to another site opens in a Peek over the page, so you can read it and close it without losing your place.'),
          toggle('peekInEveryTab', 'In every tab, not only Favorites and Pinned tabs', null, { disabled: () => !value('peekLinksToOtherSites') }),
          toggle('peekOnShiftClick', 'Open a Peek window when clicking on links with Shift held', 'Hold ⇧ while you click any link to open it in a Peek.'),
          toggle('openLinksInForeground', '“Open Link in New Tab” switches to the new tab', '“Open Link in New Tab” brings the new tab to the front. Off, the page you’re reading stays in front, as in Arc. ⌘-click opens a link behind the page and ⇧⌘-click switches to it either way.'),
        ]),
        routesCard(),
      ];
    },

    shortcuts() {
      const filter = el('input', { type: 'search', placeholder: 'Filter shortcuts', spellcheck: 'false', autocomplete: 'off', 'aria-label': 'Filter shortcuts' });
      const field = el('label', { class: 'field-search', html: icon('search-engines') }, filter);
      const listEl = el('div');
      const count = el('span', { class: 'toolbar-count' });
      let f = '';
      filter.addEventListener('input', () => { f = filter.value.trim().toLowerCase(); listShown.delete(listEl); update(); });
      list(listEl, () => S && { shortcuts: S.shortcuts, recording: S.recording, groups: S.shortcutGroups, f }, (host, data) => {
        const n = renderShortcuts(host, data, f);
        count.textContent = f ? `${n} of ${(data.shortcuts || []).length}` : `${(data.shortcuts || []).length} commands`;
      });
      const resetAll = el('button', { class: 'btn small', type: 'button' }, 'Reset All');
      resetAll.addEventListener('click', () => pageDialog({ title: 'Reset every shortcut?', message: 'Every command goes back to Pane’s own shortcut. Ones you added are removed.',
        confirmLabel: 'Reset All', destructive: true }).then((r) => { if (r.ok) run('resetAllShortcuts').catch(() => {}); }));
      return [
        el('section', { class: 'block toolbar' },
          el('div', { class: 'toolbar-row' }, field, count, resetAll),
          el('p', { class: 'footnote' }, 'Click a command, then press its new keys. Escape cancels, Delete removes the shortcut.')),
        listEl,
      ];
    },

    privacy() {
      return [
        card('Content blocking', [
          toggle('blockAdsAndTrackers', 'Block ads and trackers', 'Pane’s own lists, on every site you visit.'),
          toggle('blockCookieBanners', 'Block cookie banners', 'Cookie banners from the common consent tools are hidden. Pages load again with the change.'),
          // Not in Arc or Dia: Cra's Chromium (scripts/cef-patches/fingerprinting-protection.patch).
          toggle('fingerprintingProtection', 'Fingerprinting protection', 'Sites that tell browsers apart by reading back drawings, 3D graphics or sound get faint noise in what they read, different for each site and each time Pane opens. Sites also see 8 processor cores.'),
        ]),
        card('Connections', [
          toggle('httpsOnly', 'Always use secure connections', 'Pages load over HTTPS, and Pane asks before one that can’t.'),
          select('secureDNS', 'Secure DNS', () => {
            const d = (S && S.dns) || { providers: [] };
            return [{ value: 'automatic', label: 'Automatic' }, { value: 'off', label: 'Off' }]
              .concat(d.providers.map((p) => ({ value: 'provider:' + p.id, label: p.name })))
              .concat(d.choice === 'custom' ? [{ value: 'custom', label: 'Custom' }] : []);
          }, (() => { const d = el('span'); control(() => { d.textContent = (S && S.dns && S.dns.summary) || 'How Pane looks up a site before it loads.'; }); return d; })(), {
            current: () => (S && S.dns && S.dns.choice) || 'automatic',
            disabled: () => !(S && S.dns && S.dns.available) || (S.dns && S.dns.managed),
            onchange: (v) => run('secureDNS', { choice: v }).catch(() => {}).finally(update),
          }),
        ]),
        card('Data', [
          button('Browsing data', 'History, cookies, cached pictures and files.', 'Clear Browsing Data…', 'openURL', { url: 'chrome://settings/clearBrowserData' }),
          toggle('perfHidesSiteNames', 'Leave site names out of performance recordings'),
        ]),
        card('Automation', [
          toggle('allowAppleEventsJavaScript', 'Allow JavaScript from Apple Events', 'Scripts and Shortcuts can run JavaScript in your tabs.'),
        ]),
      ];
    },

    advanced() {
      const launch = () => (S && S.extra) || {};
      return [
        card('Engine', [
          toggle('chromeEngine', 'Chrome engine for pages', 'Extensions and Chrome DevTools. Restart Pane to apply a change.'),
          toggle('hardwareAcceleration', 'Use hardware acceleration when available', () => (value('hardwareAcceleration') !== launch().accelerationAtLaunch
            ? 'Takes effect the next time Pane opens.' : 'Pages draw on the graphics card. Off can help with a glitching display.')),
          button('Restart', 'Close and open Pane again, with the windows you have open.', 'Restart Pane', 'relaunch'),
        ]),
        card('Websites', [
          // Arc's, under the toolbar too (#363): the band is 60 pt from the card's top, its bar included.
          toggle('pageTopWindowDrag', 'Allow window dragging from the top of webpages', 'Drag the top edge of a page to move the window.'),
          toggle('boostsEnabled', 'Enable Boosts on websites you visit', 'Your Boosts restyle and change the sites they’re made for.'),
        ]),
        card('Command bar', [
          // #307, not in Arc: ⌘T finds tabs in the window's space only (CraCore TabSearchScope).
          toggle('commandBarCurrentSpaceOnly', 'Search only the current space’s tabs', 'Off, ⌘T finds a tab in any space, as in Arc. % then Tab searches one space either way.'),
        ]),
        mcpCard(),
        card('Import & export', [
          button('Import', 'Spaces, tabs, bookmarks and passwords from Arc, Chrome, Safari and others.', 'Import…', 'importData'),
          button('Export', 'Every space’s favorites, pinned tabs and folders as a bookmarks file.', 'Export…', 'exportSpaces'),
        ]),
        card('Diagnostics', [
          toggle('perfRecording', 'Record performance', 'Saved on this Mac only; nothing leaves it.'),
          button('Diagnostics', 'A file with Pane’s logs for a bug report, site names left out.', 'Export Diagnostics…', 'exportDiagnostics'),
        ]),
        card('About', [
          row({ title: 'Version', detail: (() => { const d = el('span'); control(() => { d.textContent = (S && S.version) || ''; }); return d; })() }),
          button('Data folder', () => (S && S.dataFolder) || '', 'Show in Finder', 'showDataFolder'),
        ]),
      ];
    },

    profiles() {
      const profiles = el('div'), downloads = el('div'), languages = el('div');
      const P = () => (S && S.profiles) || { list: [] };
      list(profiles, () => S && S.profiles && S.profiles.list.map((p) => [p.id, p.name, p.spaces, p.canDelete]), () => {
        profiles.replaceChildren(...P().list.map((p) => {
          const rename = el('button', { class: 'btn', type: 'button' }, 'Rename…');
          rename.addEventListener('click', () => pageDialog({ title: 'Rename your Profile', message: 'This won’t affect the names of any of the Spaces associated with this Profile.',
            input: p.name, placeholder: 'Profile name', requiresInput: true, confirmLabel: 'Save' }).then((r) => { if (r.ok) run('renameProfile', { id: p.id, name: r.value }).catch(() => {}); }));
          const del = el('button', { class: 'btn danger', type: 'button', disabled: !p.canDelete, title: p.canDelete ? '' : 'Only Profiles not assigned to any Spaces can be deleted.' }, 'Delete…');
          del.addEventListener('click', () => pageDialog({ title: `Delete “${p.name}”?`, message: 'Deleting this Profile will permanently remove any cookies, history, preferences, and logins that belong to it.',
            confirmLabel: 'Delete Profile', destructive: true }).then((r) => { if (r.ok) run('deleteProfile', { id: p.id }).catch(() => {}); }));
          return row({ title: p.name, detail: p.spaces, trailing: p.id === 'default' ? null : [rename, del] });
        }));
      });
      list(downloads, () => S && S.profiles && S.profiles.list.map((p) => [p.id, p.name, p.downloads]), () => {
        downloads.replaceChildren(...P().list.map((p) => {
          const s2 = el('select', { 'aria-label': `Download location for ${p.name}` },
            el('option', { value: 'folder' }, p.downloads.folderName), el('option', { value: 'ask' }, 'Ask where to save each file'), el('option', { value: 'other' }, 'Other…'));
          s2.value = p.downloads.ask ? 'ask' : 'folder';
          s2.addEventListener('change', () => run('profileDownloads', { profile: p.id === 'default' ? null : p.id, choice: s2.value }).catch(() => {}).finally(() => { listShown.delete(downloads); update(); }));
          return row({ title: p.name, detail: p.downloads.path, trailing: s2, search: 'download location' });
        }));
      });
      list(languages, () => S && S.profiles && S.profiles.list.map((p) => [p.id, p.name, p.languages, p.hasSpace]), () => {
        languages.replaceChildren(...P().list.map((p) => {
          const b = actionButton('Change…', 'openProfilePage', { url: 'chrome://settings/languages', profile: p.id === 'default' ? null : p.id });
          b.disabled = !p.hasSpace;
          b.title = p.hasSpace ? `Open Chromium’s language settings for ${p.name}.` : `Set ${p.name} on a Space first.`;
          return row({ title: p.name, detail: p.languages, trailing: b, search: 'languages' });
        }));
      });
      const createButton = el('button', { class: 'btn', type: 'button' }, 'Create Profile…');
      createButton.addEventListener('click', createProfileDialog);
      const create = el('div', { class: 'card-actions' }, createButton);
      control(() => {
        const has = create.querySelector('[data-arc]');
        if (P().canRebuildFromArc && !has) { const b = actionButton('Rebuild from Arc…', 'rebuildArcProfiles'); b.dataset.arc = '1'; b.title = 'Put spaces imported from Arc back on the profiles they use in Arc.'; create.append(b); }
      });
      const pages = [['Privacy and Security', 'chrome://settings/privacy'], ['Passwords', 'chrome://password-manager/passwords'],
        ['Credit Cards', 'chrome://settings/payments'], ['Notifications', 'chrome://settings/content/notifications']];
      const dataRows = el('div');
      list(dataRows, () => S && S.profiles && S.profiles.list.map((p) => [p.id, p.name]), () => {
        dataRows.replaceChildren(...pages.map(([title, url]) => {
          const ps = P().list;
          const trailing = ps.length <= 1 ? actionButton('Open', 'openProfilePage', { url, profile: null }) : (() => {
            const sel = el('select', { 'aria-label': `Open ${title} for` }, el('option', { value: '', disabled: true }, 'Open for…'),
              ...ps.map((p) => el('option', { value: p.id }, p.name)));
            sel.value = '';
            sel.addEventListener('change', () => { run('openProfilePage', { url, profile: sel.value === 'default' ? null : sel.value }).catch(() => {}); sel.value = ''; });
            return sel;
          })();
          return row({ title, trailing });
        }));
      });
      return [
        card('Profiles', [profiles], { footnote: 'Profiles keep logins, cookies and site data apart. A Space picks its Profile in Spaces ▸ Change Profile. Spaces on the same Profile share their logins. Only Profiles no Space uses can be deleted.' }),
        create,
        card('Downloads', [downloads], { footnote: 'Where each Profile saves downloaded files.' }),
        card('Languages', [languages], { footnote: 'The languages websites show their pages in for each Profile, most wanted first. Pane itself stays in English.' }),
        card('Your data and settings', [dataRows]),
      ];
    },

    extensions() {
      const host = el('div');
      const X = () => (S && S.extensions) || { list: [] };
      list(host, () => S && S.extensions, (h, x) => {
        if (!x) return;
        if (!x.list.length) { h.replaceChildren(el('div', { class: 'empty' }, 'No extensions installed. Add one from the Chrome Web Store, or an unpacked extension folder (the kind Chrome’s “Load unpacked” takes).')); return; }
        h.replaceChildren(...x.list.map((e) => {
          const r = row({ title: `${e.name} ${e.version}`, detail: e.description || null, search: e.name,
            trailing: actionButton(e.managedByChrome ? 'Remove…' : 'Remove', 'removeExtension', { id: e.id }) });
          const ic = el('span', { class: 'favicon ext-icon' }, el('img', { alt: '', src: `pane://settings/extension-icon/${encodeURIComponent(e.id)}` }));
          ic.querySelector('img').addEventListener('error', (ev) => { ev.target.replaceWith(el('span', { html: icon('extensions') })); });
          r.prepend(ic);
          return r;
        }));
      });
      const manager = actionButton('Open Chrome’s Extension Manager', 'openURL', { url: 'chrome://extensions' });
      control(() => { manager.disabled = !X().chromeEngine; });
      return [
        card('Installed extensions', [host], { footnote: () => (X().chromeEngine ? (X().needsRestart ? 'Restart Pane to apply the change.' : 'Extensions load when Pane starts.') : 'Extensions need the Chrome engine (Advanced).') }),
        el('div', { class: 'card-actions' }, actionButton('Add Unpacked Extension…', 'addExtension'), manager),
      ];
    },

    plugins() {
      const host = el('div');
      list(host, () => S && S.plugins, (h, x) => {
        if (!x) return;
        if (!x.list.length) { h.replaceChildren(el('div', { class: 'empty' }, 'No plugins installed.')); return; }
        h.replaceChildren(...x.list.map((p) => row({ title: `${p.name} ${p.version}`, detail: p.bundled ? 'Built-in' : 'Installed plugin', search: p.name,
          trailing: [p.bundled ? null : (() => {
              const b = el('button', { class: 'btn', type: 'button' }, 'Remove…');
              b.addEventListener('click', () => pageDialog({ title: `Remove “${p.name}”?`, message: 'The plugin will move to the Trash. Its existing folders and tabs will stay in the sidebar.',
                confirmLabel: 'Remove Plugin', destructive: true }).then((r) => { if (r.ok) run('removePlugin', { id: p.id }).catch(() => {}); }));
              return b;
            })(),
            switchControl(p.enabled, x.reloading, (on) => run('setPluginEnabled', { id: p.id, on }).catch(() => {}))] })));
      });
      const failures = el('div');
      control(() => {
        const f = (S && S.plugins && S.plugins.failures) || [];
        failures.replaceChildren(...f.map((m) => el('p', { class: 'footnote error' }, m)));
      });
      const reload = actionButton('Reload Plugins', 'reloadPlugins');
      control(() => { reload.disabled = !!(S && S.plugins && S.plugins.reloading); });
      return [
        card('Live folder plugins', [host], { footnote: 'Create folders from the sidebar’s Live Folders menu. Disabling or removing a plugin keeps its existing folders and tabs.' }),
        el('div', { class: 'card-actions' }, actionButton('Add Plugin…', 'addPlugin'), reload),
        failures,
      ];
    },

    max() {
      const M = () => (S && S.max) || {};
      const feature = (key, title, detail, picture) => {
        const r = toggle(key, title, detail, { disabled: () => !M().available });
        r.classList.add('feature');
        r.prepend(el('span', { class: `max-picture ${picture}`, html: MAX_PICTURES[picture] }));
        return r;
      };
      const foot = el('div', { class: 'max-foot' });
      control(() => {
        const m = M();
        foot.replaceChildren(el('p', { class: 'footnote center' }, m.explanation || ''),
          ...(m.canOpenSettings ? [el('button', { class: 'link-btn', type: 'button', onclick: () => run('openAppleIntelligence').catch(() => {}) }, 'Turn on Apple Intelligence in System Settings')] : []));
      });
      return [
        card(null, [
          feature('tidyTabs', 'Tidy Tabs', 'Press the broom to let your Sidebar organize itself whenever you have six or more Today Tabs.', 'tidy-tabs'),
          feature('tidyTabTitles', 'Tidy Tab Titles', 'Have your tabs automatically renamed with tidier, shorter titles when you Pin them.', 'tidy-titles'),
          feature('tidyDownloads', 'Tidy Downloads', 'Keep your many files more organized with smartly renamed downloads — and make them a little easier to find later.', 'tidy-downloads'),
          // #324: Arc Max's hover cards, on the Mac's own Apple Intelligence model.
          feature('fiveSecondPreviews', '5-Second Previews', 'Instant summaries appear when you hover over links on certain websites (Google results, X and Hacker News). Or hold Shift while hovering to preview any link.', 'five-second-previews'),
        ]),
        foot,
      ];
    },

    performance() {
      const recording = toggle('perfRecording', 'Record performance in the background', 'Off, Pane measures itself only while this page is open, so nothing wakes it up meanwhile.');
      const body = el('div');
      list(body, () => S && [S.settings && S.settings.perfRecording, S.performance], (h) => {
        const p = (S && S.performance) || {};
        const on = !!(S && S.settings && S.settings.perfRecording);
        if (!p.ready) { h.replaceChildren(el('div', { class: 'card' }, el('div', { class: 'empty' }, 'Reading the recording…'))); return; }
        const blocks = [];
        // Off in Settings: Cra measures only while this page is open, and stops when you leave it.
        if (!on) blocks.push(el('p', { class: 'footnote' }, 'Measuring while this page is open; it stops when you leave. Switch on Record performance to keep recording in the background.'));
        if (p.insights.length) blocks.push(card('Findings', p.insights.map((i) => row({ title: (i.warning ? '⚠︎ ' : '') + i.title, detail: i.detail }))));
        for (const c of p.cards) blocks.push(card(c.title, c.rows.map(([k, v]) => row({ title: k, trailing: el('span', { class: 'value wide' }, v) }))));
        blocks.push(card('Events', p.events.length ? p.events.map((e) => row({ title: e.title, detail: e.detail || null, trailing: el('span', { class: 'value' }, e.time) }))
          : [el('div', { class: 'empty' }, 'Nothing has happened this session: no stalls, crashed pages or failed loads.')]));
        blocks.push(el('p', { class: 'footnote' }, p.footer));
        h.replaceChildren(...blocks);
      });
      const clear = el('button', { class: 'btn danger', type: 'button' }, 'Clear…');
      clear.addEventListener('click', () => pageDialog({ title: 'Clear the performance recording?', message: 'This session’s numbers, the last 24 hours and saved freezes are deleted.',
        confirmLabel: 'Clear', destructive: true }).then((r) => { if (r.ok) run('perfClear').catch(() => {}); }));
      const copy = el('button', { class: 'btn', type: 'button' }, 'Copy Summary');
      copy.addEventListener('click', () => run('perfCopySummary').then(() => toast('Summary copied')).catch(() => {}));
      return [
        card(null, [recording], { footnote: 'Pane measures itself on this Mac: freezes, CPU and memory per process, tab timings. Nothing leaves the Mac unless you export it.' }),
        body,
        card('Export', [
          toggle('perfHidesSiteNames', 'Hide site names', 'Sites in the exported files become site-1, site-2… in every file, logs included.'),
        ], { footnote: () => `Copy Summary never names a site. The recording lives in ${(S && S.performance && S.performance.folder) || 'Perf'} and stays under 2 MB.` }),
        el('div', { class: 'card-actions' }, actionButton('Export Diagnostics…', 'exportDiagnostics'), copy, clear),
      ];
    },
  };

  // Max's pictures, after Arc's: the broom on lavender, a renamed tab on mauve, a renamed download on blue.
  const MAX_PICTURES = {
    'five-second-previews': '<svg viewBox="0 0 88 56"><rect x="9" y="13" width="70" height="30" rx="4" fill="#fff"/><path d="M15.2 19.6l1.2-1.2a1.4 1.4 0 0 1 2 2l-1.2 1.2M17.2 21.6l-1.2 1.2a1.4 1.4 0 0 1-2-2l1.2-1.2" fill="none" stroke="#8C8C8C" stroke-width=".8" stroke-linecap="round"/><rect x="21" y="18.6" width="30" height="3" rx="1.5" fill="#111"/><path d="M72 17.5l.7 1.7 1.7.7-1.7.7-.7 1.7-.7-1.7-1.7-.7 1.7-.7z" fill="#8C73E6"/><g fill="#8C8C8C"><circle cx="15.5" cy="28" r="1"/><circle cx="15.5" cy="33" r="1"/><circle cx="15.5" cy="38" r="1"/></g><g fill="#8C8C8C" opacity=".7"><rect x="18.5" y="27" width="44" height="2" rx="1"/><rect x="18.5" y="32" width="50" height="2" rx="1"/><rect x="18.5" y="37" width="34" height="2" rx="1"/></g></svg>',
    'tidy-tabs': '<svg viewBox="0 0 88 56"><path d="M14 28c3-4 6 4 9 0s6 4 9 0 6 4 9 0" fill="none" stroke="#B3ABE6" stroke-width="1.6" stroke-linecap="round"/><g fill="none" stroke="#8C85B8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M60 19l-6 8M51 29l6 4.5-2.5 4c-.6 1-1.8 1.2-2.8.6L48 35.6c-1-.6-1.2-1.8-.6-2.8L49 30.4z"/><path d="M68 24l7 7M75 24l-7 7"/></g></svg>',
    'tidy-titles': '<svg viewBox="0 0 88 56"><rect x="12" y="20" width="64" height="16" rx="8" fill="#fff"/><rect x="17" y="25" width="8" height="6" rx="1.5" fill="#521E5C"/><rect x="29" y="24" width="38" height="3.5" rx="1.7" fill="#6B459E"/><rect x="29" y="29.5" width="26" height="2.5" rx="1.2" fill="#6B459E" opacity=".6"/><g fill="#fff"><circle cx="10" cy="14" r="1.2"/><circle cx="78" cy="12" r="1"/><circle cx="74" cy="44" r="1.3"/><circle cx="20" cy="45" r="1"/></g></svg>',
    'tidy-downloads': '<svg viewBox="0 0 88 56"><rect x="9" y="15" width="70" height="26" rx="4" fill="#fff"/><rect x="14" y="19.5" width="34" height="2.5" rx="1.2" fill="#8C8C8C"/><rect x="14" y="25" width="44" height="4" rx="2" fill="#111"/><rect x="14" y="32" width="30" height="2.5" rx="1.2" fill="#A0A0A0"/><path d="M14 33.2h30" stroke="#A0A0A0" stroke-width=".8"/></svg>',
  };

  // Arc's light pastels, for a space with no colour of its own (Settings ▸ Appearance ▸ Default color).
  const TINTS = ['#DCF3FC', '#E8F4F9', '#E6E6FA', '#F7E1E8', '#E3F4E1', '#FDF1DC', '#ECE9E4'];

  function defaultTintRow() {
    const chips = el('div', { class: 'tint-chips' });
    const custom = el('input', { type: 'color', 'aria-label': 'Another color' });
    custom.addEventListener('change', () => write('defaultSpaceTint', custom.value));
    const reset = iconButton('reset', 'Back to Arc’s sky blue', () => write('defaultSpaceTint', TINTS[0]));
    control(() => {
      const cur = String(value('defaultSpaceTint') || TINTS[0]).toUpperCase();
      chips.replaceChildren(...TINTS.map((t) => el('button', { class: `tint-chip${t === cur ? ' selected' : ''}`, type: 'button', title: t, 'aria-label': `Default color ${t}`,
        style: `background:${t}`, onclick: () => write('defaultSpaceTint', t) })),
        el('label', { class: `tint-chip custom${TINTS.includes(cur) ? '' : ' selected'}`, title: 'Another color', style: TINTS.includes(cur) ? '' : `background:${cur}` }, custom));
      custom.value = cur.toLowerCase();
      reset.classList.toggle('hidden', cur === TINTS[0]);
    });
    return row({ title: 'Default color', detail: 'What a space with no color of its own is painted, see-through as the space is.', trailing: [reset, chips], search: 'default space color tint theme pastel' });
  }

  // MARK: General ▸ Sync, Appearance ▸ App Icon, Tabs & Spaces ▸ Air Traffic Control

  // Advanced ▸ Agents: the local MCP server (upstream 31187f8, #193). Off by default; Cra asks once
  // per agent, and scripts and history stay off unless switched on here.
  function mcpCard() {
    const host = el('div');
    list(host, () => S && S.mcp, (h, m) => {
      if (!m) return;
      const rows = [row({ title: 'Allow local agents to control Pane', detail: `Connected agents can read pages and act using your signed-in sessions. ${m.status}`,
        trailing: switchControl(m.enabled, false, (on) => run('mcpEnabled', { on }).catch(() => update())), search: 'mcp agents claude cursor codex' })];
      if (m.enabled) {
        // Add Cra to an agent (upstream 241cc8c): a tile per popular agent writes Cra into its MCP
        // settings; right-click for Remove and Show Settings File. Other Agent lists the rest.
        const caption = (a) => ({ current: '✓ Added', outdated: 'Update', unreadable: 'Can’t edit its settings' }[a.state] || (a.installed ? (a.detail || 'Add') : 'Not on this Mac'));
        const help = (a) => (!a.installed ? `Pane didn’t find ${a.name} on this Mac.` : {
          current: `Pane is in ${a.name}’s MCP settings.`, outdated: `${a.name} has Pane at another location. Click to point it at this Pane.`,
          unreadable: `${a.name}’s settings file isn’t one Pane can change safely. Copy the configuration and add it by hand.`,
        }[a.state] || `Add Pane to ${a.name}’s MCP settings.`);
        const tiles = el('div', { class: 'agent-tiles' }, ...(m.apps || []).filter((a) => a.popular).map((a) => el('button', {
          class: `agent-tile ${a.state}`, type: 'button', disabled: !a.installed, title: help(a), 'aria-label': a.name,
          onclick: () => run('mcpAgentAdd', { id: a.id }).catch(() => {}),
          oncontextmenu: (e) => { e.preventDefault(); run('mcpAgentMenu', { id: a.id }).catch(() => {}); },
        }, a.hasIcon ? el('img', { class: 'agent-icon', alt: '', src: `pane://settings/agent-icon/${encodeURIComponent(a.id)}` }) : el('span', { class: 'agent-icon terminal' }, '>_'),
        el('span', { class: 'agent-text' }, el('span', { class: 'agent-name' }, a.name), el('span', { class: 'agent-state' }, caption(a))))));
        rows.push(el('div', { class: 'row agent-block', dataset: { search: 'add cra to an agent mcp claude code cowork codex cursor t3 conductor' } },
          el('div', { class: 'label' }, el('div', { class: 'title' }, 'Add Pane to an agent'),
            el('div', { class: 'detail' }, 'Pane writes itself into the agent’s MCP settings. Each agent asks before it uses Pane the first time.')),
          tiles,
          el('div', { class: 'agent-actions' },
            el('button', { class: 'btn small', type: 'button', onclick: () => run('mcpAgentMenu').catch(() => {}) }, 'Other Agent…'),
            el('button', { class: 'btn small', type: 'button', onclick: () => run('mcpCopyConfiguration').then(() => toast('MCP configuration copied')).catch(() => {}) }, 'Copy MCP Configuration')),
          m.message ? el('p', { class: `footnote${m.messageIsError ? ' error' : ''}` }, m.message) : null));
        rows.push(row({ title: 'Last tool', detail: m.lastTool || 'None' }));
        rows.push(row({ title: 'Let agents run JavaScript in pages', detail: 'A script can read anything a page holds, including passwords Pane fills in.',
          trailing: switchControl(m.scripts, false, (on) => run('mcpScripts', { on }).catch(() => update())) }));
        rows.push(row({ title: 'Let agents read your history',
          trailing: switchControl(m.history, false, (on) => run('mcpHistory', { on }).catch(() => update())) }));
        for (const a of m.agents) {
          rows.push(row({ title: a.name, detail: a.allowed ? 'Allowed' : 'Not allowed',
            trailing: el('button', { class: 'btn', type: 'button', onclick: () => run('mcpForget', { id: a.id }).catch(() => {}) }, 'Forget') }));
        }
      }
      h.replaceChildren(...rows);
    });
    return card('Agents', [host]);
  }

  function syncCard() {
    const host = el('div');
    list(host, () => S && S.sync, (h, y) => {
      if (!y) return;
      const rows = [];
      if (y.pending) {
        rows.push(row({ title: 'Use the sidebar from your other Mac?', detail: y.pending, cls: 'notice', trailing: [
          actionButton('Use That Sidebar', 'syncUseRemote', {}, true),
          actionButton('Replace It with This Mac’s', 'syncUseLocal'),
          actionButton('Cancel', 'syncICloud', { on: false }),
        ] }));
      }
      const icloud = switchControl(y.location === 'icloud', !y.iCloudAvailable, (on) => run('syncICloud', { on }).catch(() => update()));
      rows.push(row({ title: 'Sync with iCloud', detail: y.iCloudAvailable ? 'Uses the iCloud account signed in on this Mac.' : y.iCloudReason,
        trailing: [actionButton('iCloud Settings…', 'openICloudSettings'), icloud], search: 'icloud sync' }));
      if (y.location === 'folder') rows.push(row({ title: 'Sync folder', detail: y.folder, trailing: actionButton('Stop Syncing', 'syncStop') }));
      else if (!y.location) rows.push(row({ title: 'Or sync through a folder in Dropbox, OneDrive or a similar service', trailing: actionButton('Use a Folder…', 'syncFolder') }));
      if (y.location) rows.push(row({ title: y.status, cls: y.failed ? 'error' : '', trailing: y.otherDevices.length ? el('span', { class: 'value wide' }, 'Also on ' + y.otherDevices.join(', ')) : null }));
      rows.push(row({ title: 'Settings file', detail: 'Your sidebar, settings and shortcuts in a “Pane” folder.', trailing: [actionButton('Export…', 'syncExport'), actionButton('Import…', 'syncImport')] }));
      h.replaceChildren(...rows);
    });
    return card('Sync', [host], { footnote: () => (S && S.sync && S.sync.notice) || 'Spaces, pinned tabs, favorites, folders, settings and shortcuts sync. Logins, cookies, history and extensions stay on each Mac.' });
  }

  function appIconCard() {
    const tiles = el('div', { class: 'icon-tiles' });
    const remove = el('span');
    list(tiles, () => S && S.appIcon, (h, a) => {
      if (!a) return;
      h.replaceChildren(...a.list.map((i) => {
        const custom = i.id === 'custom';
        const img = custom && !a.hasCustom ? el('span', { class: 'icon-empty', html: icon('plus') })
          : el('img', { alt: '', src: `pane://settings/app-icon/${encodeURIComponent(i.id)}?v=${a.selected}${a.hasCustom}` });
        return el('button', { class: `icon-tile${a.selected === i.id ? ' selected' : ''}`, type: 'button', title: i.name,
          onclick: () => run('appIcon', { id: i.id }).catch(() => {}) }, el('span', { class: 'icon-frame' }, img), el('span', { class: 'icon-name' }, i.name));
      }));
      remove.replaceChildren(...(a.hasCustom ? [actionButton('Remove', 'appIconRemoveCustom')] : []));
    });
    return card('App Icon', [
      el('div', { class: 'row tiles-row', dataset: { search: 'app icon dock' } }, tiles),
      row({ title: 'Your own icon', trailing: [remove, actionButton('Choose Image…', 'appIconChoose')], search: 'custom icon image' }),
    ], { footnote: 'Pick any image. It’s sized to match the other icons in the Dock, and the Dock keeps it after Pane quits.' });
  }

  function destinationSelects(token, spaces, onchange) {
    const little = token.startsWith('little');
    const first = el('select', { 'aria-label': 'Open in' },
      el('optgroup', { label: 'Open in Space' }, el('option', { value: 'recent' }, 'Most Recent Space'),
        ...spaces.map((sp) => el('option', { value: 'space:' + sp.id }, sp.name))),
      el('option', { value: 'little' }, 'Little Window'));
    first.value = little ? 'little' : token;
    first.addEventListener('change', () => onchange(first.value === 'little' && little ? token : first.value));
    const parts = [first];
    if (little) {
      const second = el('select', { 'aria-label': 'Little Window space', title: 'The space the Little Window opens in' },
        el('optgroup', { label: 'Little Window in' }, el('option', { value: 'little' }, 'Most Recent Space'),
          ...spaces.map((sp) => el('option', { value: 'little:' + sp.id }, sp.name))));
      second.value = token;
      second.addEventListener('change', () => onchange(second.value));
      parts.push(second);
    }
    return el('div', { class: 'stack' }, parts);
  }

  function routesCard() {
    const host = el('div');
    list(host, () => S && S.routes, (h, r) => {
      if (!r) return;
      const rows = r.list.map((route) => {
        const match = el('select', { 'aria-label': 'Match' }, ...r.matchStyles.map((m) => el('option', { value: m.value }, m.label)));
        match.value = route.match;
        match.addEventListener('change', () => run('editRoute', { id: route.id, match: match.value }).catch(() => {}));
        const text = el('input', { class: 'text-input', value: route.text, placeholder: 'pane.uz', spellcheck: 'false', 'aria-label': 'URL' });
        text.addEventListener('change', () => run('editRoute', { id: route.id, text: text.value.trim() }).catch(() => {}));
        const dest = destinationSelects(route.destination, r.spaces, (v) => run('editRoute', { id: route.id, destination: v }).catch(() => {}));
        return el('div', { class: 'row route', dataset: { search: `air traffic control route ${route.text}` } },
          el('div', { class: 'route-line' }, el('span', { class: 'route-label', html: icon('link') + 'URL' }), match, text,
            iconButton('minus', 'Remove route', () => run('removeRoute', { id: route.id }).catch(() => {}), 'danger')),
          el('div', { class: 'route-line indent' }, el('span', { class: 'route-label' }, '↳ Open in'), dest));
      });
      if (!rows.length) rows.push(el('div', { class: 'empty' }, 'Add a route to open matching links from other apps in a chosen space.'));
      const def = destinationSelects(r.default, r.spaces, (v) => run('setDefaultDestination', { destination: v }).catch(() => {}));
      rows.push(row({ title: 'Default', detail: 'Links from other apps no route matches.', trailing: def, search: 'air traffic control default links other apps' }));
      h.replaceChildren(...rows);
    });
    const add = el('button', { class: 'btn small', type: 'button' }, 'New Route');
    add.addEventListener('click', () => run('addRoute').then(() => setTimeout(() => { const t = document.querySelectorAll('.route .text-input'); if (t.length) t[t.length - 1].focus(); }, 50)).catch(() => {}));
    return card('Air Traffic Control', [host], { trailing: add, footnote: 'Links from other apps open in the space whose route matches them first.' });
  }

  function actionButton(label, action, args = {}, primary = false) {
    const b = el('button', { class: `btn${primary ? ' primary' : ''}`, type: 'button' }, label);
    b.addEventListener('click', (e) => { e.stopPropagation(); run(action, args).catch(() => {}); });
    return b;
  }

  function switchControl(on, disabled, onchange) {
    const input = el('input', { type: 'checkbox', role: 'switch' });
    input.checked = !!on;
    input.disabled = !!disabled;
    input.addEventListener('change', () => onchange(input.checked));
    return el('label', { class: 'switch' }, input, el('span', { class: 'track' }), el('span', { class: 'knob' }));
  }

  // MARK: Lists (rebuilt only when their data changes)

  function list(host, data, render) {
    control(() => {
      const d = data();
      const sig = JSON.stringify(d);
      if (listShown.get(host) === sig) return;
      listShown.set(host, sig);
      render(host, d);
    });
  }

  function favicon(host, name, color) {
    const f = el('span', { class: 'favicon letter' });
    setFavicon(f, host, name, color);
    return f;
  }
  function setFavicon(f, host, name, color) {
    const letter = (name || host || '?').trim().charAt(0).toUpperCase();
    f.style.background = color || 'var(--ink-3)';
    f.classList.add('letter');
    f.replaceChildren(document.createTextNode(letter));
    if (!host) return;
    const img = el('img', { alt: '', src: `pane://settings/favicon/${encodeURIComponent(host)}` });
    img.addEventListener('load', () => { f.classList.remove('letter'); f.style.background = ''; f.firstChild && f.firstChild.nodeType === 3 && f.firstChild.remove(); });
    img.addEventListener('error', () => img.remove());
    f.append(img);
  }

  function iconButton(name, label, onclick, cls = '') {
    return el('button', { class: `icon-btn ${cls}`, type: 'button', title: label, 'aria-label': label, html: icon(name), onclick });
  }

  function renderCustom(host, custom) {
    if (!custom || !custom.length) {
      host.replaceChildren(el('div', { class: 'empty' }, 'Add a site of your own: type its shortcut in the command bar, then Tab, to search it.'));
      return;
    }
    host.replaceChildren(...custom.map((c) => row({
      title: el('span', {}, c.name, ' ', el('span', { class: 'chip', style: `background:${c.shownColor || 'var(--ink-3)'}` }, c.shortcut)),
      detail: el('span', { class: 'mono' }, c.url),
      search: `${c.name} ${c.shortcut} ${c.url}`,
      trailing: [
        iconButton('edit', `Edit ${c.name}`, () => openSiteDialog(c)),
        iconButton('trash', `Delete ${c.name}`, () => run('removeSite', { id: c.id }).then(() => toast(`${c.name} removed`)).catch(() => {}), 'danger'),
      ],
    })).map((r, i) => { r.prepend(favicon(custom[i].host, custom[i].name, custom[i].shownColor)); return r; }));
  }

  function renderSites(host, sites) {
    if (!sites || !sites.length) { host.replaceChildren(el('div', { class: 'empty' }, 'Every built-in site is off the list.')); return; }
    host.replaceChildren(...sites.map((s) => {
      const color = el('input', { type: 'color', value: s.color || '#8E8E93', 'aria-label': `Badge color for ${s.name}` });
      color.addEventListener('change', () => run('setSiteColor', { host: s.host, color: color.value }).catch(() => {}));
      const swatch = el('label', { class: 'swatch', style: `background:${s.color || '#8E8E93'}`, title: 'Badge color' }, color);
      const trailing = [
        s.own ? iconButton('reset', `Back to ${s.name}’s own color`, () => run('setSiteColor', { host: s.host, color: null }).catch(() => {})) : null,
        swatch,
        iconButton('edit', `Edit ${s.name}`, () => openSiteDialog({ name: s.name, shortcut: s.host, url: s.url, color: s.own ? s.color : null, shownColor: s.color, replaces: s.host })),
        iconButton('trash', `Remove ${s.name}`, () => run('hideSite', { host: s.host }).then(() => toast(`${s.name} removed`)).catch(() => {}), 'danger'),
      ];
      const r = row({ title: s.name, detail: s.host, trailing, search: `${s.name} ${s.host}` });
      r.prepend(favicon(s.iconHost, s.name, s.color));
      return r;
    }));
  }

  /// One shortcut as macOS key caps, one cap a key (⇧ ⌘ D), like the sidebar's tooltips.
  function keyCaps(caps) { return el('span', { class: 'chord' }, caps.map((c) => el('kbd', { class: 'keycap' }, c))); }

  /// The groups in their order (CraCore ShortcutGroups), each a card; returns how many commands show.
  function renderShortcuts(host, data, f) {
    const all = (data && data.shortcuts) || [];
    const shown = all.filter((s) => !f || `${s.name} ${s.keys.join(' ')} ${s.section}`.toLowerCase().includes(f));
    const groups = new Map((data.groups || []).map((g) => [g, []]));
    for (const s of shown) { if (!groups.has(s.section)) groups.set(s.section, []); groups.get(s.section).push(s); }
    const blocks = [];
    for (const [section, items] of groups) {
      if (!items.length) continue;
      const rows = items.map((s) => {
        const recording = data.recording === s.id;
        let keys;
        if (recording) keys = el('span', { class: 'chord recording-hint' }, el('kbd', { class: 'keycap live' }, 'Type the new shortcut'), el('span', { class: 'esc-hint' }, 'esc to cancel'));
        else if (s.caps.length) keys = el('span', { class: 'chords' }, ...s.caps.flatMap((c, i) => (i ? [el('span', { class: 'or' }, 'or'), keyCaps(c)] : [keyCaps(c)])));
        else keys = el('span', { class: 'chord' }, el('span', { class: 'keycap-none' }, 'Add shortcut'));
        const tools = el('span', { class: 'edit' },
          s.overridden ? iconButton('reset', `Back to Pane’s shortcut for ${s.name}`, (e) => { e.stopPropagation(); run('resetShortcut', { id: s.id }).catch(() => {}); }) : null);
        return row({ title: s.name, detail: s.overridden ? 'Changed' : null, trailing: [tools, keys], cls: `shortcut${recording ? ' recording' : ''}${s.overridden ? ' changed' : ''}`,
          search: `${s.name} ${s.keys.join(' ')}`, onclick: () => run(recording ? 'stopRecording' : 'recordShortcut', { id: s.id }).catch(() => {}) });
      });
      blocks.push(el('section', { class: 'block' }, el('div', { class: 'section-header' }, el('h3', {}, section), el('span', { class: 'header-count' }, String(items.length))),
        el('div', { class: 'card' }, rows)));
    }
    host.replaceChildren(...(blocks.length ? blocks : [el('section', { class: 'block' }, el('div', { class: 'card' }, el('div', { class: 'empty' }, 'No shortcuts match.')))]));
    return shown.length;
  }

  // MARK: Site search dialog

  let editing = null;
  function openSiteDialog(site) {
    editing = site;
    const d = $('#site-dialog'), form = $('#site-form');
    $('#site-dialog-title').textContent = site ? `Edit ${site.name}` : 'Add Site Search';
    $('#site-save').textContent = site && site.id ? 'Save' : (site ? 'Save as Mine' : 'Add');
    form.name.value = site ? site.name : '';
    form.shortcut.value = site ? site.shortcut : '';
    form.url.value = site ? site.url : 'https://';
    form.ownColor.checked = !!(site && site.color);
    form.color.value = (site && (site.color || site.shownColor)) || '#5E5CE6';
    hint('');
    preview();
    d.showModal();
    setTimeout(() => form.name.focus(), 0);
  }
  /// Out with the page dialogs' quick drop, then closed.
  function closeDialog(d) {
    if (!d.open || d.classList.contains('closing')) return;
    d.classList.add('closing');
    const finish = () => { d.classList.remove('closing'); if (d.open) d.close(); };
    d.addEventListener('animationend', finish, { once: true });
    setTimeout(finish, 260);
  }

  function hint(text) {
    const h = $('#site-hint');
    h.textContent = text || 'Put %s where the search goes. Without a color of its own, the badge takes the site icon’s.';
    h.classList.toggle('error', !!text);
  }
  function preview() {
    const form = $('#site-form');
    form.color.disabled = !form.ownColor.checked;
    const p = $('#badge-preview');
    p.textContent = form.shortcut.value.trim() || 'yt';
    p.style.background = form.ownColor.checked ? form.color.value : 'var(--ink-3)';
  }
  function wireDialog() {
    const d = $('#site-dialog'), form = $('#site-form');
    for (const n of ['shortcut', 'color', 'ownColor']) form[n].addEventListener('input', preview);
    form.ownColor.addEventListener('change', preview);
    $('#site-cancel').addEventListener('click', () => closeDialog(d));
    d.addEventListener('cancel', (e) => { e.preventDefault(); closeDialog(d); });
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      const args = { name: form.name.value.trim(), shortcut: form.shortcut.value.trim(), url: form.url.value.trim(), color: form.ownColor.checked ? form.color.value : null };
      if (editing && editing.id) args.id = editing.id;
      if (editing && editing.replaces) args.replaces = editing.replaces;
      bridge.action(editing && editing.id ? 'editSite' : 'addSite', args)
        .then((s) => { if (s) apply(s); closeDialog(d); toast(editing ? `${args.name} saved` : `${args.name} added`); })
        .catch((err) => hint(typeof err === 'string' ? err : (err && err.message) || 'Pane couldn’t save it.'));
    });
  }

  // MARK: Page

  function renderNav() {
    const nav = $('#sections');
    nav.replaceChildren(...SECTIONS.map((s) => el('button', {
      class: `nav-item${s.id === current && !query ? ' selected' : ''}`, type: 'button', dataset: { section: s.id },
      html: icon(s.id) + `<span>${s.title}</span>`,
      onclick: () => show(s.id),
    })));
    $('#more').replaceChildren(...MORE.map((s) => el('button', {
      class: `nav-item${s.id === current && !query ? ' selected' : ''}`, type: 'button', dataset: { section: s.id },
      html: icon(s.id) + `<span>${s.title}</span>`,
      onclick: () => show(s.id),
    })));
  }

  function render() {
    controls = [];
    listShown.clear();
    const content = $('#content');
    if (query) {
      const parts = [el('h1', { class: 'page-title' }, `Results for “${$('#search').value.trim()}”`)];
      for (const s of ALL) {
        if (s.id === 'performance') continue;
        const blocks = build[s.id]();
        const group = el('div', { class: 'result-group', dataset: { section: s.id } }, el('div', { class: 'section-header' }, el('h3', {}, s.title)), blocks);
        parts.push(group);
      }
      content.replaceChildren(...parts);
    } else {
      const s = ALL.find((x) => x.id === current) || SECTIONS[0];
      content.replaceChildren(el('h1', { class: 'page-title' }, s.title), ...build[s.id]());
    }
    renderNav();
    update();
    sectionShown();
  }

  // Performance reads the recorder every two seconds while it is on screen, never otherwise; Max
  // asks Apple Intelligence where it stands each time it comes up.
  let perfTimer = 0;
  function sectionShown() {
    clearInterval(perfTimer);
    perfTimer = 0;
    if (query) return;
    if (current === 'performance') {
      const tick = () => { if (!document.hidden) bridge.action('perfRefresh').catch(() => {}); };
      tick();
      perfTimer = setInterval(tick, 2000);
    }
    if (current === 'max') bridge.action('maxRefresh').catch(() => {});
    if (current === 'advanced') bridge.action('mcpAgentsRefresh').catch(() => {});
  }
  document.addEventListener('visibilitychange', () => { if (!document.hidden) sectionShown(); });

  function filterResults() {
    if (!query) return;
    let any = false;
    for (const group of document.querySelectorAll('.result-group')) {
      let groupHas = false;
      for (const block of group.querySelectorAll('.block')) {
        let has = false;
        for (const r of block.querySelectorAll('.row')) {
          const hit = (r.dataset.search || '').includes(query);
          r.classList.toggle('hidden', !hit);
          has = has || hit;
        }
        block.classList.toggle('hidden', !has);
        groupHas = groupHas || has;
      }
      group.classList.toggle('hidden', !groupHas);
      any = any || groupHas;
    }
    let none = $('#no-results');
    if (!any && !none) $('#content').append(el('div', { id: 'no-results', class: 'card' }, el('div', { class: 'empty' }, 'No settings match.')));
    else if (any && none) none.remove();
  }

  function update() {
    if (!S) return;
    for (const c of controls) { try { c(); } catch (e) { console.error(e); } }
    filterResults();
  }

  function show(section, { report = true } = {}) {
    if (!ALL.some((s) => s.id === section)) section = 'general';
    const changed = section !== current || query;
    current = section;
    if (query) { query = ''; $('#search').value = ''; }
    if (changed) { render(); $('#main').scrollTop = 0; }
    if (report) bridge.section(section).catch(() => {});
  }

  function apply(state) {
    if (!state) return;
    const first = !S;
    S = state;
    const root = document.documentElement;
    if (state.theme === 'light' || state.theme === 'dark') root.dataset.theme = state.theme; else delete root.dataset.theme;
    if (state.accent) root.style.setProperty('--accent', state.accent);
    if (state.section && state.section !== current && (first || state.navigate)) { current = state.section; render(); return; }
    if (first) render(); else update();
  }

  // Cra moves the page to a section (⌘, with one in mind, pane://settings/<section> typed).
  window.craSettingsShow = (section) => show(section, { report: false });

  document.addEventListener('DOMContentLoaded', () => {
    wireDialog();
    const fromPath = location.pathname.split('/').filter(Boolean)[0];
    if (fromPath) current = fromPath;
    renderNav();
    $('#search').addEventListener('input', (e) => {
      const q = e.target.value.trim().toLowerCase();
      if (q === query) return;
      const was = !!query;
      query = q;
      if (!!q !== was || q) render();
    });
    document.addEventListener('keydown', (e) => {
      if ((e.metaKey && e.key === 'f') || (e.key === '/' && document.activeElement === document.body)) { e.preventDefault(); $('#search').focus(); }
    });
    // Escape on this page (11 Nov 2026): closes the page's open dialog (Add Site Search), else
    // clears and leaves the field being typed in, else does nothing. It is always handled here, so
    // it never goes on to the window: no tab closing, no leaving full screen, no window change.
    document.addEventListener('keydown', (e) => {
      if (e.key !== 'Escape' || e.metaKey || e.ctrlKey || e.altKey) return;
      e.preventDefault();
      e.stopPropagation();
      const open = document.querySelector('dialog[open]');
      if (open) { closeDialog(open); return; }
      const field = document.activeElement;
      if (field && field !== document.body && field.matches('input, textarea, select')) {
        if (field === $('#search') && query) { field.value = ''; query = ''; render(); }
        else if (field.type === 'search' && field.value) { field.value = ''; field.dispatchEvent(new Event('input')); }
        field.blur();
      }
    }, true);
    bridge.state().then(apply).catch((e) => {
      $('#content').replaceChildren(el('h1', { class: 'page-title' }, 'Settings'), el('div', { class: 'card' }, el('div', { class: 'empty' }, (e && e.message) || 'Settings opens in Pane.')));
    });
  });
})();
