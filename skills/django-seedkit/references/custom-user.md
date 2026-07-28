# Custom User Model

Docs: <https://docs.djangoproject.com/en/stable/topics/auth/customizing/#substituting-a-custom-user-model>

Set `AUTH_USER_MODEL` **before the first `migrate`**. Adding it later requires data migrations and breaks foreign keys to `auth.User`.

An empty subclass suffices — extending it later (extra fields, email-as-username) doesn't require schema changes to existing rows.

## Create the app

```sh
uv run django-admin startapp users
```

For a nested layout: `mkdir -p apps/users && uv run django-admin startapp users apps/users` and adjust the dotted reference.

## users/models.py

Username-based login — plain `AbstractUser`:

```python
from django.contrib.auth.models import AbstractUser


class User(AbstractUser):
    pass
```

Email-only login (allauth with `ACCOUNT_LOGIN_METHODS = {"email"}`, or `django-mail-auth`) — drop `username`, make `email` unique, switch `USERNAME_FIELD`, and ship a manager that creates users by email:

```python
from typing import TYPE_CHECKING

from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models
from django.db.models.functions import Lower

if TYPE_CHECKING:
    from typing import ClassVar


class UserManager(BaseUserManager["User"]):
    use_in_migrations = True

    def _create_user(self, email: str, password: str | None, **extra_fields):
        if not email:
            raise ValueError("Email is required")
        email = self.normalize_email(email).lower()  # Foo@x and foo@x are the same account
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, email: str, password: str | None = None, **extra_fields):
        extra_fields.setdefault("is_staff", False)
        extra_fields.setdefault("is_superuser", False)
        return self._create_user(email, password, **extra_fields)

    def create_superuser(self, email: str, password: str | None = None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        if extra_fields.get("is_staff") is not True:
            raise ValueError("Superuser must have is_staff=True.")
        if extra_fields.get("is_superuser") is not True:
            raise ValueError("Superuser must have is_superuser=True.")
        return self._create_user(email, password, **extra_fields)


class User(AbstractUser):
    username = None  # type: ignore[assignment]
    email = models.EmailField(unique=True)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS: "ClassVar[list[str]]" = []

    objects: "ClassVar[UserManager]" = UserManager()

    class Meta:
        constraints = [
            # DB-level backstop for paths that bypass the manager (admin, shell).
            models.UniqueConstraint(Lower("email"), name="user_email_ci_unique"),
        ]
```

## users/admin.py

Plain variant — default `UserAdmin` works:

```python
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import User

admin.site.register(User, UserAdmin)
```

Email-only variant — override add/change forms; default `UserCreationForm` expects a `username` field that no longer exists:

```python
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.forms import (
    ReadOnlyPasswordHashField,
    UserChangeForm,
    UserCreationForm,
)

from .models import User


class UserCreationFormEmail(UserCreationForm):
    class Meta(UserCreationForm.Meta):
        model = User
        fields = ("email",)


class UserChangeFormEmail(UserChangeForm):
    class Meta(UserChangeForm.Meta):
        model = User
        # Parent pins {"username": UsernameField, "password": ReadOnlyPasswordHashField}.
        # Drop username (the model has no such field) but KEEP the password mapping.
        # ReadOnlyPasswordHashField is what shows the hash + "change password" link
        # in admin. Without it the password field is editable plain text and saving
        # the user form silently overwrites user.password with whatever was typed,
        # breaking login.
        field_classes = {"password": ReadOnlyPasswordHashField}


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    add_form = UserCreationFormEmail
    form = UserChangeFormEmail
    list_display = ("email", "is_staff", "is_superuser")
    ordering = ("email",)
    search_fields = ("email",)
    readonly_fields = ("last_login", "date_joined")
    fieldsets = (
        (None, {"fields": ("email", "password")}),
        ("Permissions", {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")}),
        ("Important dates", {"fields": ("last_login", "date_joined")}),
    )
    add_fieldsets = (
        (None, {"classes": ("wide",), "fields": ("email", "password1", "password2", "is_active", "is_staff", "is_superuser")}),
    )
```

`add_fieldsets` includes the permission flags so admin can create a superuser in one round-trip; without them, every new user starts as a regular user and a second edit pass is needed to grant `is_staff` / `is_superuser`.

## Settings

```python
INSTALLED_APPS = [
    ...
    "users",
]

AUTH_USER_MODEL = "users.User"
```

## Migrate

`startapp` does not generate a migration for the new `User` model. Run
`makemigrations users` immediately, then `migrate`:

```sh
uv run manage.py makemigrations users
uv run manage.py migrate
uv run manage.py createsuperuser
```

Without the explicit `makemigrations`, the next `migrate` fails with
`Dependency on app with no migrations: users`. The `users_user` table
replaces `auth_user`.
