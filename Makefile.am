ACLOCAL_AMFLAGS = -I m4
SUBDIRS = src

# Keep non-source runtime assets and test tooling in release tarballs.
EXTRA_DIST = \
	README \
	README.markdown \
	docker/Dockerfile \
	docker/README.md \
	docker/dims.conf \
	docs/perf-baseline.md \
	examples/dims.conf \
	tests/config-smoke.sh \
	tests/hardening-integration.sh \
	tests/hardening_fixture_server.py \
	tests/perf-smoke.sh \
	.github/workflows/ci.yml

TEST_IMAGE_TAG = mod-dims:make-check
TEST_REQUESTS = 60
TEST_P95_LIMIT_MS = 400

.PHONY: check-local qa-smoke dev-build dev-check sanitize-build sanitize-check

# Wire make check to the project smoke/integration suites.
check-local: qa-smoke

qa-smoke:
	./tests/config-smoke.sh
	IMAGE_TAG="$(TEST_IMAGE_TAG)" ./tests/hardening-integration.sh
	IMAGE_TAG="$(TEST_IMAGE_TAG)" SKIP_BUILD=true REQUESTS="$(TEST_REQUESTS)" P95_LIMIT_MS="$(TEST_P95_LIMIT_MS)" ./tests/perf-smoke.sh

# Developer build profiles.
dev-build:
	./autorun.sh --enable-dev-warnings
	$(MAKE) -j$$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)

dev-check: dev-build
	$(MAKE) check

sanitize-build:
	./autorun.sh --enable-dev-warnings --enable-sanitizers
	$(MAKE) -j$$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)

sanitize-check: sanitize-build
	$(MAKE) check
