# Django application development

Use this when extending or reviewing an existing Django app: models and migrations, URLs and views, forms, templates, admin, query performance, or tests. First follow the inventory in `existing-project.md`; preserve the installed Django version, test runner, settings layout, URL style, and project conventions. Do not introduce a package or restructure settings merely to follow this guide.

## Data model and migrations

- Point relations to the configured user model with `settings.AUTH_USER_MODEL`; never import Django's concrete `User` model.
- Use `TextChoices` or `IntegerChoices` for stable finite states. Use `DecimalField`, not `FloatField`, for money. `blank=True` controls form validation; `null=True` controls database storage and is usually unnecessary for text fields.
- Put invariants that must survive every write path in database constraints. Add indexes only for demonstrated query shapes; name explicit constraints and indexes so migrations stay stable.
- Choose `on_delete` for the domain, not by habit: `PROTECT`/`RESTRICT` for records that must not disappear, `SET_NULL` only on a nullable relation, and `CASCADE` only when deletion really owns the child.
- Create and inspect migrations before applying them. For a mature or production-backed table, flag locking, backfills, table rewrites, and non-null additions before running the migration.

## URLs, views, and forms

- Give each app URLconf an `app_name` and name every pattern. Use `reverse()`/`reverse_lazy()` and `{% url %}` rather than literal URLs.
- Scope every object and queryset to the requesting user's permissions before lookup. `get_object_or_404(scoped_queryset, ...)` is safer than fetching globally and checking permission later.
- Do not change state in a GET request. After a successful POST, redirect. Use Django forms for user input; `ModelForm.Meta.fields` must be explicit, never `"__all__"`.
- Limit a `ModelChoiceField` or form queryset to objects the current user may select. Validate cross-field rules in `clean()` and use `cleaned_data` after `is_valid()`.
- Use async views only when awaited I/O makes them worthwhile. Do not call synchronous ORM code directly from an async view; follow the project's Django-version-appropriate async ORM or adapter pattern.

## Templates and admin

- Extend the project base template, include `{% csrf_token %}` in every POST form, and rely on Django autoescaping. Never use `safe` or `mark_safe()` for user-controlled content.
- Register useful admin surfaces with a `ModelAdmin`: explicit `list_display`, appropriate filters and search fields, and `autocomplete_fields` for large related tables. A bare registration is acceptable only for a genuinely trivial internal model.
- Optimise admin and list views when they display relations: use explicit `select_related()` for foreign keys and `prefetch_related()` for collections. Avoid broad calls with no field names.

## Tests and completion checks

Test the behaviour changed, including permission boundaries and invalid form input—not just the happy path. Use the runner already configured by the project. Add a focused query-count test where a new list/admin view renders related objects.

After code that changes models, settings, templates, or URLs, run the narrowest relevant checks, then the existing suite when feasible:

```sh
uv run manage.py makemigrations --check --dry-run
uv run manage.py check
# then the project's configured test command
```

For production-setting changes, also run `uv run manage.py check --deploy` with the project's production settings and required safe placeholder environment. Read `references/ci.md` for the existing CI contract instead of adding a second workflow.
