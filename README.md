# Django Seedkit 🌱

An agent skill to start new Django projects or extend existing ones. One sentence in, a running project out. It wires packages together, splits dev and prod settings, and adds CI.

```
/django-seedkit SaaS landing + waitlist, GDPR-friendly stack (mail, analytics, error reporting), VPS deploy

/django-seedkit add proper auth — magic link, lockout on brute force, optional 2FA

/django-seedkit look at our repo and tell us what's worth adding next
```

[![View Outputs](https://img.shields.io/badge/View%20Outputs-00C853?style=for-the-badge)](https://github.com/viewflow/seedkit-examples)

LLMs write Django from memory. That memory is a year or two old. Think deprecated auth settings and last version's Stripe webhooks. Or database ports open to the local network.

seedkit keeps that knowledge in [maintained reference files](https://github.com/viewflow/seedkit/tree/main/skills/django-seedkit/references) instead. We build them from package docs, test them end-to-end, and fix every failure back into the file. The model types. That's why scaffolding runs clean on mid-tier Sonnet — your frontier-model hours go to the code only you can write.

Version pins re-resolve at generation time. Nothing goes stale the way an unmaintained starter template does. Nine end-to-end scenarios test the output: generate, boot, smoke-check, audit by a second LLM ([see the outputs](https://github.com/viewflow/seedkit-examples)). The references distill 100+ hours of that generate–boot–fix grind, so you skip it.

It works on the project you already have. Generators only start from zero. `/django-seedkit add [feature]` wires a new package into a live repo: deps, settings, `.env` example, the CI step.

And you get your exact stack, not a preset. A cookiecutter hands you its choices, and you spend day one deleting. Here you pick: Celery or RQ, allauth or magic links, VPS or Fly. You get only the code for the options you picked. The output is a normal Django project you own. No wrapper library, no runtime dependency on seedkit, nothing extra to upgrade later.

<img src=".github/demo.gif" alt="One prompt in, a running Django project out" width="700">

One prompt like the first produces [07-vps-sqlite-saas](https://github.com/viewflow/seedkit-examples/tree/main/07-vps-sqlite-saas): Docker + Caddy deploy, Sentry, Litestream backups, CI.

Helps you with:

- **Setup & config:** [Python deps & venvs](https://docs.astral.sh/uv/), [settings for dev vs prod](https://django-environ.readthedocs.io/), [custom user model](https://docs.djangoproject.com/en/stable/topics/auth/customizing/#substituting-a-custom-user-model).
- **Auth:** [social & password login](https://docs.allauth.org/), [passwordless magic-link login](https://django-mail-auth.readthedocs.io/), [brute-force protection](https://django-axes.readthedocs.io/).
- **APIs:** [typed REST endpoints](https://django-modern-rest.readthedocs.io/), [Rust-powered high-RPS APIs](https://bolt.farhana.li/), [CORS headers](https://github.com/adamchainz/django-cors-headers).
- **Billing:** [Stripe payments & subscriptions](https://dj-stripe.dev/).
- **Async & caching:** [background jobs](https://docs.celeryq.dev/), [scheduled tasks](https://github.com/codingjoe/django-crontask), [async views](https://docs.djangoproject.com/en/stable/topics/async/), [WebSockets](https://channels.readthedocs.io/), [Redis caching](https://github.com/jazzband/django-redis).
- **Storage & email:** [S3 for static & media](https://django-storages.readthedocs.io/), [outbound email](https://anymail.dev/).
- **Frontend & SEO:** [Tailwind without Node](https://django-tailwind-cli.readthedocs.io/), [meta tags & sitemap](https://docs.djangoproject.com/en/stable/ref/contrib/sitemaps/), [translations](https://docs.djangoproject.com/en/stable/topics/i18n/translation/), [GDPR-safe analytics](https://www.goatcounter.com/help/start).
- **Security:** [security headers](https://docs.djangoproject.com/en/stable/topics/security/), [CSP headers](https://django-csp.readthedocs.io/), [production error tracking](https://docs.sentry.io/platforms/python/integrations/django/), [structured logs](https://www.structlog.org/).
- **Code quality:** [pytest & coverage](https://pytest-django.readthedocs.io/), [N+1 query detection](https://github.com/PedroBern/django-zeal), [safe migrations](https://github.com/3YOURMIND/django-migration-linter), [linting & formatting](https://docs.astral.sh/ruff/), [type checking](https://microsoft.github.io/pyright/).
- **Dev experience:** [request profiling](https://github.com/jazzband/django-silk), [auto browser reload](https://github.com/adamchainz/django-browser-reload), [pre-commit hooks](https://pre-commit.com/), [devcontainers](https://containers.dev/).
- **Ops:** [scheduled DB backups](https://django-dbbackup.readthedocs.io/), [Docker for local dev](https://docs.docker.com/compose/), [auto-HTTPS reverse proxy](https://caddyserver.com/docs/), [managed deploys on Fly/Railway/Render](https://fly.io/docs/django/).
- **CI/CD:** [CI pipeline](https://docs.github.com/en/actions), [deploy over SSH](https://github.com/appleboy/ssh-action).

## Does it help? We measured it

Four project specs, each generated twice: once with seedkit, once from the identical prompt with no skill. A separate model then audits every result against the same eight checks — locked dependencies, secrets read from the environment, no usable production `SECRET_KEY` fallback, `DEBUG` off in production, database configurable from env, `.gitignore` covering the env file, README commands matching the shipped manifest, and project layout.

| Generated by | blog | shop | jobs board | media vault | total |
|---|---|---|---|---|---|
| **Sonnet + seedkit** | **8/8** | **8/8** | **8/8** | **8/8** | **32/32** |
| Opus, no skill | 6/8 | 8/8 | 7/8 | 8/8 | 29/32 |
| Fable, no skill | 5/8 | 7/8 | 5/8 | 7/8 | 24/32 |
| Sonnet, no skill | 5/8 | 7/8 | 4/8 | 7/8 | 23/32 |

**Sonnet with seedkit scores above Opus without it.** The knowledge lives in the reference files, so the model doesn't have to supply it.

**The gap is mostly security.** Nine of the twelve unskilled runs shipped a usable production `SECRET_KEY` fallback — a project that quietly boots on a known key when the env var is missing. Every seedkit run raised instead.

**And it costs less rework.** Holding the model fixed, the same prompt took 16 in-flight self-repairs without the skill and 8 with. On the shop scenario, Opus needed 12 repairs to reach the 8/8 that seedkit reached in 2.

One run per cell, four scenarios, Claude models only — enough to show a gap this size, not enough to rank models. [Every generated project and every log is published.](https://github.com/viewflow/seedkit-examples)

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

Now, in whatever empty directory you'd like to populate:

```
/django-seedkit
```

## Project Status

Verification runs on Claude Sonnet today. Other models (Opus, Haiku, GPT, Gemini) and the production deploy targets (VPS, Fly, GitHub-SSH) are wired up but less traveled. Hit something odd there — or anywhere — [open an issue](https://github.com/viewflow/seedkit/issues/new): bug reports go straight into the test loop and come out as fixes.

## Contributing

A person reading the output catches what automated tests can't.

Hit a bug or something odd? [Open an issue](https://github.com/viewflow/seedkit/issues/new). Even a one-line "this broke" helps.

Cross-model coverage is what we need most. We verify on Claude Sonnet, so point `train/run-tests.sh` at Opus, Haiku, GPT, or Gemini and share the logs.

And read the output before you trust it. It boots and passes smoke checks, but hasn't seen production. Your review is part of the loop.

For anything bigger, open an issue first so we can talk it through. Full test cycles take a couple hours, so it's worth saving each other the wasted run.

## License

[MIT](./LICENSE), © 2026 Mikhail Podgurskiy.

<br>

---
<sub><i>$ Sorry, you're right. I shouldn't have deleted the production database.<br>&nbsp;&nbsp;&nbsp;Want me to at least write the restore script?</i></sub>
