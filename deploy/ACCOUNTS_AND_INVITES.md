# Accounts, captions and meeting invitations

## Current changes

- Self-signup validates the institutional email address and sends a verification
  link. It no longer marks the email as verified before the user opens that link.
  Administrator-created accounts retain the existing provisioning behavior.
- Existing verified accounts are unchanged. Previously auto-verified accounts
  are not evidence of mailbox ownership; this release does not revoke them.
- Password fields have accessible show/hide buttons. Forgot password is always
  available on the sign-in page. Reset links expire after one hour, work once,
  and reset existing sessions. An invalid replacement password keeps the link valid.
- Without SMTP, signup, resend verification and password reset report that mail
  delivery needs configuration. Existing users can still sign in.
- Live English captions remain enabled by the existing installer. Each speaker
  needs a supported browser and microphone audio. See [LIVE_TRANSCRIPTION.md](LIVE_TRANSCRIPTION.md).
- Translation is deferred: the requested scope is English captions only for now.
- New meeting sessions use `guestPolicy=ASK_MODERATOR`. Viewer join links set
  `guest=true`, so the host must approve admission. Room owners and shared-room
  moderators join without the guest flag. Existing access codes, authentication
  requirements and meeting schedules still apply.

This uses BBB's documented [guest admission policy](https://docs.bigbluebutton.org/development/api/).
Existing room invitation links continue working. End running sessions and start
them again after deployment to apply the creation policy; it cannot change a
session already created on BBB. A guest who starts an empty room waits for the
host and cannot approve their own entry.

## Mail setup required

The server currently has no outgoing mail account. Obtain a free mailbox with
SMTP access or an approved college SMTP relay before enabling public signup.
No paid mail API is required. Do not paste credentials into chat or commit them.

Edit the existing deployment's private `.env` (for example
`/root/greenlight-v3/.env`) with the values provided by that mail service:

```dotenv
SMTP_SERVER=your-smtp-host
SMTP_PORT=587
SMTP_DOMAIN=your-mail-domain
SMTP_USERNAME=your-mailbox
SMTP_PASSWORD=your-smtp-password
SMTP_AUTH=plain
SMTP_STARTTLS_AUTO=true
SMTP_STARTTLS=true
SMTP_TLS=false
SMTP_SSL_VERIFY=true
SMTP_SENDER_EMAIL=your-approved-sender-address
SMTP_SENDER_NAME=SIETConnect
```

These settings illustrate STARTTLS on port 587; use the provider's actual TLS
settings. Keep the file readable only by its owner. Run the custom installer to
recreate the app with the new environment and built-in account checks.

Test delivery with your own institutional address: sign up, receive and open the
verification email, sign in, request a password reset and confirm its email arrives.
The installer's account checks use an in-memory mail queue and roll back their
database fixtures. They do not establish SMTP delivery or mailbox receipt.

For host approval, open a new meeting as its owner and use its normal room invite
link in a private browser. The guest should wait until the host accepts them.
