# Sri Shakthi deployment

This checkout contains portal branding, institutional account checks, host-only meeting creation/start, scheduled meeting windows and participant notification emails. It is running locally using compose.local.yml; production deployment remains outstanding.

## Deploy

Build this checkout with the provided Dockerfile and point docker-compose.yml at that built image; the upstream bigbluebutton/greenlight:v3 image does not contain these changes. Run `bundle exec rails db:migrate`, build frontend assets, then restart the portal. Back up the production database first.

Configure SMTP_SERVER and the other SMTP values in sample.env. Local signup no longer auto-verifies accounts when SMTP is missing. Existing verified flags remain unchanged: audit previously auto-verified accounts before production use. For OIDC, the identity provider must supply a boolean email_verified claim in extra.raw_info; unverified identities cannot join.

Default User/Guest roles are participant-only. Assign approved employees an Administrator, Faculty or Staff role and grant CreateRoom permission in role administration. Do not use domain-wide role mapping to grant staff access. Domain membership alone cannot distinguish staff from students. Existing student-owned rooms cannot start meetings. Schedule existing rooms before use.

Create or update a room with its date/time, duration and participant email addresses. Browser local times are converted to UTC. Invitations display IST and link to authenticated joining. Notification recipients must belong to srishakthi.ac.in; joining additionally requires an active verified account. The participant list is a notification list, not a meeting allowlist. A host starts the session within its scheduled window; it does not auto-start at the scheduled instant. Late starts use the remaining duration.

Emails are queued using the existing Active Job configuration. No real participant emails were sent during development. Configure a durable production job backend and worker for reliable delivery; verify delivery with a test institutional account.

## BigBlueButton server work

The portal passes Sri Shakthi logo/banner/copyright, disables infiniteWhiteboard and automatic multi-user whiteboard access, and sets the session duration. Infinite whiteboard requires BBB 3.0+. Presenter annotations are not fully disabled by these options. Enable displayBrandingArea on the BBB server for the logo, and customize its default welcome message/footer, default presentation and client title/favicon to remove remaining upstream identity. The BBB server and browsers must reach the public logo URL.

The generic portal welcome page is skipped in favor of sign-in. The portal join page remains in place for authentication, consent and waiting for a moderator. Hiding the BBB default welcome presentation or pre-meeting device screen requires confirming the installed BBB version and adjusting its server configuration; these screens are not managed by this repository.

## Process audit

The inspected execution environment exposed only the agent and inspection commands, with no running Rails, Redis, PostgreSQL or BigBlueButton services. No processes were stopped. On the actual deployment inspect `docker compose ps`, `docker stats --no-stream`, `ps -eo pid,ppid,comm,%cpu,%mem --sort=-%cpu` and `systemctl --failed`; BBB normally uses multiple services. Do not kill services based on process count alone.

## Verification

Ruby syntax and policy unit tests can be checked without a database. Full Rails request/model tests and frontend builds require installing the project's dependencies and configuring PostgreSQL/Redis. Test student direct API start/create denial, outsider/unverified joining denial, moderator-code escalation denial, schedule boundaries, late-start duration, and SMTP delivery in staging before deployment.
