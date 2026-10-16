# Run locally

The isolated local stack uses `compose.local.yml` and `.env.local` (generated secrets, excluded from Git). Other Docker projects are unaffected.

```sh
docker compose --env-file .env.local -f compose.local.yml up -d --build
docker compose --env-file .env.local -f compose.local.yml exec portal bundle exec rails db:migrate:with_data
```

Open http://localhost:5050. PostgreSQL and Redis are private to this stack. Persistent database and upload volumes survive restarts.

For phones and laptops on the same Wi-Fi, follow [local Wi-Fi setup](LOCAL_WIFI.md).
It provides HTTPS portal access and the meeting media ports on the host's LAN IP.

Invitation links allow a guest to enter a name and click Join Meeting to start an
available meeting as a Viewer. Existing and new rooms enable **Allow any user to
start** by default; hosts can turn it off in room settings. Scheduled times,
access codes and any room sign-in requirement still apply.

```sh
# Status and logs
docker compose --env-file .env.local -f compose.local.yml ps
docker compose --env-file .env.local -f compose.local.yml logs --tail 80 portal
# Stop the stack while keeping its database
docker compose --env-file .env.local -f compose.local.yml stop
```

The base local stack requires a running meeting server and its API credentials for meetings and recordings. For the local test server, follow LOCAL_BIGBLUEBUTTON.md and include compose.portal-bbb.yml when starting the portal. Enable recording in room settings before the meeting; it starts automatically when the host joins. The recording processor publishes playback after the meeting ends, and participant talk time appears when analytics arrives. SMTP is needed to deliver meeting invitations. Signup does not send verification emails.

A local administrator must be provisioned with your institutional email. The upstream seed account is not created because its email does not belong to siet.ac.in. New local siet.ac.in accounts are activated automatically without an email ownership check.

The local administrator selected for this run is `student_name@siet.ac.in`. Its generated initial password is stored in `tmp/local-admin-credentials.txt` with restricted permissions after provisioning. Change the password after first sign-in. Administrator status is an explicit local bootstrap assignment; the email's name does not change the student access policy.

## Verified local run

The stack is running at http://localhost:5050. Database migrations completed, the selected administrator was provisioned, the home page and supplied logo returned HTTP 200, and 17 transactional smoke checks passed. The checks covered administrator login/scheduling, student creation/start denial, Viewer-only joining, shared-access denial, schedule boundaries, unverified/unauthenticated denial, meeting branding and remaining duration, and invitation contents. The meeting backend was simulated in the checks; no real meetings were started or emails sent. The updated welcome, sign-in and signup pages were subsequently checked with headless Chromium for the institute logo, SIETConnect text and #004d00 headings. Signup without activation email and instant/scheduled meeting creation passed transactional API checks.
