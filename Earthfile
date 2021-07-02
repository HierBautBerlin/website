FROM hexpm/elixir:1.12.2-erlang-23.3.1-debian-stretch-20210326

all:
    BUILD +build

build:
    ARG APP_NAME=hierbautberlin
    ARG APP_VERSION=0.1.0
    ARG MIX_ENV=prod
    RUN apt-get update
    RUN apt-get install nodejs build-essential git curl -y
    RUN curl -fsSL https://deb.nodesource.com/setup_14.x | bash -
    RUN apt-get update
    RUN apt-get install nodejs -y
    RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
    WORKDIR /src/
    COPY --dir .git config lib priv assets ./
    COPY mix.exs .
    COPY mix.lock .
    RUN mix local.hex --force
    RUN mix local.rebar --force
    RUN export PATH="$HOME/.cargo/bin:$PATH" && mix do deps.get --only prod
    RUN export PATH="$HOME/.cargo/bin:$PATH" && mix deps.compile
    RUN curl -o- -L https://yarnpkg.com/install.sh | bash
    RUN export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH" && cd assets && yarn install && yarn run deploy
    RUN RUSTLER_NIF_VERSION=2.15 mix phx.digest
    RUN RUSTLER_NIF_VERSION=2.15 mix release
    SAVE ARTIFACT _build/${MIX_ENV}/${APP_NAME}-1.0.0+${APP_VERSION}.tar.gz AS LOCAL build/${APP_NAME}-${APP_VERSION}.tar.gz

