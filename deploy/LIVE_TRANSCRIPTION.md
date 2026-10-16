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
2. Each speaker joins microphone audio, permits microphone access, and selects
   English in the transcription/language option of the audio setup. The language
   selector remains available so speakers can disable transcription.
3. Participants use the native caption control to display recognized speech.
   Speakers must enable transcription for their own speech to be shared. A
   listen-only participant does not transcribe the other speakers automatically.
4. Test with two devices: speak a few English sentences on one device and verify
   that the other receives captions. Then swap speakers and test again.

## Limits

Browser speech recognition may send audio to the browser vendor's service. It is
not an offline, wholly self-hosted recognizer. Recognition availability, quotas,
accuracy, and latency are controlled partly by the browser and its service.
There is no promise of perfect text or zero delay. Headsets, clear speech and a
stable network help; test local accents and course terminology before rollout.

This feature does not add a second custom microphone capture implementation,
replace meeting audio, or modify the recording speaker-highlight timeline.
Caption availability in recordings remains subject to BBB's native processing.

If captions do not appear, check the speaker's selected transcription language,
microphone permissions, browser compatibility, and network first. Existing native
YAML corruption is a separate server issue; the early client settings avoid
depending on that file for the caption interface.

Upstream configuration reference:
https://docs.bigbluebutton.org/3.0/administration/customize/
