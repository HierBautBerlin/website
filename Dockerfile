# Production image, e.g. for Coolify. See docs/deployment.md.
#
#   docker build --build-arg SOURCE_COMMIT=$(git rev-parse HEAD) -t hierbautberlin .

ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=28.3.3
ARG DEBIAN_VERSION=trixie-20260824-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"
ARG NODE_IMAGE="node:22-trixie-slim"

# --- build ---------------------------------------------------------------------
FROM ${NODE_IMAGE} AS node

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Node 22 like the CI (.github/workflows/elixir.yml). Debian only has node 20,
# and its npm 9 aborts `npm ci` when the version of a file: dependency
# (deps/phoenix*) in package-lock.json is not the one in deps/, while newer npm
# versions install it anyway.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"
# The commit becomes part of the release version (Coolify passes it automatically)
ARG SOURCE_COMMIT=""
ENV SOURCE_COMMIT=${SOURCE_COMMIT}

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY assets/package.json assets/package-lock.json assets/
RUN npm ci --prefix assets

COPY priv priv
COPY lib lib
COPY assets assets
RUN mix assets.setup && mix assets.deploy

RUN mix compile
COPY config/runtime.exs config/
COPY rel rel
RUN mix release --overwrite

# --- run -----------------------------------------------------------------------
FROM ${RUNNER_IMAGE}

# qpdf, pdftotext (poppler-utils) and dumppdf.py (pdfminer) for the Amtsblatt
# importer, ogr2ogr (gdal-bin) for the OSM import, curl for the healthcheck and
# bin/import_geo_objects.sh
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    libstdc++6 openssl libncurses6 locales ca-certificates tini curl \
    qpdf poppler-utils python3-pdfminer gdal-bin \
  && rm -rf /var/lib/apt/lists/* \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen \
  && if ! command -v dumppdf.py >/dev/null; then ln -s "$(command -v dumppdf)" /usr/local/bin/dumppdf.py; fi

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    MIX_ENV=prod \
    PORT=4000 \
    HIERBAUT_STORAGE_PATH=/app/data/file_storage \
    HIERBAUT_IMPORT_PATH=/app/data/import \
    DATA_DIR=/app/data/osm \
    RELEASE_DIR=/app

WORKDIR /app

RUN useradd --create-home --uid 1000 app \
  && mkdir -p /app/data/file_storage /app/data/import/amtsblatt /app/data/osm \
  && chown -R app:app /app

COPY --from=builder --chown=app:app /app/_build/prod/rel/hierbautberlin ./
COPY --chown=app:app bin/import_geo_objects.sh ./bin/import_geo_objects.sh

USER app

# file storage (Amtsblatt PDFs), import folder and the OSM download
VOLUME /app/data

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl --fail --silent http://localhost:4000/ping || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/bin/server"]
