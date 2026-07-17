FROM busybox:1.37.0-musl

# In-container base path (CapRover mounts the host datalake here).
# Serve root is $DATA_MOUNT/$DIRECTORY.
ENV DATA_MOUNT=/data_mount

# Remap http user to the UID/GID that owns mounted host files (CapRover VMs: usually 1000).
ARG HTTP_UID=1000
ARG HTTP_GID=1000
RUN addgroup -g ${HTTP_GID} http \
  && adduser -D -H -u ${HTTP_UID} -G http http \
  && mkdir -p /data_mount \
  && chown http:http /data_mount

COPY httpd.conf /etc/httpd.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER http

# Non-root cannot bind privileged ports; CapRover Container HTTP Port must be 8080.
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
