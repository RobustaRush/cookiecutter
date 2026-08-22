# Django feature review

Use this after the inventory in `existing-project.md` when implementing or reviewing a requested feature. Preserve the project's installed Django version, conventions, and configured test runner. This is a risk check, not a second Django tutorial or a reason to add packages or restructure settings.

## Failure-prone boundaries

- **Authorization:** scope every object lookup and form choice to what the requesting user may access. A global `get_object_or_404(Model, pk=...)` followed by a later permission check can expose an object's existence or data. A `ModelChoiceField` must likewise be restricted to permitted objects.
- **HTTP semantics:** never mutate data from a GET request. Validate POST input through a form with an explicit field allowlist, then redirect on success; do not accept `fields = "__all__"` for a public form.
- **Relations:** use `settings.AUTH_USER_MODEL` for new user relations, rather than importing the concrete `User` class. This avoids breaking projects that selected a custom user model before their first migration.
- **Async:** in an `async def` view, use the project's async ORM pattern or an adapter for synchronous work. A direct synchronous ORM call raises `SynchronousOnlyOperation`.
- **Rendered collections:** if a view or admin list reads related objects inside a loop, select or prefetch those explicit relations and add a query-count test when the path is material.
- **Migrations:** inspect data migrations and schema changes on established tables before applying them; call out destructive operations, table rewrites, non-null additions, and locks rather than treating them as routine.

## Completion evidence

Add tests for changed permission boundaries and invalid input. For model changes, run `uv run manage.py makemigrations --check --dry-run`; then run the project's configured checks and test command. Existing CI guidance, including production checks, remains in `references/ci.md`.
