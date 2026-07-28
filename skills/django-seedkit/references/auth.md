# Authentication

Docs: <https://docs.allauth.org/> · <https://django-mail-auth.readthedocs.io/>

Stock Django ships barebones login/logout views and a `User` model. Pick one add-on:

- **`django-allauth`** — full account flows: signup, email verification, password reset, optional social providers (Google / GitHub), 2FA. The most-used auth library in the Django ecosystem.
- **`django-mail-auth`** — passwordless magic-link. Single tiny dependency, no passwords, no social providers.

If "no auth add-on", skip this reference.

Email backend (`references/email.md`) must be configured first — both options send mail.

---

## Option A — `django-allauth`

### Install

```sh
uv add django-allauth
```

### Settings — `base.py`

Append rather than redeclare so `production.py` overrides (WhiteNoise position, CSP middleware) survive:

```python
INSTALLED_APPS += [
    "django.contrib.sites",
    "allauth",
    "allauth.account",
    # "allauth.socialaccount",   # uncomment for social providers
]

MIDDLEWARE += ["allauth.account.middleware.AccountMiddleware"]

AUTHENTICATION_BACKENDS = [
    "django.contrib.auth.backends.ModelBackend",
    "allauth.account.auth_backends.AuthenticationBackend",
]

SITE_ID = 1
LOGIN_REDIRECT_URL = "/"           # don't send non-staff users to /admin/
                                   # — they bounce to a re-login screen.
                                   # The root view can redirect to /admin/
                                   # for now; replace once a real landing
                                   # page lands.
LOGOUT_REDIRECT_URL = "/accounts/login/"

ACCOUNT_LOGIN_METHODS = {"email"}
ACCOUNT_SIGNUP_FIELDS = ["email*", "password1*", "password2*"]
ACCOUNT_EMAIL_VERIFICATION = "optional"   # tightened in production
```

In `production.py` (or gate on `not DEBUG`):

```python
ACCOUNT_EMAIL_VERIFICATION = "mandatory"
```

Mandatory + console email = verification link only in `runserver` stdout — fine in prod with real SMTP, painful for local signup.

### URLs

```python
urlpatterns = [
    ...
    path("accounts/", include("allauth.urls")),
]
```

### Migrate

```sh
uv run manage.py migrate
```

`django.contrib.sites` ships a default Site row (`pk=1`, `domain="example.com"`) used for absolute URLs in verification / password-reset emails. Update it per environment via admin (`/admin/sites/site/1/`) or a data migration reading `DJANGO_SITE_DOMAIN` from env. Forgetting it sends links pointing at `example.com`.

Allauth ships its own templates; override only for branding.

### With a custom user model

If `references/custom-user.md` is applied, use the email-as-`USERNAME_FIELD` variant — `AbstractUser` requires a username, so plain subclassing fails email-only signup. Also add:

```python
ACCOUNT_USER_MODEL_USERNAME_FIELD = None
```

Without it, allauth's `get_username_max_length()` calls `User._meta.get_field("username")` and `/accounts/signup/` raises `FieldDoesNotExist`.

---

## Option B — `django-mail-auth`

User enters email → gets a one-time link → clicks → logged in. Three pieces ship in one package:

- `mailauth` — backend + `/accounts/login/` views (required)
- `mailauth.contrib.admin` — replaces Django admin's password login with the same magic-link flow (recommended)
- `mailauth.contrib.user` — provides an `EmailUser` model with `email` as `USERNAME_FIELD` and no password column (alternative to writing your own custom user)

### Install

```sh
uv add django-mail-auth
```

### User model — pick one route

Decide before the first migration. The choice mirrors `references/custom-user.md`:

- **`mailauth.contrib.user`** (simplest, no custom code). Add the app and `AUTH_USER_MODEL = "mailauth_user.EmailUser"`. Skip `custom-user.md` entirely.
- **Your own custom user** (`references/custom-user.md` email-only variant). Keep `users.User` as `AUTH_USER_MODEL`; mailauth works against any model with an `email` field.
- **Stock `auth.User`**. Works, but stock `auth.User.email` has no `unique=True`, and `MailAuthBackend.authenticate()` silently picks the first match when two users share an address — anyone who can sign up twice can hijack the other user's magic-link login. If you stay on stock `auth.User`, add a `UniqueConstraint` via a data migration *and* an admin-side validator. Easier path: pick `mailauth.contrib.user` (handles uniqueness for you) or the email-only custom user from `references/custom-user.md`.

### Settings

```python
# `mailauth.contrib.admin` MUST come before `django.contrib.admin` —
# Django resolves admin templates / login view in app order, so the
# overriding app has to load first. After-ordering silently leaves the
# stock password-login admin in place. This requires editing the
# existing INSTALLED_APPS list in place rather than appending.
INSTALLED_APPS = [
    # ... existing prefix entries kept ...
    "mailauth.contrib.admin",       # admin login → magic link too
    "django.contrib.admin",         # already present from startproject
    # ... other contrib apps ...
    "mailauth",
    "mailauth.contrib.user",        # only if EmailUser route picked
]

AUTHENTICATION_BACKENDS = [
    "mailauth.backends.MailAuthBackend",
    # Drop ModelBackend if no password support is needed (the EmailUser
    # route has no password column, so it can never authenticate anyway).
    "django.contrib.auth.backends.ModelBackend",
]

# Only when the EmailUser route is picked:
AUTH_USER_MODEL = "mailauth_user.EmailUser"

LOGIN_URL = "mailauth:login"
LOGIN_REDIRECT_URL = "/"            # see Option A — don't dump non-staff
                                    # users on /admin/.
```

### URLs

```python
from django.urls import include, path

urlpatterns = [
    ...
    path("accounts/", include("mailauth.urls")),
]
```

No `namespace=...` argument — `app_name = "mailauth"` is already declared inside the package's `urls.py`.

### Templates

mailauth ships the email-body and email-subject templates and *expects you to provide* the HTML pages. All paths live under `templates/registration/` (Django's convention; this is what upstream's views resolve to):

```html
{# templates/registration/login.html — required #}
{% extends "base.html" %}
{% block content %}
<h1>Sign in</h1>
<form method="post">{% csrf_token %}{{ form }}<button>Send link</button></form>
{% endblock %}

{# templates/registration/login_requested.html — required #}
{% extends "base.html" %}
{% block content %}
<h1>Check your inbox</h1>
<p>We sent a sign-in link to that address. The link is valid for a few minutes.</p>
{% endblock %}

{# templates/registration/logged_out.html — required for the logout flow #}
{% extends "base.html" %}
{% block content %}<p>Signed out.</p>{% endblock %}

{# templates/registration/login_email.html — optional; HTML body. If absent, only the package's plain-text body is sent. #}
<a href="{{ code.url }}">Sign in</a>
```

`registration/login_email.txt` and `registration/login_subject.txt` ship inside the package — override them only to customise wording.

Add `BASE_DIR / "templates"` to `TEMPLATES[0]["DIRS"]` if it isn't there already.

### Migrate

```sh
uv run manage.py migrate
```

The package itself ships no models. The migration step exists because the EmailUser route (if picked) creates `mailauth_user.EmailUser` and its initial migration.

### Testing locally

mailauth needs a working email backend (`references/email.md`). With `EMAIL_URL=consolemail://` the magic link prints to `runserver` stdout; with Mailpit it lands in the Mailpit UI. With nothing configured the SMTP default points at `localhost:25` and login silently fails.
