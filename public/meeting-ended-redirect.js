/* Return through BBB's own logout action if a client still renders its end dialog. */
(() => {
  if (!window.location.pathname.startsWith('/html5client/')) return;
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
