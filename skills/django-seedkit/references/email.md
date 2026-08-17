# Email (Django 6.1)

Docs: <https://docs.djangoproject.com/en/6.1/howto/mailers-migration/> · <https://docs.djangoproject.com/en/6.1/topics/email/>

Django 6.1 deprecates `EMAIL_BACKEND` and transport `EMAIL_*` settings; they are removed in Django 7.0. Use `MAILERS`. `DEFAULT_FROM_EMAIL`, `SERVER_EMAIL`, `ADMINS`, `MANAGERS`, and `EMAIL_SUBJECT_PREFIX` are unchanged.

Do not use `env.email_url()`: it creates deprecated Django settings.

## SMTP

```python
DEFAULT_FROM_EMAIL = env(
    "DEFAULT_FROM_EMAIL", default="webmaster@localhost" if DEBUG else env.NOTSET
)
SERVER_EMAIL = env("SERVER_EMAIL", default=DEFAULT_FROM_EMAIL)
ADMINS = [(address.split("@", 1)[0], address) for address in env.list("DJANGO_ADMINS", default=[])]

MAILERS = {
    "default": {
        "BACKEND": (
            "django.core.mail.backends.console.EmailBackend"
            if DEBUG else "django.core.mail.backends.smtp.EmailBackend"
        ),
        "OPTIONS": {} if DEBUG else {
            "host": env("DJANGO_MAIL_HOST", default=env.NOTSET),
            "port": env.int("DJANGO_MAIL_PORT", default=587),
            "use_tls": env.bool("DJANGO_MAIL_USE_TLS", default=True),
            "username": env("DJANGO_MAIL_USERNAME", default=""),
            "password": env("DJANGO_MAIL_PASSWORD", default=""),
            "timeout": env.int("DJANGO_MAIL_TIMEOUT", default=10),
        },
    },
}
```

Local uses the console mailer. Production needs `DJANGO_MAIL_HOST`; set the remaining `DJANGO_MAIL_*` variables as needed. Add them to `.env.example`.

Direct migration:

```python
# Before
EMAIL_BACKEND = "django.core.mail.backends.smtp.EmailBackend"
EMAIL_HOST = "smtp.example.com"
EMAIL_PORT = 587
EMAIL_USE_TLS = True
EMAIL_HOST_USER = "user@example.com"
EMAIL_HOST_PASSWORD = "password"

# After
MAILERS = {
    "default": {
        "BACKEND": "django.core.mail.backends.smtp.EmailBackend",
        "OPTIONS": {
            "host": "smtp.example.com",
            "use_tls": True,  # port 587 is implicit
            "username": "user@example.com",
            "password": "password",
        },
    },
}
```

Map remaining settings as follows: `EMAIL_FILE_PATH` → `file_path`, `EMAIL_USE_SSL` → `use_ssl`, `EMAIL_SSL_CERTFILE` → `ssl_certfile`, `EMAIL_SSL_KEYFILE` → `ssl_keyfile`, and `EMAIL_TIMEOUT` → `timeout`, all inside `OPTIONS`. `use_tls` and `use_ssl` are mutually exclusive.

## Named mailers and APIs

```python
MAILERS["marketing"] = {
    "BACKEND": "django.core.mail.backends.smtp.EmailBackend",
    "OPTIONS": {"host": env("MARKETING_MAIL_HOST"), "use_tls": True},
}

send_mail("Welcome!", "Thanks for signing up.", "hello@example.com", ["user@example.com"], using="marketing")
```

Calls without `using=` use `"default"`. Replace `mail.get_connection()` with `mail.mailers.default`, and replace `connection=`, `auth_user`, and `auth_password` with a named `MAILERS` entry plus `using=`. Do not combine `using` with those arguments or `fail_silently`.

Check dependencies before defining `MAILERS`: packages that read `settings.EMAIL_*` or call `get_connection()` with a backend path are incompatible until updated.

## Anymail

```python
INSTALLED_APPS += ["anymail"]
if not DEBUG:
    MAILERS["default"] = {"BACKEND": "anymail.backends.postmark.EmailBackend"}
ANYMAIL = {"POSTMARK_SERVER_TOKEN": env("POSTMARK_SERVER_TOKEN", default="" if DEBUG else env.NOTSET)}
```

Keep provider credentials in `ANYMAIL`; use `OPTIONS` only for backend-constructor options. Add `path("anymail/", include("anymail.urls"))` and `ANYMAIL["WEBHOOK_SECRET"]` only when webhooks are required.

## Mailpit

In `config/settings/local.py`, replace the inherited console mailer:

```python
MAILERS["default"] = {
    "BACKEND": "django.core.mail.backends.smtp.EmailBackend",
    "OPTIONS": {"host": "localhost", "port": 1025},
}
```

Run a test message with `PYTHONWARNINGS=default uv run manage.py send_test_email you@example.com` to catch remaining deprecated email APIs.
