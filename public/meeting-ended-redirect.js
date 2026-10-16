/* Return through BBB's own logout action if a client still renders its end dialog. */
(() => {
  if (!window.location.pathname.startsWith('/html5client/')) return;
  const skipDialog = (settings) => {
    const app = settings?.public?.app;
    if (!app) return;
    const descriptor = Object.getOwnPropertyDescriptor(app, 'skipMeetingEnded');
    if (!descriptor || descriptor.configurable) {
      Object.defineProperty(app, 'skipMeetingEnded', {
        configurable: true, enumerable: true, get: () => true, set: () => {},
      });
    }
  };
  // Run before the application bundle: apply the flag to both bundled defaults
  // and the settings object subsequently supplied by the meeting server.
  const descriptor = Object.getOwnPropertyDescriptor(window, 'meetingClientSettings');
  if (!descriptor || (descriptor.configurable && !descriptor.get && !descriptor.set)) {
    let settings = window.meetingClientSettings;
    skipDialog(settings);
    Object.defineProperty(window, 'meetingClientSettings', {
      configurable: true, enumerable: true,
      get: () => settings,
      set: (value) => { skipDialog(value); settings = value; },
    });
  } else {
    skipDialog(window.meetingClientSettings);
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
