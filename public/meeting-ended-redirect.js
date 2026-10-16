/* Return through BBB's own logout action if a client still renders its end dialog. */
(() => {
  if (!window.location.pathname.startsWith('/html5client/')) return;
  const applySettings = (settings) => {
    const app = settings?.public?.app;
    if (!app) return;
    // Also cover existing rooms when the server's native YAML cannot be loaded.
    // Keep the microphone dialog's language/off selector available to speakers.
    app.audioCaptions = {
      ...app.audioCaptions,
      enabled: true, alwaysVisible: true, mobile: true, provider: 'webspeech',
      language: {
        ...app.audioCaptions?.language,
        available: ['en-US'], locale: 'en-US', defaultSelectLocale: true, forceLocale: false,
      },
    };
    for (const [key, value] of [['skipMeetingEnded', true], ['clientTitle', 'SIETConnect']]) {
      const descriptor = Object.getOwnPropertyDescriptor(app, key);
      if (!descriptor || descriptor.configurable) {
        Object.defineProperty(app, key, {
          configurable: true, enumerable: true, get: () => value, set: () => {},
        });
      }
    }
  };
  // Run before the application bundle: apply the flag to both bundled defaults
  // and the settings object subsequently supplied by the meeting server.
  const descriptor = Object.getOwnPropertyDescriptor(window, 'meetingClientSettings');
  if (!descriptor || (descriptor.configurable && !descriptor.get && !descriptor.set)) {
    let settings = window.meetingClientSettings;
    applySettings(settings);
    Object.defineProperty(window, 'meetingClientSettings', {
      configurable: true, enumerable: true,
      get: () => settings,
      set: (value) => { applySettings(value); settings = value; },
    });
  } else {
    applySettings(window.meetingClientSettings);
  }
  const handled = new WeakSet();
  const redirect = () => {
    const modal = document.querySelector('[data-test="meetingEndedModal"]');
    const button = modal?.querySelector('[data-test="redirectButton"]');
    if (!button || button.disabled || handled.has(modal)) return;
    handled.add(modal);
    modal.style.setProperty('display', 'none', 'important');
    // The client's handler uses the meeting's logoutURL, including portal prefixes.
    button.click();
  };
  new MutationObserver(redirect).observe(document.documentElement, {
    childList: true, subtree: true, attributes: true, attributeFilter: ['disabled'],
  });
  redirect();
})();
