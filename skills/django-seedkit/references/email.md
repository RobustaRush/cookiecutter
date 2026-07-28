# Email

Docs: <https://django-environ.readthedocs.io/en/latest/types.html#environ-env-email-url> · <https://anymail.dev/> · <https://mailpit.axllent.org/> · <https://docs.djangoproject.com/en/stable/topics/email/>

Stock Django wires email backend / host / port / user / pass / tls one setting at a time. `django-environ`'s `email_url` parser collapses that into a single `EMAIL_URL` env var (`consolemail://`, `smtp+tls://user:pass@host:port`, …). Same shape as `DATABASE_URL`; swap providers without touching code.

## Settings

In `config/settings.py` (or `config/settings/base.py`):

```python
# Gated default keeps dev zero-config but fails fast in prod (where DEBUG
# is unset). Use `env.NOTSET` for the prod branch — `default=None` would
# pass None into env.email_url() / env(), which then crashes with TypeError
# on URL parsing or silently propagates as `DEFAULT_FROM_EMAIL = None`.
# `env.NOTSET` raises ImproperlyConfigured cleanly at startup naming the
# missing variable.
globals().update(env.email_url(
    "EMAIL_URL",
    default="consolemail://" if DEBUG else env.NOTSET,
))

DEFAULT_FROM_EMAIL = env(
    "DEFAULT_FROM_EMAIL",
    default="webmaster@localhost" if DEBUG else env.NOTSET,
)
SERVER_EMAIL = env("SERVER_EMAIL", default=DEFAULT_FROM_EMAIL)

ADMINS = [(email.split("@")[0], email) for email in env.list("DJANGO_ADMINS", default=[])]
MANAGERS = ADMINS
```

`.env` must exist before the first `manage.py` invocation. Some
django-environ versions raise `ImproperlyConfigured` on a missing `.env`
file rather than falling through to the gated defaults — `cp .env.example
.env` is the safest first step in the README.

`ADMINS` receive 500-error emails (when `DEBUG=False`) and any `mail_admins()` call. Leave empty in dev — console backend prints to stdout anyway.

If allauth is configured with `ACCOUNT_EMAIL_VERIFICATION = "mandatory"` in production, the gated default is what saves you: console backend would block every signup because the verification link only goes to stdout. Production must set `EMAIL_URL` to a real SMTP URL.

`EMAIL_URL` schemes:

- `consolemail://` — print to stdout (dev default)
- `smtp://user:pass@host:port` — plain SMTP
- `smtp+tls://user:pass@host:port` — STARTTLS (port 587)
- `smtp+ssl://user:pass@host:port` — implicit TLS (port 465)
- `dummymail://` — drop silently (tests)

## .env (local)

```sh
EMAIL_URL=consolemail://
DEFAULT_FROM_EMAIL=webmaster@localhost
```

Also append to `.env.example` so the var is discoverable:

```sh
EMAIL_URL=consolemail://
# DEFAULT_FROM_EMAIL=webmaster@localhost
# SERVER_EMAIL=root@example.com
# DJANGO_ADMINS=admin@example.com,ops@example.com
```

## .env.prod (VPS)

Pick the URL matching your provider:

```sh
# Postmark SMTP
EMAIL_URL=smtp+tls://<server-token>:<server-token>@smtp.postmarkapp.com:587
# SendGrid SMTP
EMAIL_URL=smtp+tls://apikey:<api-key>@smtp.sendgrid.net:587
# Mailgun SMTP
EMAIL_URL=smtp+tls://<smtp-user>:<smtp-password>@smtp.mailgun.org:587
# AWS SES SMTP
EMAIL_URL=smtp+tls://<smtp-user>:<smtp-password>@email-smtp.<region>.amazonaws.com:587

DEFAULT_FROM_EMAIL=no-reply@example.com
SERVER_EMAIL=django@example.com
DJANGO_ADMINS=ops@example.com,alerts@example.com
```

URL-encode special characters in the password (`%40` for `@`, `%23` for `#`).

**Before mail delivers:** add SPF and DKIM DNS records for the sending domain (each provider prints the exact records in its dashboard); most also want a DMARC record. Without them a correct `EMAIL_URL` still gets password-reset and verification mail dropped or spam-filed.

