package api

import (
	"context"
	"net/http"
	"net/url"
)

// Pager walks a list route page after page, following next_cursor:
//
//	p := client.Jobs.ListAll(ctx, &api.JobsListQuery{Status: api.String("failed")})
//	for p.Next(ctx) {
//		job := p.Item()
//	}
//	if err := p.Err(); err != nil { … }
type Pager[T any] struct {
	c      *core
	path   string
	query  url.Values
	opts   []Option
	items  []T
	i      int
	cursor *string
	done   bool
	err    error
	cur    T
}

func newPager[T any](c *core, path string, q url.Values, opts []Option) *Pager[T] {
	if q == nil {
		q = url.Values{}
	}
	q.Del("cursor")
	return &Pager[T]{c: c, path: path, query: q, opts: opts, i: -1}
}

// Next advances to the next item, fetching the next page when needed.
func (p *Pager[T]) Next(ctx context.Context) bool {
	if p.err != nil {
		return false
	}
	p.i++
	for p.i >= len(p.items) {
		if p.done {
			return false
		}
		q := url.Values{}
		for k, v := range p.query {
			q[k] = v
		}
		if p.cursor != nil {
			q.Set("cursor", *p.cursor)
		}
		var page struct {
			Items      []T     `json:"items"`
			NextCursor *string `json:"next_cursor"`
		}
		if err := p.c.call(ctx, http.MethodGet, p.path, q, nil, &page, p.opts); err != nil {
			p.err = err
			return false
		}
		p.items, p.i = page.Items, 0
		p.cursor = page.NextCursor
		p.done = page.NextCursor == nil || *page.NextCursor == ""
		if len(p.items) == 0 && p.done {
			return false
		}
	}
	p.cur = p.items[p.i]
	return true
}

// Item is the current item.
func (p *Pager[T]) Item() T { return p.cur }

// Err is the error that stopped the walk, if any.
func (p *Pager[T]) Err() error { return p.err }

// All collects every remaining item.
func (p *Pager[T]) All(ctx context.Context) ([]T, error) {
	var out []T
	for p.Next(ctx) {
		out = append(out, p.Item())
	}
	return out, p.Err()
}
