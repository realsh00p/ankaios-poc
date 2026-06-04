FROM alpine:3.23

RUN apk add --no-cache jq util-linux

COPY rollback-workload.sh /usr/local/bin/rollback-workload
RUN chmod 0755 /usr/local/bin/rollback-workload

ENTRYPOINT ["/usr/local/bin/rollback-workload"]