---

## Provider HTTP APIs (django-anymail)

SMTP works everywhere but is slower than provider HTTP APIs and exposes none of the provider's features (templated emails, click tracking, event webhooks). `django-anymail` ships per-provider `EmailBackend` classes that talk the provider's HTTP API instead.

Pick this over SMTP when:

- The provider charges per-message and you want delivery-event webhooks (delivered / bounced / complained / opened).
- You want to use server-stored templates with merge variables instead of rendering MIME locally.
- The platform blocks outbound port 587 (some serverless / managed runtimes do).

### Install

Pick the provider extra at install time:

```sh
uv add 'django-anymail[postmark]'      # or [amazon-ses], [sendgrid], [mailgun], [mandrill], [sparkpost], [brevo]
```

### Settings

Anymail's `EMAIL_BACKEND` overrides whatever `EMAIL_URL` parsed. Keep the `globals().update(env.email_url(...))` line as the dev fallback, but relax its gate to an unconditional default — the `.env.prod` for this setup no longer carries `EMAIL_URL`, and the `env.NOTSET` branch would crash the prod boot with `ImproperlyConfigured`:

```python
globals().update(env.email_url("EMAIL_URL", default="consolemail://"))
```

```python
INSTALLED_APPS += ["anymail"]

# Use provider API in prod; consolemail in dev. Same gating shape as
# the rest of the foundation.
if not DEBUG:
    EMAIL_BACKEND = "anymail.backends.postmark.EmailBackend"

ANYMAIL = {
    "POSTMARK_SERVER_TOKEN": env("POSTMARK_SERVER_TOKEN", default="" if DEBUG else env.NOTSET),
    # Provider-specific keys — see anymail.readthedocs.io for the full list.
    # SES: "AMAZON_SES_CLIENT_PARAMS", or use boto3's standard env vars.
    # SendGrid: "SENDGRID_API_KEY".
    # Mailgun: "MAILGUN_API_KEY", "MAILGUN_SENDER_DOMAIN".
}
```

### .env.prod

```sh
POSTMARK_SERVER_TOKEN=<token>
DEFAULT_FROM_EMAIL=no-reply@example.com
SERVER_EMAIL=django@example.com
```

`EMAIL_URL` is no longer needed in prod with this setup — `EMAIL_BACKEND` wins, and the relaxed gate above makes the missing var safe.

### Webhooks (optional)

Provider event webhooks (delivered / bounced / opened / clicked) need a Django URL exposed:

```python
# config/urls.py
urlpatterns = [
    ...
    path("anymail/", include("anymail.urls")),
]
```

```python
# settings — protect against forged webhook calls
ANYMAIL["WEBHOOK_SECRET"] = env("ANYMAIL_WEBHOOK_SECRET", default="" if DEBUG else env.NOTSET)
```

The provider needs configuring with `ANYMAIL_WEBHOOK_SECRET` as HTTP basic auth (`https://<secret>@example.com/anymail/<provider>/tracking/`). Connect signals to react to events:

```python
from anymail.signals import tracking

def handle_event(sender, event, esp_name, **kwargs):
    # event.event_type: "delivered", "bounced", "opened", ...
    ...

tracking.connect(handle_event)
```

---

## Managed platforms

Set `EMAIL_URL` and `DEFAULT_FROM_EMAIL` as platform env vars.

- **Fly.io**: `fly secrets set EMAIL_URL=... DEFAULT_FROM_EMAIL=...`
- **Railway / Render**: project-variables UI.

Application mail uses `DEFAULT_FROM_EMAIL`; error reports to `ADMINS` use `SERVER_EMAIL`.

---

## Optional — Mailpit for local HTML preview

Apply only if the user wants a web UI to inspect rendered emails locally.

### docker-compose.yml

