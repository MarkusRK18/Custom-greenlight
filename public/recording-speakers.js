/* Speaker names are shown only where BBB recorded a timed talking event. */
(() => {
  const path = window.location.pathname;
  const id = path.match(/\/playback\/(?:presentation\/2\.3|video)\/([a-f0-9]+-\d+)/)?.[1];
  if (!id) return;
  const isVideo = path.includes('/playback/video/');
  const dataUrl = isVideo ? `/playback/video/${id}/speakers.json` : `/presentation/${id}/speakers.json`;
  fetch(dataUrl).then((response) => {
    if (!response.ok) throw new Error('Speaker data unavailable');
    return response.json();
  }).then((data) => {
    const box = document.createElement('aside');
    box.setAttribute('aria-live', 'polite');
    box.style.cssText = 'position:fixed;z-index:9999;right:16px;top:145px;max-width:260px;padding:10px 14px;background:rgba(0,42,17,.93);color:white;border-radius:8px;font:14px/1.4 sans-serif;box-shadow:0 2px 12px #0004;pointer-events:none';
    document.body.appendChild(box);
    const names = Array.isArray(data.participants) ? data.participants : [];
    const cues = Array.isArray(data.speakers) ? data.speakers : [];
    const media = data.media || {};
    const player = () => document.querySelector('audio') || document.querySelector('video');
    const update = () => {
      const seconds = player()?.currentTime || 0;
      const active = [...new Set(cues.filter((cue) => seconds >= cue.start && seconds < cue.end).map((cue) => cue.name))];
      if (active.length) box.textContent = `Speaking: ${active.join(', ')}`;
      else if (!Object.values(media).some(Boolean)) box.textContent = 'No microphone, camera, slides or screen share were captured in this recording.';
      else if (!cues.length) box.textContent = `Participants: ${names.join(', ') || 'None recorded'}. Timed speaker activity was not captured.`;
      else box.textContent = `Participants: ${names.join(', ')}`;
    };
    update();
    setInterval(update, 300);
  }).catch(() => {});
})();
