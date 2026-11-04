package engage

import (
	"reflect"
	"testing"
)

func TestAttributionFromFullURL(t *testing.T) {
	url := "https://shop.example/landing?utm_source=google&utm_medium=cpc&utm_campaign=fall+sale" +
		"&utm_term=shoes&utm_content=ad%201&utm_id=42&gclid=g1&fbclid=f1&msclkid=m1&other=x"
	want := map[string]string{
		"utm_source":   "google",
		"utm_medium":   "cpc",
		"utm_campaign": "fall sale",
		"utm_term":     "shoes",
		"utm_content":  "ad 1",
		"utm_id":       "42",
		"gclid":        "g1",
		"fbclid":       "f1",
		"msclkid":      "m1",
	}
	if got := AttributionFromURL(url); !reflect.DeepEqual(got, want) {
		t.Errorf("got %v", got)
	}
}

func TestAttributionFromQueryForms(t *testing.T) {
	want := map[string]string{"utm_source": "news", "gclid": "abc"}
	for _, in := range []string{
		"?utm_source=news&gclid=abc",
		"utm_source=news&gclid=abc",
		"/landing?utm_source=news&gclid=abc#top",
		"https://x.example/?gclid=abc&utm_source=news",
	} {
		if got := AttributionFromURL(in); !reflect.DeepEqual(got, want) {
			t.Errorf("%q: got %v", in, got)
		}
	}
}

func TestAttributionEmpty(t *testing.T) {
	for _, in := range []string{"", "https://x.example/", "https://x.example/#/r?utm_source=a", "?utm_source=&foo=1"} {
		if got := AttributionFromURL(in); got == nil || len(got) != 0 {
			t.Errorf("%q: got %v", in, got)
		}
	}
}

func TestAttributionFirstValueWins(t *testing.T) {
	got := AttributionFromURL("?utm_source=a&utm_source=b")
	if !reflect.DeepEqual(got, map[string]string{"utm_source": "a"}) {
		t.Errorf("got %v", got)
	}
}
