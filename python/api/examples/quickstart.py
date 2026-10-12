"""The Lowco API quickstart with lowcoai-api: a UPI QR code, then a GST
invoice extracted as a job and waited for. Run with LOWCO_API_KEY set to a
test key (lc_test_…) and invoice.pdf in the working directory."""

import sys

from lowcoai.api import Files, LowcoApi, LowcoApiError

lowco = LowcoApi()  # reads LOWCO_API_KEY

try:
    # 1. A UPI payment QR code, as the PNG itself
    qr = lowco.qr.generate(type="upi", pa="acme@okhdfcbank", pn="Acme Traders", am="1499.00",
                           tn="INV-2026-0042", accept="image/png")
    with open("qr.png", "wb") as f:
        f.write(qr.bytes)
    print(f"qr.png written ({len(qr.bytes)} bytes)")

    # 2. A GST invoice, submitted as a job and waited for
    answer = lowco.docai.invoice(file=Files.path("invoice.pdf"), mode="async")
    print(f"job {answer.job['status']}")
    invoice = lowco.wait_for_result(answer)
    for name, f in {"invoice_number": invoice["invoice_number"], "seller_gstin": invoice["seller"]["gstin"],
                    "total": invoice["total"]}.items():
        print(f"{name}: {f['value']} (confidence {f['confidence']})")
except LowcoApiError as e:
    print(f"{e.reason}: {e.message} ({e.doc_url}, request {e.request_id})", file=sys.stderr)
    sys.exit(1)
