# Real-time — django-channels

Docs: <https://channels.readthedocs.io/> · <https://github.com/django/channels-redis>

WebSockets, long-lived connections, server-pushed events. Picked at Foundation §2.4 = `asgi+channels`. Read `references/async.md` first — the ASGI server choice and Dockerfile `CMD` apply equally here.

`django-channels` activity has slowed; prefer stock ASGI views (`references/async.md`) when you only need async request handling. Reach for channels when the project genuinely needs WebSockets or out-of-band channel-layer broadcasts.

## Install

```sh
uv add channels 'channels-redis' daphne
```

`daphne` isn't pulled in transitively by `channels`; install it explicitly so the `INSTALLED_APPS` entry resolves. `channels-redis` is the production-grade channel-layer backend. The in-memory layer is fine for a single dev process but doesn't span workers, so any scale or separate ASGI worker breaks broadcast.

## Settings

```python
# base.py
INSTALLED_APPS = [
    "daphne",  # not used as the server, but ships management commands and lifecycle hooks channels relies on
    "django.contrib.contenttypes",
    "django.contrib.auth",
    # ...
    "channels",
]

ASGI_APPLICATION = "config.asgi.application"

# Reuse the REDIS_URL line from references/redis.md if it's already in settings.
REDIS_URL = env("REDIS_URL", default="redis://127.0.0.1:6379").rstrip("/")

CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels_redis.core.RedisChannelLayer",
        # /4 — the channel layer's slot in the Redis DB map (references/conventions.md).
        "CONFIG": {"hosts": [f"{REDIS_URL}/4"]},
    },
}
```

Dev fallback (in-memory) lives in `local.py` only when Redis isn't running locally:

```python
# local.py
CHANNEL_LAYERS = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}
```

## ASGI app

```python
# config/asgi.py
import os

import django
from channels.auth import AuthMiddlewareStack
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.security.websocket import AllowedHostsOriginValidator
from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.production")
django.setup()

django_asgi_app = get_asgi_application()

from config.routing import websocket_urlpatterns  # noqa: E402  imported after django.setup()

application = ProtocolTypeRouter({
    "http": django_asgi_app,
    "websocket": AllowedHostsOriginValidator(
        AuthMiddlewareStack(URLRouter(websocket_urlpatterns))
    ),
})
```

`AllowedHostsOriginValidator` rejects WS handshakes whose `Origin` isn't in `ALLOWED_HOSTS`. `AuthMiddlewareStack` populates `scope["user"]` from the session cookie so consumers can authorise per-user.

## Routing + consumer

```python
# config/routing.py
from django.urls import path
from chat.consumers import ChatConsumer

websocket_urlpatterns = [
    path("ws/chat/<str:room>/", ChatConsumer.as_asgi()),  # type: ignore[arg-type]
]
# django-stubs has no model for ASGI views in `path()`; the type: ignore keeps pyright clean.
```

```python
# chat/consumers.py
from channels.generic.websocket import AsyncJsonWebsocketConsumer

class ChatConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        self.room = self.scope["url_route"]["kwargs"]["room"]
        self.group = f"chat-{self.room}"
        if self.scope["user"].is_anonymous:
            await self.close(code=4401)
            return
        await self.channel_layer.group_add(self.group, self.channel_name)
        await self.accept()

    async def disconnect(self, code):
        await self.channel_layer.group_discard(self.group, self.channel_name)

    async def receive_json(self, content, **kwargs):
        await self.channel_layer.group_send(
            self.group,
            {"type": "chat.message", "text": content["text"], "user": self.scope["user"].username},
        )

    async def chat_message(self, event):
        await self.send_json({"text": event["text"], "user": event["user"]})
```

## Local — host

`DJANGO_SETTINGS_MODULE=config.settings.local uv run uvicorn config.asgi:application --reload` on the host serves HTTP and WS through the same loop — `config/asgi.py` defaults to `production` settings, so the dev run overrides it explicitly. `manage.py runserver` won't upgrade WebSockets — use uvicorn directly when testing channels. Make sure `redis` from `references/redis.md` is running.

## Production — separate ASGI worker

