# Django Seedkit 🌱

**An agent skill to start new Django projects, or extend the one you already have.**

Scaffold a Django project the way you need it. Current Django knowledge and best practices for coding agents: tell the agent what you must build — it asks a few questions, then writes the project. Packages wired together, dev and prod settings split, CI in place.

[![Site](https://img.shields.io/badge/site-django--seedkit.viewflow.io-0C4B33?style=for-the-badge)](https://django-seedkit.viewflow.io)
[![View Outputs](https://img.shields.io/badge/View%20Outputs-00C853?style=for-the-badge)](https://github.com/viewflow/seedkit-examples)
[![License MIT](https://img.shields.io/badge/license-MIT-44B78B?style=for-the-badge)](./LICENSE)

```
/django-seedkit SaaS landing + waitlist, GDPR-friendly stack (mail, analytics, errors), VPS deploy

/django-seedkit add proper auth — magic link, lockout on brute force, optional 2FA

/django-seedkit look at our repo and tell us what's worth adding next
```

<img src=".github/demo.gif" alt="One prompt in, a running Django project out" width="700">

The first prompt produces [07-vps-sqlite-saas](https://github.com/viewflow/seedkit-examples/tree/main/07-vps-sqlite-saas): a Docker and [Caddy](https://caddyserver.com/docs/) deploy, [Sentry](https://docs.sentry.io/platforms/python/integrations/django/), Litestream backups, CI.

## Sonnet with the skill scores above Fable and Opus without it

Nine projects, generated more than once and audited by a second model against the same eight security and configuration checks. With the skill: **72 of 72**. Without it, a quarter of the checks failed. [Full numbers below.](#does-it-help-we-measured-it)

The knowledge lives in [maintained reference files](https://github.com/viewflow/seedkit/tree/main/skills/django-seedkit/references), so the model doesn't have to supply it. That's why scaffolding runs clean on mid-tier Sonnet — your frontier-model hours go to the code only you can write.

## Install

### Claude Code (plugin)

```sh
/plugin marketplace add viewflow/seedkit
/plugin install seedkit@viewflow
```

### Other agents (Cursor, Codex, OpenCode, Gemini CLI, …)

Via the [skills](https://github.com/vercel-labs/skills) CLI, which installs into whichever agent dirs it detects:

```sh
npx skills add viewflow/seedkit            # project scope
npx skills add viewflow/seedkit -g         # global (all your projects)
npx skills add viewflow/seedkit -a cursor  # pin to one agent
```

Then, in whatever empty directory you'd like to populate:

```
/django-seedkit
```

## What you can pick

More than 50 Django packages, and most topics offer more than one option — [one reference file per topic](https://github.com/viewflow/seedkit/tree/main/skills/django-seedkit/references), and only the files your answers select get written.

- **Setup & config:** [Python deps & venvs](https://docs.astral.sh/uv/), [settings for dev vs prod](https://django-environ.readthedocs.io/), [custom user model](https://docs.djangoproject.com/en/stable/topics/auth/customizing/#substituting-a-custom-user-model).
- **Auth:** [social & password login](https://docs.allauth.org/), [passwordless magic-link login](https://django-mail-auth.readthedocs.io/), [brute-force protection](https://django-axes.readthedocs.io/), [two-factor](https://django-otp-official.readthedocs.io/).
- **APIs:** [typed REST endpoints](https://django-modern-rest.readthedocs.io/), [Rust-powered high-RPS APIs](https://bolt.farhana.li/), [CORS headers](https://github.com/adamchainz/django-cors-headers).
- **Billing:** [Stripe payments & subscriptions](https://dj-stripe.dev/).
- **Async & caching:** [background jobs](https://docs.celeryq.dev/), [an RQ queue](https://github.com/rq/django-rq), [a database-backed queue](https://docs.djangoproject.com/en/stable/topics/tasks/), [scheduled tasks](https://github.com/codingjoe/django-crontask), [async views](https://docs.djangoproject.com/en/stable/topics/async/), [WebSockets](https://channels.readthedocs.io/), [Redis caching](https://github.com/jazzband/django-redis).
- **Storage & email:** [S3 for static & media](https://django-storages.readthedocs.io/), [WhiteNoise](https://whitenoise.readthedocs.io/), [outbound email](https://anymail.dev/).
- **Frontend & SEO:** [Tailwind without Node](https://django-tailwind-cli.readthedocs.io/), [meta tags & sitemap](https://docs.djangoproject.com/en/stable/ref/contrib/sitemaps/), [robots.txt](https://django-robots.readthedocs.io/), [translations](https://docs.djangoproject.com/en/stable/topics/i18n/translation/), [GDPR-safe analytics](https://www.goatcounter.com/help/start).
- **Security:** [security headers](https://docs.djangoproject.com/en/stable/topics/security/), [CSP headers](https://docs.djangoproject.com/en/6.1/howto/csp/), [error tracking](https://docs.sentry.io/platforms/python/integrations/django/), [structured logs](https://www.structlog.org/).
- **Code quality:** [pytest & coverage](https://pytest-django.readthedocs.io/), [N+1 query detection](https://github.com/taobojlen/django-zeal), [safe migrations](https://github.com/3YOURMIND/django-migration-linter), [linting & formatting](https://docs.astral.sh/ruff/), [type checking](https://microsoft.github.io/pyright/).
- **Dev experience:** [request profiling](https://github.com/jazzband/django-silk), [auto browser reload](https://github.com/adamchainz/django-browser-reload), [pre-commit hooks](https://pre-commit.com/), [devcontainers](https://containers.dev/).
- **Ops:** [scheduled DB backups](https://django-dbbackup.readthedocs.io/), [Docker for local dev](https://docs.docker.com/compose/), [auto-HTTPS reverse proxy](https://caddyserver.com/docs/), [managed deploys on Fly/Railway/Render](https://fly.io/docs/django/).
- **CI/CD:** [CI pipeline](https://docs.github.com/en/actions), [deploy over SSH](https://github.com/appleboy/ssh-action).

## Why a skill and not a prompt

A model writes Django from memory, and that memory is a year or two old. So it writes an auth setting Django deprecated, or last version's Stripe webhook. Or it opens the database port to the local network.

You can correct all that in your prompt — if you already know the answers. Seedkit already knows them, and it is that prompt, written and tested:

- **A [reference file](https://github.com/viewflow/seedkit/tree/main/skills/django-seedkit/references) keeps only the part of the package docs the model doesn't know.** Today's setting names, today's package names.
- **You don't have to know what to ask for.** Which package locks an account after failed logins? Which settings does a production deploy need? The files have the answer, and the skill offers it.
- **More than 100 hours of tests found what the model gets wrong.** Each file goes into a generated project. We start the project, read the result, then correct or drop what failed.
- **Version pins re-resolve at generation time.** Nothing goes stale the way an unmaintained starter template does.

## A cookiecutter alternative for coding agents

A cookiecutter hands you its choices, and you spend day one deleting. Here you pick: Celery or RQ, allauth or magic links, VPS or Fly. You get only the code for the options you picked.

The output is a normal Django project you own. No wrapper library, no runtime dependency on seedkit, nothing extra to upgrade later.

And it works on the project you already have — generators only start from zero. `/django-seedkit add [feature]` wires a new package into a live repo: deps, settings, `.env` example, the CI step.

## Does it help? We measured it

Nine project specs, each generated more than once: with seedkit, and from the identical prompt with no skill. A separate model then audits every result against the same eight checks — locked dependencies, secrets read from the environment, no usable production `SECRET_KEY` fallback, `DEBUG` off in production, database configurable from env, `.gitignore` covering the env file, README commands matching the shipped manifest, and project layout.

| Case | Sonnet + seedkit | Fable, no skill |
|---|---|---|
| [01-blog](https://github.com/viewflow/seedkit-examples/tree/main/01-minimal-blog) | **8/8** | 5/8 |
| [02-shop](https://github.com/viewflow/seedkit-examples/tree/main/02-shop) | **8/8** | 7/8 |
| [03-jobs-board](https://github.com/viewflow/seedkit-examples/tree/main/03-jobs-board) | **8/8** | 5/8 |
| [04-media-vault](https://github.com/viewflow/seedkit-examples/tree/main/04-media-vault) | **8/8** | 7/8 |
| [05-mailer](https://github.com/viewflow/seedkit-examples/tree/main/05-orbit-demo) | **8/8** | 3/8 |
| [06-crm](https://github.com/viewflow/seedkit-examples/tree/main/06-silk-lab) | **8/8** | 6/8 |
| [07-saas](https://github.com/viewflow/seedkit-examples/tree/main/07-vps-sqlite-saas) | **8/8** | 7/8 |
| [08-startup](https://github.com/viewflow/seedkit-examples/tree/main/08-fly-app) | **8/8** | 7/8 |
| [09-internal-ops](https://github.com/viewflow/seedkit-examples/tree/main/09-ssh-deploy) | **8/8** | 7/8 |
| **total** | **72/72** | **54/72** |

The other two control arms cover part of the set: Sonnet with no skill scored 33/48 on six cases, Opus with no skill 29/32 on four.

**Sonnet with seedkit scores above Opus without it.** On the four cases Opus ran, it reached 29/32 where seedkit reached 32/32.

**The gap is mostly security.** Nine of the twelve control runs on the first four cases shipped a usable production `SECRET_KEY` fallback. Such a project boots on a known key when the env var is missing. Every seedkit run raised instead.

**And it costs less rework.** Holding the model fixed on those same four cases, the prompts took 16 in-flight self-repairs without the skill and 8 with. On the shop scenario, Opus needed 12 repairs to reach the 8/8 that seedkit reached in 2.

One run per cell, Claude models only — enough to show a gap this size, not enough to rank models. [Every generated project is published, both arms.](https://github.com/viewflow/seedkit-examples)

## Project status

Verification runs on Claude Sonnet today. Other models ([Opus](https://docs.claude.com/en/docs/about-claude/models), Haiku, GPT, Gemini) and the deploy targets (VPS, [Fly](https://fly.io/docs/django/), GitHub-SSH) are wired up but less traveled. Hit something odd there — or anywhere — [open an issue](https://github.com/viewflow/seedkit/issues/new): bug reports go straight into the test loop and come out as fixes.

Recent changes are in the [CHANGELOG](./CHANGELOG.md).

## Contributing

A person reading the output catches what automated tests can't.

Hit a bug or something odd? [Open an issue](https://github.com/viewflow/seedkit/issues/new). Even a one-line "this broke" helps.

Cross-model coverage is what we need most. We verify on Claude Sonnet, so point [`train/run-tests.sh`](https://github.com/viewflow/seedkit-examples/blob/main/train/run-tests.sh) at Opus, Haiku, GPT, or Gemini and share the logs.

Your review is part of the loop: what you report goes into a [reference file](https://github.com/viewflow/seedkit/tree/main/skills/django-seedkit/references) and every later run gets it.

For anything bigger, open an issue first so we can talk it through. Full test cycles take a couple hours, so it's worth saving each other the wasted run.

## License

[MIT](./LICENSE), © 2026 Mikhail Podgurskiy.

<br>

---
<sub><i>$ Sorry, you're right. I shouldn't have deleted the production database.<br>&nbsp;&nbsp;&nbsp;Want me to at least write the restore script?</i></sub>
