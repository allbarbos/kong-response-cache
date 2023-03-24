FROM kong:latest
USER root
COPY /kong-declarative-config.yaml /tmp/kong-declarative-config.yaml
WORKDIR /custom-plugins
COPY . ./kong-plugin-response-cache
RUN cd ./kong-plugin-response-cache \
    && luarocks build
USER kong