In dev, one process handles both. In production, run a **dedicated ASGI worker pool** alongside the regular `web` so long-lived WebSocket connections don't starve HTTP request workers. Same image, different `CMD`:

```yaml
# docker-compose.prod.yml
services:
  web:
    # ... existing web definition (HTTP gunicorn) ...
    command: gunicorn -k uvicorn_worker.UvicornWorker config.asgi:application --bind 0.0.0.0:8000

  ws:
    image: ghcr.io/{owner}/{project_slug}:latest
    restart: unless-stopped
    command: gunicorn -k uvicorn_worker.UvicornWorker config.asgi:application --bind 0.0.0.0:8001 --workers ${WS_CONCURRENCY:-2}
    env_file: .env.prod
    logging: *logging
    depends_on:
      redis:
        condition: service_healthy
```

`web` keeps low concurrency tuned for HTTP; `ws` runs higher concurrency since each WebSocket holds a socket open. The Caddyfile proxies the two upstreams by path:

```caddyfile
example.com {
    @ws path /ws/*
    reverse_proxy @ws ws:8001
    reverse_proxy web:8000
}
```

Caddy upgrades WS connections automatically — no `Connection: Upgrade` block needed.

## Scale + sticky sessions

WebSocket sessions are stateful (the connection lives in one worker's memory). When scaling `ws` horizontally:

- Channel-layer broadcasts (`group_send`) cross processes — that's what `channels-redis` is for. Same-room messages reach every connected client regardless of which worker holds them.
- A single client's connection still lives in one worker. Reconnect after a deploy lands them on a new worker; in-flight state needs to be in Redis or the DB, not in instance attributes on the consumer.
- Load balancers don't need sticky sessions for HTTP, but WebSocket upgrade requests go to one worker and stay there for the connection's lifetime — that's normal, not a config knob.

## Idle-connection limits

Caddy's default `read_timeout` is 60s. WS connections that idle longer get dropped. Either:
- Bump `read_timeout` for the WS upstream block (`reverse_proxy @ws ws:8001 { transport http { read_timeout 0 } }`), or
- Send application-level pings every ~30s from the consumer (`await self.send_json({"type": "ping"})`).

The ping path is more robust — proxies in front of Caddy (Cloudflare, AWS ALB) have their own idle timeouts you can't always control.

## Tests

```python
import pytest
from channels.routing import URLRouter
from channels.testing import WebsocketCommunicator
from config.routing import websocket_urlpatterns

@pytest.mark.asyncio
async def test_chat_round_trip(authenticated_user):
    # Wrap URLRouter directly, not the AuthMiddlewareStack-wrapped `application` —
    # AuthMiddlewareStack would overwrite scope["user"] from the session at connect.
    communicator = WebsocketCommunicator(
        URLRouter(websocket_urlpatterns),
        "/ws/chat/lobby/",
        headers=[(b"origin", b"http://testserver")],
    )
    communicator.scope["user"] = authenticated_user
    connected, _ = await communicator.connect()
    assert connected
    await communicator.send_json_to({"text": "hi"})
    msg = await communicator.receive_json_from()
    assert msg["text"] == "hi"
    await communicator.disconnect()
```

`WebsocketCommunicator` bypasses the network — useful for consumer logic. For end-to-end (Caddy + ws upstream + Redis layer), a Playwright test against a real `docker compose up` stack is the only honest check.

## Pitfalls

- `daphne` in `INSTALLED_APPS` is needed even when uvicorn is the actual server — channels uses daphne's app config for management commands and signal hooks.
- `AsyncJsonWebsocketConsumer` requires JSON-serialisable payloads. Pass model instances through a serializer first.
- The channel layer is fire-and-forget — `group_send` doesn't error if no one's listening. Don't rely on it for must-deliver messages; use the DB + a notification consumer.
- Don't read `request.session` directly inside an async consumer — go through `database_sync_to_async`. `AuthMiddlewareStack` handles the session resolution at connect time.
- `AllowedHostsOriginValidator` requires an `Origin` header. Browsers always send one; the Python `websockets` client does not by default — pass `origin='http://localhost'` (or matching `ALLOWED_HOSTS` entry) in smoke tests. Keep the validator unconditional in `config/asgi.py`.
