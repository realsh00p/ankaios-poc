FROM alpine:3.23

RUN apk add --no-cache util-linux

COPY systemd-unit-workload.sh /usr/local/bin/systemd-unit-workload
RUN chmod 0755 /usr/local/bin/systemd-unit-workload

ENTRYPOINT ["/usr/local/bin/systemd-unit-workload"]
