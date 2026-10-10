"""lowcoai-api against an in-process mock of the Lowco API (stdlib only:
python -m unittest discover -s tests)."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from lowcoai.api import (  # noqa: E402
    ERROR_REASONS, Files, LowcoApi, LowcoApiError, LowcoJobError, LowcoTimeoutError, construct_event,
    new_idempotency_key, verify_signature,
)

PNG = bytes.fromhex("89504e470d0a1a0a0000000d49484452")
SEEN: list = []
STATE = {"polls": 0, "settings": 0}


def env(data):
    return json.dumps({"status": 1, "data": data}).encode()


def job(job_id, status, **extra):
    j = {"job_id": job_id, "service": "docai", "operation": "invoice", "status": status, "progress": None, "input": {},
         "result": None, "error": None, "usage": None, "attempts": 1, "created_at": "2026-10-09T09:30:00Z",
         "started_at": None, "finished_at": None, "expires_at": "2026-10-16T09:30:00Z",
         "links": {"self": f"/v1/jobs/{job_id}", "cancel": f"/v1/jobs/{job_id}/cancel"}}
    j.update(extra)
    return j


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # quiet
        pass

    def send(self, status, body, ctype="application/json", headers=None):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("X-Request-Id", "req_test")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def handle_any(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        SEEN.append({"method": self.command, "path": u.path, "query": q, "headers": dict(self.headers), "body": body})
        if self.headers.get("Authorization") != "Bearer lc_test_sdk" and not u.path.startswith("/v1/downloads/"):
            return self.send(401, json.dumps({"status": 0, "error": {"code": 401, "reason": "missing_key", "message": "No key", "doc_url": "x"}}).encode())
        key = f"{self.command} {u.path}"
        if key == "POST /v1/qr/generate":
            if self.headers.get("Accept") == "image/png":
                return self.send(200, PNG, "image/png")
            return self.send(200, env({"format": "png", "width": 512}), headers={"X-Lowco-Credits-Used": "0.0500"})
        if key == "POST /v1/docai/invoice":
            if q.get("mode") == "async":
                return self.send(202, env(job("job_inv", "queued")), headers={"Retry-After": "0"})
            return self.send(200, env({"invoice_number": {"value": "INV-1", "confidence": 0.98, "source": {"page": 1}}}))
        if key == "GET /v1/jobs/job_inv":
            STATE["polls"] += 1
            if STATE["polls"] < 3:
                return self.send(200, env(job("job_inv", "processing")), headers={"Retry-After": "0"})
            return self.send(200, env(job("job_inv", "succeeded", result={"invoice_number": {"value": "INV-1", "confidence": 0.98, "source": {"page": 1}}})))
        if key == "GET /v1/jobs/job_bad":
            return self.send(200, env(job("job_bad", "failed", error={"code": 422, "reason": "file_corrupt", "message": "The file is not a readable PDF.", "doc_url": "x"})))
        if key == "GET /v1/jobs/job_slow":
            return self.send(200, env(job("job_slow", "processing")), headers={"Retry-After": "0"})
        if key == "GET /v1/jobs":
            if not q.get("cursor"):
                return self.send(200, env({"items": [job("j1", "succeeded"), job("j2", "succeeded")], "next_cursor": "c2"}))
            return self.send(200, env({"items": [job("j3", "failed")], "next_cursor": None}))
        if key == "POST /v1/files":
            return self.send(201, env({"file_id": "file_uploaded"}))
        if key == "POST /v1/pdf/merge":
            return self.send(200, env({"pages": 2, "files_merged": 2, "file": {"file_id": "file_m", "url": None}}))
        if key == "POST /v1/pdf/rotate":
            return self.send(400, json.dumps({"status": 0, "error": {"code": 400, "reason": "invalid_param", "message": "angle must be 90, 180 or 270.", "param": "angle", "request_id": "req_err", "doc_url": "https://docs.lowco.ai/api/errors#invalid_param"}}).encode())
        if key == "POST /v1/ocr/text":
            return self.send(202, env(job("job_ocr", "queued")), headers={"Idempotent-Replayed": "true"})
        if key == "GET /v1/settings":
            STATE["settings"] += 1
            if STATE["settings"] == 1:
                return self.send(429, json.dumps({"status": 0, "error": {"code": 429, "reason": "rate_limited", "message": "Slow down", "doc_url": "x"}}).encode(), headers={"Retry-After": "0"})
            return self.send(200, env({"environment": "test"}))
        if key == "GET /v1/usage":
            return self.send(200, env({"from": q.get("from"), "to": q.get("to")}))
        if key == "GET /v1/files/file_x/content":
            self.send_response(307)
            self.send_header("Location", BASE + "/v1/downloads/tok_x")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None
        if key == "GET /v1/downloads/tok_x":
            return self.send(200, b"%PDF-1.7", "application/pdf")
        return self.send(404, json.dumps({"status": 0, "error": {"code": 404, "reason": "route_not_found", "message": "no", "doc_url": "x"}}).encode())

    do_GET = do_POST = do_PATCH = do_DELETE = handle_any


SERVER = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
BASE = f"http://127.0.0.1:{SERVER.server_address[1]}"
threading.Thread(target=SERVER.serve_forever, daemon=True).start()


def client():
    return LowcoApi("lc_test_sdk", base_url=BASE)


def last(path):
    return [s for s in SEEN if s["path"] == path][-1]


class ApiTest(unittest.TestCase):
    def test_inline_answer(self):
        a = client().qr.generate(type="upi", pa="acme@okhdfcbank", pn="Acme", am="1499.00")
        self.assertEqual(a.status, 200)
        self.assertEqual(a.data["width"], 512)
        self.assertEqual(a.request_id, "req_test")
        self.assertEqual(a.credits_used, "0.0500")
        sent = last("/v1/qr/generate")
        self.assertEqual(json.loads(sent["body"]), {"type": "upi", "pa": "acme@okhdfcbank", "pn": "Acme", "am": "1499.00"})
        self.assertTrue(sent["headers"]["X-Client-User-Agent"].startswith("lowcoai-api-python/"))

    def test_accept_returns_bytes(self):
        a = client().qr.generate(content="x", accept="image/png")
        self.assertEqual(a.bytes, PNG)
        self.assertEqual(a.content_type, "image/png")

    def test_multipart_then_wait(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "invoice.pdf"
            p.write_bytes(b"%PDF-1.7 test")
            lowco = client()
            a = lowco.docai.invoice(file=Files.path(p), languages=["eng", "hin"], mode="async")
        self.assertEqual(a.status, 202)
        self.assertEqual(a.job["job_id"], "job_inv")
        sent = last("/v1/docai/invoice")
        self.assertTrue(sent["headers"]["Content-Type"].startswith("multipart/form-data"))
        text = sent["body"].decode()
        self.assertIn('name="file"; filename="invoice.pdf"', text)
        self.assertIn("%PDF-1.7 test", text)
        self.assertIn('name="options"\r\n\r\n{"languages": ["eng", "hin"]}', text)
        self.assertEqual(sent["query"]["mode"], "async")
        result = lowco.wait_for_result(a)
        self.assertEqual(result["invoice_number"]["value"], "INV-1")
        self.assertEqual(STATE["polls"], 3)

    def test_references_and_mixed_inputs(self):
        client().pdf.merge(files=[Files.id("file_a"), Files.url("https://example.com/b.pdf")], bookmarks=True)
        self.assertEqual(json.loads(last("/v1/pdf/merge")["body"]), {"bookmarks": True, "files": [{"file_id": "file_a"}, {"file_url": "https://example.com/b.pdf"}]})
        client().pdf.merge(files=[Files.id("file_a"), b"%PD"])
        self.assertTrue(last("/v1/files")["headers"]["Content-Type"].startswith("multipart/form-data"))
        self.assertEqual(json.loads(last("/v1/pdf/merge")["body"]), {"files": [{"file_id": "file_a"}, {"file_id": "file_uploaded"}]})

    def test_typed_error(self):
        with self.assertRaises(LowcoApiError) as cm:
            client().pdf.rotate(file=Files.id("file_a"), angle=45)
        e = cm.exception
        self.assertEqual((e.status, e.reason, e.param, e.request_id), (400, "invalid_param", "angle", "req_err"))
        self.assertEqual(e.doc_url, "https://docs.lowco.ai/api/errors#invalid_param")
        self.assertEqual(ERROR_REASONS["invalid_param"]["status"], 400)
        self.assertEqual(len(ERROR_REASONS), 56)

    def test_idempotency_key(self):
        key = new_idempotency_key()
        a = client().ocr.text(file=Files.id("file_a"), idempotency_key=key, mode="async")
        self.assertEqual(last("/v1/ocr/text")["headers"]["Idempotency-Key"], key)
        self.assertTrue(a.replayed)

    def test_get_retries_429(self):
        self.assertEqual(client().settings.get()["environment"], "test")
        self.assertEqual(STATE["settings"], 2)

    def test_keyword_wire_names(self):
        u = client().usage.get(from_="2026-10-01", to="2026-10-10")
        self.assertEqual(u, {"from": "2026-10-01", "to": "2026-10-10"})

    def test_list_all(self):
        ids = [j["job_id"] for j in client().jobs.list_all(status="succeeded")]
        self.assertEqual(ids, ["j1", "j2", "j3"])
        self.assertEqual(last("/v1/jobs")["query"]["cursor"], "c2")

    def test_failed_and_slow_jobs(self):
        with self.assertRaises(LowcoJobError) as cm:
            client().jobs.wait("job_bad")
        self.assertEqual(cm.exception.reason, "file_corrupt")
        self.assertEqual(cm.exception.job["status"], "failed")
        with self.assertRaises(LowcoTimeoutError):
            client().jobs.wait("job_slow", timeout=0.05)

    def test_content_url_and_download(self):
        lowco = client()
        link = lowco.files.content_url("file_x")
        self.assertEqual(link, BASE + "/v1/downloads/tok_x")
        self.assertEqual(lowco.files.download(link), b"%PDF-1.7")
        self.assertNotIn("Authorization", last("/v1/downloads/tok_x")["headers"])

    def test_missing_key(self):
        saved = os.environ.pop("LOWCO_API_KEY", None)
        try:
            with self.assertRaises(LowcoApiError) as cm:
                LowcoApi()
            self.assertEqual(cm.exception.reason, "missing_key")
            os.environ["LOWCO_API_KEY"] = "lc_test_sdk"
            os.environ["LOWCO_API_BASE_URL"] = BASE
            self.assertEqual(LowcoApi().settings.get()["environment"], "test")
        finally:
            os.environ.pop("LOWCO_API_BASE_URL", None)
            if saved is None:
                os.environ.pop("LOWCO_API_KEY", None)
            else:
                os.environ["LOWCO_API_KEY"] = saved


class WebhookTest(unittest.TestCase):
    def test_vectors_from_lowco_api(self):
        vectors = json.loads((Path(__file__).resolve().parents[3] / "specs" / "webhook-signature-vectors.json").read_text())["vectors"]
        self.assertEqual(len(vectors), 8)
        for v in vectors:
            self.assertEqual(verify_signature(v["header"], v["body"], v["secret"], now=v["now"]), v["valid"], v["name"])
            self.assertEqual(verify_signature(v["header"], v["body"].encode(), v["secret"], now=v["now"]), v["valid"], v["name"])
        ok = vectors[0]
        self.assertEqual(construct_event(ok["body"], ok["header"], ok["secret"], now=ok["now"])["type"], "job.succeeded")


if __name__ == "__main__":
    unittest.main()
