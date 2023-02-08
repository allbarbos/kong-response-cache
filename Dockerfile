FROM kong:latest
USER root
RUN apk add --no-cache --upgrade && apk add unzip make gcc musl-dev libc-dev lua-dev
COPY /kong-declarative-config.yaml /tmp/kong-declarative-config.yaml
WORKDIR /custom-plugins

COPY . ./kong-plugin-response-cache
RUN cd ./kong-plugin-response-cache \
    && luarocks build

USER kong
