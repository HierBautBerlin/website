VERSION = $(shell git rev-parse HEAD)

start:
		mix phx.server

setup:
		mix ecto.setup

run-tests:
		mix test.watch --stale

check:
		mix check

i18n:
		mix gettext.extract
		mix gettext.merge priv/gettext

update:
		mix deps.get
		(cd assets && yarn install)

prod-build:
		echo Building $(VERSION)
		earthly --build-arg APP_VERSION=$(VERSION) +build
