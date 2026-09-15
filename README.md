# Hier Baut Berlin

A tool to visualize and inform citizens of Berlin about governmental decisions.

[![Build Status](https://github.com/hierbautberlin/website/actions/workflows/elixir.yml/badge.svg?branch=main)](https://github.com/HierBautBerlin/website/actions/workflows/elixir.yml)

**You want to help?** Awesome. Scroll through the issues, open a new one, or just send
a short notice to [mail@hierbautberlin.de](mailto:mail@hierbautberlin.de). We are happy about every person who wants to help.

## Development setup

HierBautBerlin uses Elixir and Phoenix. Information on how
to install Elixir can be found [here](http://elixir-lang.org/install.html).

As database it uses [PostgreSQL](http://postgresql.org) with the PostGIS extension.
If you don't want to install PostGIS locally, you can run it in a container:

```bash
podman run -d --name hierbautberlin-db -e POSTGRES_PASSWORD=postgres -p 5434:5432 docker.io/postgis/postgis:17-3.5
export DATABASE_PORT=5434
```

The importers need `qpdf`, `pdftotext` (poppler-utils) and `dumppdf.py` (`pip install pdfminer.six`).
Assets are built with esbuild and dart-sass (installed by mix), JavaScript
dependencies are installed with `npm` (Node.js 22+). Common tasks are run with
[just](https://just.systems) (`just` lists all recipes).

After you installed everything, the setup is as follows:

```bash
just update
just setup
just start
```

The app runs on http://localhost:4000, sent emails show up in http://localhost:4000/dev/mailbox.

Before you contribute code, please make sure to read the [CONTRIBUTING.md](CONTRIBUTING.md)

## How to run the test suite

```bash
just check
```

You can also run the `ExUnit` tests in watch mode with:

```bash
just run-tests
```

## Import geo objects

The text analysis (finding streets, addresses and places in news) and the map
need the streets, street numbers and places of Berlin. They are imported from
OpenStreetMap (streets, addresses, parks) and from [gdi.berlin.de](https://gdi.berlin.de)
(LOR planning areas, schools):

```bash
just import-geo
```

It downloads the OSM extract of Berlin (~100 MB) and needs `ogr2ogr` (Debian:
`gdal-bin`). A full import takes about a minute. Running it again updates the
data; ids and links to news items are kept. In the Docker container use
`bin/import_geo_objects.sh --release`.

After the address matching or the geo data changed, the links of existing news
can be updated. Without `--apply` it only shows what would change:

```bash
just reanalyze BERLIN_AMTSBLATT
just reanalyze BERLIN_PRESSE --since 2026-01-01 --apply
```

The list next to the map is sorted by relevance (see
`lib/hierbautberlin/geo_data/relevance.ex`). After changing those rules, calculate
it again for all news items with `mix geo.relevance`.

## Working with a production dump

```bash
just restore-dump dump.sql hierbautberlin_prod   # creates the database
export DATABASE_NAME=hierbautberlin_prod
mix ecto.migrate
mix geo.relevance
just import-geo
just start
```

Copy the production file storage into `file_storage/` to see the Amtsblatt PDFs.

## Deployment

The app runs as Docker image built from the `Dockerfile` (e.g. with Coolify). The
container runs the web server and the importers, so run only one instance. The
migrations run on every start.

It needs Postgres with PostGIS and these environment variables:

| Variable | |
|---|---|
| `DATABASE_URL` | required, e.g. `ecto://user:password@host/database` |
| `SECRET_KEY_BASE` | required, `mix phx.gen.secret` |
| `PHX_HOST` | the domain, default `hierbautberlin.de` |
| `MAILGUN_API`, `MAILGUN_DOMAIN` | sending emails |
| `BUGSNAG_API` | optional, error reporting |
| `PLAUSIBLE_SCRIPT_ID` | optional, empty disables the visitor statistics |
| `POOL_SIZE`, `PORT` | optional, default `10` and `4000` |

The Amtsblatt PDFs, the import folder and the OSM download are stored in
`/app/data`, mount a volume there.

## Funding

This project is funded by the [German Federal Ministry of Education and Research](http://bmbf.de)
and is part of the 9th batch of the [prototype fund](http://prototypefund.de).

![Logo of the German Federal Ministry of Education and Research](images/support-bmbf.png)
![Prototype Fund Logo](images/support-prototype.png)
