/* Recording playback only: highlight participants using BBB's recorded speech timeline. */
(() => {
  const path = window.location.pathname;
  const id = path.match(/\/playback\/(?:presentation\/2\.3|video)\/([a-f0-9]+-\d+)/)?.[1];
  if (!id || document.getElementById('sietconnect-speakers')) return;
  const dataUrl = path.includes('/playback/video/')
    ? `/playback/video/${id}/speakers.json` : `/presentation/${id}/speakers.json`;
  const loadData = async () => {
    for (let attempt = 0; attempt < 60; attempt += 1) {
      try {
        const response = await fetch(dataUrl, { cache: 'no-store', signal: AbortSignal.timeout(5000) });
        if (!response.ok) throw new Error('Speaker data unavailable');
        return await response.json();
      } catch {
        if (attempt < 59) await new Promise((resolve) => setTimeout(resolve, 2000));
      }
    }
    return { participants: [], unavailable: true };
  };
  loadData().then((data) => {
    const participants = Array.isArray(data.participant_details) ? data.participant_details
      : (data.participants || []).map((name) => ({ id: name, name }));
    const cues = (Array.isArray(data.speakers) ? data.speakers : []).filter((cue) => (
      Number.isFinite(cue.start) && Number.isFinite(cue.end) && cue.end > cue.start
    ));
    const style = document.createElement('style');
    style.textContent = `
      body.sietconnect-recording-layout { display:grid !important; grid-template-columns:minmax(0,1fr) 240px;
        margin:0 !important; width:100% !important; height:100vh; overflow:hidden; }
      #sietconnect-recording-stage { min-width:0; height:100vh; overflow:auto; transform:translateZ(0); }
      #sietconnect-speakers { box-sizing:border-box; height:100vh; padding:24px 14px 60px;
        overflow:auto; background:#f5f8f5; color:#17271b; border-left:1px solid #dce5dd;
        font:14px/1.4 system-ui,sans-serif; }
      #sietconnect-speakers h2 { margin:0 0 5px; font-size:18px; color:#004d00; }
      #sietconnect-speakers .speaker-notice { margin:0 0 22px; color:#59665c; font-size:12px; }
      #sietconnect-speakers .speaker-row { display:flex; align-items:center; gap:12px;
        margin:6px 0; padding:12px 8px; border-radius:10px; }
      #sietconnect-speakers .speaker-avatar { box-sizing:border-box; display:grid; place-items:center;
        width:44px; height:44px; flex:none; border-radius:50%; background:#e0e8e1; color:#32503a;
        font-weight:600; border:2px solid transparent; }
      #sietconnect-speakers .speaker-name { overflow-wrap:anywhere; font-weight:600; }
      #sietconnect-speakers .speaker-state { display:block; font-size:12px; color:#667369; }
      #sietconnect-speakers .is-speaking { background:#e5f3e7; }
      #sietconnect-speakers .is-speaking .speaker-avatar { border-color:#00872c;
        outline:3px solid #00872c; outline-offset:3px; background:#d4eedb; color:#004d00; }
      #sietconnect-speakers .is-speaking .speaker-state { color:#006824; font-weight:600; }
      @media(max-width:700px) {
        body.sietconnect-recording-layout { grid-template-columns:minmax(0,1fr) 160px; }
        #sietconnect-speakers { padding:18px 8px 60px; }
        #sietconnect-speakers .speaker-row { gap:9px; padding:12px 5px; }
        #sietconnect-speakers .speaker-avatar { width:32px; height:32px; font-size:12px; }
      }
    `;
    document.head.appendChild(style);
    const stage = document.createElement('div');
    stage.id = 'sietconnect-recording-stage';
    [...document.body.childNodes].forEach((child) => stage.appendChild(child));
    document.body.appendChild(stage);
    document.body.classList.add('sietconnect-recording-layout');
    const panel = document.createElement('aside');
    panel.id = 'sietconnect-speakers';
    panel.setAttribute('aria-label', 'Recorded meeting participants');
    const title = document.createElement('h2');
    title.textContent = 'Participants';
    const notice = document.createElement('p');
    notice.className = 'speaker-notice';
    notice.textContent = cues.length ? 'A green ring shows who is speaking.'
      : 'Speaker timing was not captured for this recording.';
    if (data.media && !Object.values(data.media).some(Boolean)) {
      notice.textContent = 'No microphone, camera, slides or screen share were captured in this recording.';
    }
    panel.append(title, notice);
    const rows = participants.map((participant) => {
      const row = document.createElement('div');
      row.className = 'speaker-row';
      const avatar = document.createElement('span');
      avatar.className = 'speaker-avatar';
      avatar.setAttribute('aria-hidden', 'true');
      avatar.textContent = String(participant.name || '?').trim().split(/\s+/).slice(0, 2)
        .map((word) => [...word][0] || '').join('').toUpperCase();
      const label = document.createElement('div');
      const name = document.createElement('span');
      name.className = 'speaker-name';
      name.textContent = participant.name;
      const state = document.createElement('span');
      state.className = 'speaker-state';
      state.textContent = 'Participant';
      label.append(name, state);
      row.append(avatar, label);
      panel.appendChild(row);
      return { participant, row, state };
    });
    if (!rows.length) notice.textContent = data.unavailable
      ? 'Participant data is not available yet. Reload to retry.'
      : 'No participant information is available for this recording.';
    document.body.appendChild(panel);
    const player = () => stage.querySelector('audio') || stage.querySelector('video');
    const update = () => {
      const media = player();
      const playing = media && !media.paused && !media.ended && !media.seeking;
      const seconds = media?.currentTime || 0;
      rows.forEach(({ participant, row, state }) => {
        const speaking = Boolean(playing && cues.some((cue) => seconds >= cue.start && seconds < cue.end
          && (cue.participant_id ? cue.participant_id === participant.id : cue.name === participant.name)));
        row.classList.toggle('is-speaking', speaking);
        state.textContent = speaking ? 'Speaking' : 'Participant';
      });
    };
    const bound = new WeakSet();
    const bindMedia = () => {
      stage.querySelectorAll('audio,video').forEach((media) => {
        if (bound.has(media)) return;
        bound.add(media);
        ['timeupdate', 'play', 'pause', 'seeking', 'seeked', 'ended', 'ratechange', 'emptied'].forEach((event) => {
          media.addEventListener(event, update);
        });
      });
    };
    new MutationObserver(bindMedia).observe(stage, { childList: true, subtree: true });
    bindMedia();
    update();
    const tick = () => { update(); requestAnimationFrame(tick); };
    requestAnimationFrame(tick);
  }).catch(() => {});
})();