```yaml
services:
  mailpit:
    image: axllent/mailpit:latest
    environment:
      MP_MAX_MESSAGES: 5000
      MP_SMTP_AUTH_ACCEPT_ANY: 1
      MP_SMTP_AUTH_ALLOW_INSECURE: 1
    ports:
      # Bind to loopback — MP_SMTP_AUTH_ACCEPT_ANY + ALLOW_INSECURE
      # would otherwise expose an open SMTP relay to the LAN.
      - "127.0.0.1:1025:1025"  # SMTP
      - "127.0.0.1:8025:8025"  # web UI
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8025/livez"]
      interval: 5s
      timeout: 3s
      retries: 5
```

`docker compose up -d --wait` polls this probe; without a `healthcheck` block `--wait` returns immediately on `running` and may race the SMTP listener.

### .env

Django runs on the host and talks to Mailpit via the published port:

```sh
EMAIL_URL=smtp://localhost:1025
```

Open <http://localhost:8025> to view captured emails.

### Pitfalls

- Inline every CSS rule. Gmail / Outlook strip `<style>` blocks. Tools like `premailer` can do this at build time; for a starter, write inline styles by hand and keep the palette small.
- Don't reference Tailwind classes in email HTML. Tailwind output is purged against templates `@source`'d in `source.css` — email templates would either bloat the bundle (if added to `@source`) or miss styles (if not). Write the small inline subset you need.
- Test with a real client. Litmus / Email on Acid render previews; or just send to one Gmail and one Outlook account before declaring a template done.

---

## Optional — HTML email base template

Apply when the user opts in (follow-up under the email-backend question). Without it, transactional mail (allauth verification, password resets) goes out as bare text — functional, but off-brand once the product has a look.

The Mailpit `### Pitfalls` above set the constraints: table layout, inline styles only, no Tailwind classes.

### `templates/email/base.html`

```django
<!DOCTYPE html>
<html>
<body style="margin:0; padding:0; background-color:#f4f4f5;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f4f5;">
    <tr>
      <td align="center" style="padding:24px;">
        <table role="presentation" width="600" cellpadding="0" cellspacing="0"
               style="background-color:#ffffff; border-radius:8px; max-width:600px; width:100%;">
          <tr>
            <td style="padding:32px; font-family:Arial, Helvetica, sans-serif; font-size:16px; line-height:1.5; color:#18181b;">
              <p style="margin:0 0 16px; font-size:20px; font-weight:bold;"><project name></p>
              {% block content %}{% endblock %}
            </td>
          </tr>
          <tr>
            <td style="padding:16px 32px; font-family:Arial, Helvetica, sans-serif; font-size:12px; color:#71717a;">
              <project name> · <site URL>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
```

Replace `<project name>` / `<site URL>` at scaffold time. Match the two color pairs to the project's theme. Every message keeps a plain-text version alongside the HTML — send both via `EmailMultiAlternatives` (the command below shows the shape).

When allauth is selected, override its email templates under `templates/account/email/` to extend this base. With django-mail-auth, the optional `templates/registration/login_email.html` (see `references/auth.md`) can extend it too.

### `send_test_email` command

Under a registered app (e.g. `<app>/management/commands/send_test_email.py`). If the project has no domain app yet, hold this until one exists — same rule as `tasks.py` (see SKILL.md App layout).

```python
from django.conf import settings
from django.core.mail import EmailMultiAlternatives
from django.core.management.base import BaseCommand
from django.template.loader import render_to_string


class Command(BaseCommand):
    def add_arguments(self, parser):
        parser.add_argument("recipient")

    def handle(self, *args, recipient, **opts):
        msg = EmailMultiAlternatives(
            subject="Test email",
            body="If you can read this, plain-text email delivery works.",
            from_email=settings.DEFAULT_FROM_EMAIL,
            to=[recipient],
        )
        msg.attach_alternative(render_to_string("email/test.html"), "text/html")
        msg.send()
        self.stdout.write(self.style.SUCCESS(f"sent to {recipient}"))
```

### `templates/email/test.html`

```django
{% extends "email/base.html" %}
{% block content %}
<p style="margin:0;">If you can read this with styling, HTML email rendering works.</p>
{% endblock %}
```

### Verifying

```sh
uv run manage.py send_test_email you@example.com
```

With the console backend the MIME source prints to stdout; with Mailpit up, inspect the rendered HTML at <http://localhost:8025>.
