# Lowco API SDKs (docs/api.md). The other products are built per package.

LOWCO_API ?= ../lowco-api
APIGEN := cd tools/apigen && go run .

.PHONY: api-gen api-check api-compat api-sync api-test

# Generate the four SDK sources from specs/lowco-api.json.
api-gen:
	$(APIGEN) -root ../.. -spec ../../specs/lowco-api.json

# Fail when the generated sources are stale.
api-check:
	$(APIGEN) -root ../.. -spec ../../specs/lowco-api.json -check

# Breaking changes from the vendored document to lowco-api's current one.
api-compat:
	$(APIGEN) -compat ../../specs/lowco-api.json $(abspath $(LOWCO_API))/services/api/docs/swagger.json

# Take lowco-api's current document (after the gate) and regenerate.
api-sync: api-compat
	cp $(LOWCO_API)/services/api/docs/swagger.json specs/lowco-api.json
	$(MAKE) api-gen

# Every SDK's tests (npm needs its devDependencies installed).
api-test:
	cd tools/apigen && go test -count=1 ./...
	cd go/api && go vet ./... && go test -count=1 ./...
	cd npm/api && npm test
	cd python/api && python3 -m unittest discover -s tests
	cd flutter/api && dart analyze && dart test
