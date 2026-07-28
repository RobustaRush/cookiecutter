# Auth hardening — django-axes + 2FA

Docs: <https://django-axes.readthedocs.io/> · <https://docs.allauth.org/en/latest/mfa/introduction.html> · <https://django-otp-official.readthedocs.io/>

Two follow-up questions to Auth. Fire **only when** `auth ≠ none` (without an auth flow there's nothing to harden).

- `axes`: brute-force / lockout protection. Default **yes** when auth is selected.
- `2fa`: TOTP via built-in `allauth.mfa` (paired with `django-allauth`) or `django-otp` (paired with `django-mail-auth` or stock auth). Default **no** — opt-in.

## django-axes (lockout / brute-force)

Wraps the login path. Records every authentication attempt; locks an IP / username after N failures for a cool-off window.

### Install

```sh
uv add django-axes
```

### `base.py`

```python
INSTALLED_APPS += ['axes']

# AxesMiddleware MUST be the last entry — wraps every other middleware's
# auth attempts. Append so `production.py` middleware additions don't get
# dropped by re-declaring the list.
MIDDLEWARE += ['axes.middleware.AxesMiddleware']

AUTHENTICATION_BACKENDS = [
    'axes.backends.AxesBackend',
    # then the project's existing backends, e.g.:
    'django.contrib.auth.backends.ModelBackend',
    # 'allauth.account.auth_backends.AuthenticationBackend',
    # 'mailauth.backends.MailAuthBackend',
]

# Sane defaults — adjust per project tolerance.
AXES_FAILURE_LIMIT = 5
AXES_COOLOFF_TIME = 1          # hours
AXES_LOCKOUT_PARAMETERS = [['ip_address', 'username']]
AXES_RESET_ON_SUCCESS = True
```

`AxesBackend` must be **first** in `AUTHENTICATION_BACKENDS`. Wrong order silently disables lockout.

### Migrate

`axes` ships its own models:

```sh
uv run manage.py migrate
```

### `production.py` — cache handler when Redis is in scope

```python
# axes writes one DB row per failed attempt; the cache handler keeps the hot
# path in Redis. See references/redis.md for CACHES wiring.
AXES_HANDLER = 'axes.handlers.cache.AxesCacheHandler'
```

### Pitfalls

- Behind Caddy in Docker, `REMOTE_ADDR` is the proxy's IP for every request — install the extra (`uv add 'django-axes[ipware]'`) and point axes at the forwarded header:
  ```python
  AXES_IPWARE_PROXY_COUNT = 1
  AXES_IPWARE_META_PRECEDENCE_ORDER = ['HTTP_X_FORWARDED_FOR', 'REMOTE_ADDR']
  ```
  Check by hitting the login form from a known IP and reading `axes_accessattempt`.

## 2FA

Pick the matching package for the chosen Auth flow:

- **`django-allauth`** → use the built-in **`allauth.mfa`** (`uv add 'django-allauth[mfa]'`). MFA ships inside django-allauth itself; the third-party `allauth-2fa` package is unmaintained — do **not** install it. Add `allauth.mfa` to `INSTALLED_APPS`, include `allauth.mfa.urls` in the `accounts/` include, and run migrations. Users opt in from the account page; templates ship with allauth.
- **`django-mail-auth` or stock auth** → use **`django-otp`** with its bundled TOTP plugin (`uv add 'django-otp[qrcode]'`). Adds `django_otp`, `django_otp.plugins.otp_totp` to `INSTALLED_APPS`, `django_otp.middleware.OTPMiddleware` to `MIDDLEWARE` (after `AuthenticationMiddleware`). Wire admin login through `django_otp.admin.OTPAdminSite` if 2FA on `/admin/` is wanted.

For both: run migrations, then ship a UI flow for the user to enrol a TOTP secret (`allauth.mfa` includes templates; `django-otp` does not — wire your own).

### Settings — `production.py` only when allauth.mfa is used

```python
# Configures the enrolled factors and issuer name; enrollment stays opt-in from
# the account page — allauth.mfa has no setting that forces MFA at login.
MFA_TOTP_ISSUER = env("DJANGO_SITE_DOMAIN", default="example.com")
MFA_SUPPORTED_TYPES = ["totp", "recovery_codes"]
ACCOUNT_REAUTHENTICATION_REQUIRED = True
```

### Pitfalls

- 2FA + axes together: failed 2FA codes count as auth failures in axes. That's usually correct — verify the `AXES_LOCKOUT_PARAMETERS` aren't so aggressive that legitimate users get locked out for one mistyped code.
- Pin `django-allauth >= 65.0` — the settings `references/auth.md` writes (`ACCOUNT_LOGIN_METHODS`, `ACCOUNT_SIGNUP_FIELDS`) need it; never co-install `allauth-2fa`.
- `MFA_TOTP_ISSUER` should be the human-readable site name / domain, not the project slug — that string is what shows up in the user's authenticator app.
- TOTP requires accurate server time. Clock skew > 30s on the host = users fail to authenticate. Document NTP requirement in `README.md`.
