from __future__ import annotations

import uuid
from collections.abc import Mapping
from typing import Any
from urllib.parse import urlencode

WS_URL = "wss://ws.lowco.ai/"
"""The fixed flux endpoint every client connects to."""


def generate_client_id() -> str:
    """A fresh random client id (a UUID4 string)."""
    return str(uuid.uuid4())


def build_websocket_url(
    token: str,
    org_id: str,
    client_id: str,
    query_params: Mapping[str, str] | None = None,
) -> str:
    """The connection URL: ``token``, ``orgId`` and ``cli`` query parameters,
    then ``query_params`` (a key that is already present is replaced in place).

    ``FluxClient`` adds ``replay=1`` on top of this; this helper does not.
    """
    params: dict[str, str] = {"token": token, "orgId": org_id, "cli": client_id}
    if query_params:
        params.update(query_params)
    return f"{WS_URL}?{urlencode(params)}"


def normalize_topic(value: Any) -> str:
    """A trimmed topic / event name; anything that is not a string is ``""``."""
    return value.strip() if isinstance(value, str) else ""
