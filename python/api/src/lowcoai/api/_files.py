from __future__ import annotations

import mimetypes
import os
from dataclasses import dataclass
from typing import IO, Any, Dict, Optional, Tuple

__all__ = ["FileRef", "Files"]


@dataclass(frozen=True)
class FileRef:
    """One file input. Local inputs (path, bytes, stream) are sent as multipart
    parts; remote ones (url, id, base64) by reference."""

    kind: str
    value: Any
    filename: Optional[str] = None
    mime_type: Optional[str] = None
    password: Optional[str] = None

    @property
    def is_local(self) -> bool:
        return self.kind in ("path", "bytes", "stream")

    def read(self) -> Tuple[str, str, bytes]:
        if self.kind == "path":
            with open(self.value, "rb") as f:
                data = f.read()
            name = self.filename or os.path.basename(self.value)
        elif self.kind == "bytes":
            data, name = bytes(self.value), self.filename or "file"
        elif self.kind == "stream":
            data = self.value.read()
            name = self.filename or os.path.basename(getattr(self.value, "name", "") or "file")
        else:
            raise ValueError(f"a {self.kind} input is not local")
        mime = self.mime_type or mimetypes.guess_type(name)[0] or "application/octet-stream"
        return name, mime, data

    def reference(self) -> Dict[str, Any]:
        if self.kind == "url":
            out: Dict[str, Any] = {"file_url": self.value}
        elif self.kind == "id":
            out = {"file_id": self.value}
        elif self.kind == "base64":
            out = {"file_base64": self.value}
            if self.filename:
                out["filename"] = self.filename
        else:
            raise ValueError(f"a {self.kind} input must be uploaded")
        if self.password:
            out["password"] = self.password
        return out


class Files:
    """Builders for file inputs."""

    @staticmethod
    def path(path: "str | os.PathLike[str]", *, filename: Optional[str] = None, mime_type: Optional[str] = None,
             password: Optional[str] = None) -> FileRef:
        """A local file by path (read when the call is made)."""
        return FileRef("path", os.fspath(path), filename, mime_type, password)

    @staticmethod
    def bytes(data: "bytes | bytearray | memoryview", *, filename: Optional[str] = None, mime_type: Optional[str] = None,
              password: Optional[str] = None) -> FileRef:
        """Bytes in memory."""
        return FileRef("bytes", bytes(data), filename, mime_type, password)

    @staticmethod
    def stream(stream: IO[bytes], *, filename: Optional[str] = None, mime_type: Optional[str] = None,
               password: Optional[str] = None) -> FileRef:
        """A binary file object, read to the end when the call is made."""
        return FileRef("stream", stream, filename, mime_type, password)

    @staticmethod
    def url(url: str, *, password: Optional[str] = None) -> FileRef:
        """A public https URL the API fetches (file_url)."""
        return FileRef("url", url, password=password)

    @staticmethod
    def id(file_id: str, *, password: Optional[str] = None) -> FileRef:
        """A stored file (file_id from files.upload or an earlier output)."""
        return FileRef("id", file_id, password=password)

    @staticmethod
    def base64(data: str, *, filename: Optional[str] = None, password: Optional[str] = None) -> FileRef:
        """Base64 or a data: URL (up to 5 MB decoded)."""
        return FileRef("base64", data, filename, password=password)
