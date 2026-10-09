// The Lowco API quickstart with @lowcoai/api: a UPI QR code, then a GST
// invoice extracted as a job and waited for. Run with LOWCO_API_KEY set to a
// test key (lc_test_…) and invoice.pdf in the working directory.
import { writeFile } from "node:fs/promises";
import { Files, LowcoApi, LowcoApiError } from "@lowcoai/api";

const lowco = new LowcoApi(); // reads LOWCO_API_KEY

try {
  // 1. A UPI payment QR code, as the PNG itself
  const qr = await lowco.qr.generate(
    { type: "upi", pa: "acme@okhdfcbank", pn: "Acme Traders", am: "1499.00", tn: "INV-2026-0042" },
    { accept: "image/png" },
  );
  await writeFile("qr.png", qr.bytes);
  console.log(`qr.png written (${qr.bytes.length} bytes)`);

  // 2. A GST invoice, submitted as a job and waited for
  const answer = await lowco.docai.invoice({ file: Files.path("invoice.pdf") }, { mode: "async" });
  console.log(`job ${answer.job.status}`);
  const invoice = await lowco.waitForResult(answer);
  for (const [name, f] of Object.entries({ invoice_number: invoice.invoice_number, seller_gstin: invoice.seller.gstin, total: invoice.total })) {
    console.log(`${name}: ${f.value} (confidence ${f.confidence})`);
  }
} catch (err) {
  if (err instanceof LowcoApiError) {
    console.error(`${err.reason}: ${err.message} (${err.docUrl}, request ${err.requestId})`);
    process.exit(1);
  }
  throw err;
}
