FROM scratch
COPY rootfs/ /
ENV LD_LIBRARY_PATH=/usr/local/lib
WORKDIR /var/lib/symphony-api
ENTRYPOINT ["/usr/local/bin/symphony-api", "--config", "/etc/symphony-api.json"]
