# GDPR / privacy

Docs: <https://docs.sentry.io/platforms/python/data-management/sensitive-data/>

Concrete settings for projects with EU users or regulated data.

## Sentry SDK — strip PII

```python
def _scrub(event, hint):
    request = event.get("request") or {}
    headers = request.get("headers") or {}
    for h in ("Authorization", "Cookie"):
        headers.pop(h, None)
    return event

sentry_sdk.init(
    dsn=SENTRY_DSN,
    integrations=[DjangoIntegration()],
    send_default_pii=False,
    before_send=_scrub,
)
```

## Data residency

| Backend | Where data lives |
|---------|------------------|
| Bugsink / GlitchTip (self-hosted) | Your VPS |
| Sentry SaaS — EU region | de.sentry.io (choose at signup) |
| Sentry SaaS — US region | sentry.io |

## Retention

- Bugsink: `RETENTION_*` env vars per project.
- GlitchTip: per-organization in admin UI.
- App data (user models, audit log): periodic task that deletes records past retention.

## Analytics

| Backend | Cookies | Consent banner needed | Data residency |
|---|---|---|---|
| GoatCounter / Umami / Shynet (self-host) | no | no | your VPS |
| GoatCounter / Umami SaaS (EU region) | no | no | EU |
| Google Analytics 4 | yes | yes (EU) | US |

GA4 in the EU requires Google Consent Mode v2 with a CMP-driven banner. Load gtag with denied defaults, then update on consent:

```js
window.dataLayer = window.dataLayer || [];
function gtag(){dataLayer.push(arguments);}
gtag('consent', 'default', {
  ad_storage: 'denied',
  analytics_storage: 'denied',
  ad_user_data: 'denied',
  ad_personalization: 'denied',
});
// after the user accepts in your CMP:
// gtag('consent', 'update', { analytics_storage: 'granted', ... });
```

## Cookies / sessions

`SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE` — `references/security.md`.

Add `SESSION_COOKIE_SAMESITE = "Lax"` if not using cross-site auth. When `references/cors.md` is applied for a cookie-authenticated cross-origin frontend, its `"None"` wins.

## Logging

Don't log request bodies or `Authorization` headers. With structured logging add a filter that drops these keys.

## User data export & deletion

Two management commands under a registered app (e.g. `jobs/management/commands/`):

```python
# export_user_data.py
import json
from django.contrib.auth import get_user_model
from django.core import serializers
from django.core.management.base import BaseCommand

class Command(BaseCommand):
    def add_arguments(self, parser):
        parser.add_argument("user_id", type=int)

    # The export goes to the data subject — internal auth state stays out,
    # and the password hash above all.
    EXCLUDE = {"password", "is_staff", "is_superuser", "groups", "user_permissions"}

    def handle(self, *args, user_id, **opts):
        user = get_user_model().objects.get(pk=user_id)
        data = json.loads(serializers.serialize("json", [user]))
        for obj in data:
            obj["fields"] = {k: v for k, v in obj["fields"].items() if k not in self.EXCLUDE}
        self.stdout.write(json.dumps(data, indent=2))
```

```python
# delete_user_data.py
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.db import transaction

class Command(BaseCommand):
    def add_arguments(self, parser):
        parser.add_argument("user_id", type=int)

    def handle(self, *args, user_id, **opts):
        with transaction.atomic():
            get_user_model().objects.filter(pk=user_id).delete()
        self.stdout.write(self.style.SUCCESS(f"deleted user {user_id}"))
```

Extend `export_user_data` to dump user-owned rows from project apps. Deletion relies on `on_delete=CASCADE` for related models; add an immutable audit log entry if regulators require proof of erasure.

With `references/billing.md` wired, deletion must also call `stripe.Customer.delete(user.stripe_customer_id)` — erasing the DB row leaves the person's PII at Stripe.
