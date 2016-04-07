FROM elixir:1.2

RUN apt-get update && apt-get install -y git

RUN mix local.rebar
RUN mix local.hex --force

ADD . /app
WORKDIR /app

RUN mix do deps.get, deps.compile
