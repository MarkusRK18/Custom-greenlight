# Live English transcription

SIETConnect enables BBB 3.0's native live caption interface with the `webspeech`
provider. No API key, paid transcription service, model download or additional
server is required. This is English speech to English text, not translation.

## Deploy and use

Run the custom installer as usual. It enables captions in new meeting creation
options and in the early live-client settings script for existing room links.
Close old meeting tabs after deployment and rejoin through the existing link.

1. Use HTTPS and a browser with SpeechRecognition support, preferably current
   Google Chrome or Microsoft Edge. Chromium builds without a working recognition
   backend and unsupported mobile browsers may not transcribe.
2. Each speaker joins microphone audio and permits microphone access. Recognition
   starts automatically when connected and unmuted, using Indian English (`en-IN`)
   through BBB's native fixed-locale setting. Microphone permissions are still
   required. Muting or leaving microphone audio stops native recognition.
3. Participants use the native caption control to display recognized speech.
   Each speaker must join microphone audio for their speech to be transcribed. A
   listen-only participant does not transcribe the other speakers automatically.
4. Test with two devices: speak a few English sentences on one device and verify
   that the other receives captions. Then swap speakers and test again.

## Limits

Browser speech recognition may send audio to the browser vendor's service. It is
not an offline, wholly self-hosted recognizer. Recognition availability, quotas,
accuracy, and latency are controlled partly by the browser and its service.
There is no promise of perfect text or zero delay. Headsets, clear speech and a
stable network help; test local accents and course terminology before rollout.
Indian English is a locale choice for this college audience, not a verified
accuracy improvement. Recognition quality still requires a real two-device test.

The installer removes BBB 3's extra 200 ms caption-submit debounce when the
installed bundle matches the verified code pattern. Interim results then go
directly to BBB's existing caption mutation, and finalized text still uses its
original path. Backups are retained; unrecognized bundle versions are not edited.
This does not speed up the browser vendor's recognition or eliminate network
latency. Reload/rejoin after installation to fetch the updated bundle.

This feature does not add a second custom microphone capture implementation,
replace meeting audio, or modify the recording speaker-highlight timeline.
Caption availability in recordings remains subject to BBB's native processing.

If captions do not appear, check that the speaker is unmuted in microphone audio,
microphone permissions, browser compatibility, and network first. Existing native
YAML corruption is a separate server issue; the early client settings avoid
depending on that file for the caption interface.

Upstream configuration reference:
https://docs.bigbluebutton.org/3.0/administration/customize/
