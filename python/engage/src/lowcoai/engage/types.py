"""Wire types for the lowco engage track API.

Every type is a ``TypedDict`` whose keys match the JSON the browser SDK
(``@lowcoai/engage``) sends, so events built here are byte-for-byte the same
shape. Fields are optional unless marked ``Required``.
"""

from typing import Any

from typing_extensions import Required, TypedDict

__all__ = [
    "BrowserInfo",
    "CPUInfo",
    "DeviceHardwareInfo",
    "DeviceInfo",
    "EngineInfo",
    "Event",
    "Identify",
    "LocationInfo",
    "Metadata",
    "OSInfo",
]

Metadata = dict[str, Any]
"""Free-form event properties (``event_data``)."""


class BrowserInfo(TypedDict, total=False):
    name: str
    version: str
    major: str


class OSInfo(TypedDict, total=False):
    name: str
    version: str


class DeviceHardwareInfo(TypedDict, total=False):
    model: str
    type: str
    vendor: str


class CPUInfo(TypedDict, total=False):
    architecture: str


class EngineInfo(TypedDict, total=False):
    name: str
    version: str


class DeviceInfo(TypedDict, total=False):
    """Client device description (the ``ua-parser-js`` result in the browser SDK)."""

    browser: BrowserInfo
    os: OSInfo
    device: DeviceHardwareInfo
    cpu: CPUInfo
    engine: EngineInfo
    ua: str


class LocationInfo(TypedDict, total=False):
    """Location of the client, with the keys the engage ingest model reads.

    Like the rest of the event payload the keys are snake_case: the server reads
    ``altitude_accuracy`` (not the browser's camelCase ``altitudeAccuracy``).
    ``ip_address`` is the field a server usually knows.
    """

    latitude: float
    longitude: float
    accuracy: float
    altitude: float | None
    altitude_accuracy: float | None
    heading: float | None
    speed: float | None
    ip_address: str


class Event(TypedDict, total=False):
    """One tracked event as sent to ``POST /v1/engage/track``.

    ``event_time`` is an ISO-8601 UTC string with milliseconds and a ``Z``
    suffix (JavaScript ``Date.toISOString``). Keys whose value would be
    ``None`` are omitted.
    """

    id: str
    event_name: Required[str]
    event_data: Metadata
    user_id: str
    device_id: Required[str]
    session_id: str
    device_info: DeviceInfo
    location: LocationInfo
    event_time: Required[str]


class Identify(TypedDict, total=False):
    user_id: Required[str]
    user_data: Required[Metadata]
