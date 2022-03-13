FROM hexpm/elixir:1.13.3-erlang-24.3-alpine-3.15.0 as builder

RUN apk update && apk --no-cache --update add tzdata build-base git openssh \
   && cp /usr/share/zoneinfo/Europe/Amsterdam /etc/localtime

ENV MIX_ENV=prod

WORKDIR /opt/app

RUN mix local.rebar --force &&\
    mix local.hex --force

# Cache elixir deps
COPY ./mix.* ./
RUN mix deps.get --only prod
COPY ./config ./config
RUN mix deps.compile

COPY ./lib ./lib

RUN mix release --path=/opt/release

FROM alpine:3.15

ENV SQLITE_PATH=/data/albagen.sqlite

WORKDIR /opt/app

COPY --from=builder /etc/localtime /etc/localtime
COPY --from=builder /opt/release .

RUN apk update && apk --no-cache --update add ncurses-libs openssl util-linux sqlite libstdc++ unixodbc lksctp-tools \
    && mkdir /data \
    && touch /data/albagen.sqlite

ENV USER=root

CMD ["ash", "-c", "./bin/albagen start"]
