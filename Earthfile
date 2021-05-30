FROM elixir:1.11.3

all:
    BUILD +build

build:
    ARG APP_NAME=hierbautberlin
    ARG APP_VERSION=0.1.0
    ARG MIX_ENV=prod
    RUN curl -fsSL https://deb.nodesource.com/setup_14.x | bash -
    RUN apt-get update
    RUN apt-get install nodejs build-essential -y
    WORKDIR /src/
    COPY --dir config lib priv assets ./
    COPY mix.exs .
    COPY mix.lock .
    RUN mix local.hex --force
    RUN mix local.rebar --force
    RUN mix do deps.get --only prod
    RUN curl -o- -L https://yarnpkg.com/install.sh | bash
    RUN export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH" && cd assets && yarn install && yarn run deploy
    RUN mix phx.digest
    RUN mix release
    SAVE ARTIFACT _build/${MIX_ENV}/${APP_NAME}-${APP_VERSION}.tar.gz AS LOCAL build/${APP_NAME}-${APP_VERSION}.tar.gz

