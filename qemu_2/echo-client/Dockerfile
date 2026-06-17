FROM alpine:3.23

RUN apk add --no-cache curl socat

COPY echo-client.sh /usr/local/bin/echo-client
RUN chmod 0755 /usr/local/bin/echo-client

ENTRYPOINT ["/usr/local/bin/echo-client"]
