// The Lowco API quickstart with the Go SDK: a UPI QR code, then a GST
// invoice extracted as a job and waited for. Run with LOWCO_API_KEY set to a
// test key (lc_test_…) and invoice.pdf in the working directory.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"strings"

	api "github.com/lowcoai/lowco-sdk/go/api"
)

func main() {
	ctx := context.Background()
	client, err := api.NewClient(api.Config{}) // reads LOWCO_API_KEY
	if err != nil {
		log.Fatal(err)
	}

	// 1. A UPI payment QR code, as the PNG itself
	qr, err := client.QR.Generate(ctx, api.QrGenerateParams{
		Type: api.String("upi"), Pa: api.String("acme@okhdfcbank"), Pn: api.String("Acme Traders"),
		Am: api.String("1499.00"), Tn: api.String("INV-2026-0042"),
	}, api.WithAccept("image/png"))
	if err != nil {
		fail(err)
	}
	if err := os.WriteFile("qr.png", qr.Bytes, 0o644); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("qr.png written (%d bytes)\n", len(qr.Bytes))

	// 2. A GST invoice, submitted as a job and waited for
	answer, err := client.DocAI.Invoice(ctx, api.DocaiInvoiceParams{File: api.FilePath("invoice.pdf")}, api.WithMode("async"))
	if err != nil {
		fail(err)
	}
	fmt.Printf("job %s\n", answer.Job.Status)
	invoice, err := answer.Result(ctx)
	if err != nil {
		fail(err)
	}
	for _, f := range []struct {
		name  string
		field api.Field
	}{{"invoice_number", invoice.InvoiceNumber}, {"seller_gstin", invoice.Seller.GSTIN}, {"total", invoice.Total}} {
		v, _ := json.Marshal(f.field.Value) // numbers as the API sent them
		fmt.Printf("%s: %s (confidence %v)\n", f.name, strings.Trim(string(v), `"`), f.field.Confidence)
	}
}

func fail(err error) {
	var e *api.Error
	if errors.As(err, &e) {
		log.Fatalf("%s: %s (%s, request %s)", e.Reason, e.Message, e.DocURL, e.RequestID)
	}
	log.Fatal(err)
}
