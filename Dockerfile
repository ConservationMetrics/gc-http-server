FROM quay.io/oauth2-proxy/oauth2-proxy:v7.15.5 AS oauth2-proxy

FROM busybox:1.37.0-musl

# In-container base path (CapRover mounts the host datalake here).
# DIRECTORY is the app root; optional DATA_DIRECTORY is exposed at /data/.
# AUTH_ENABLED defaults to false in entrypoint.sh.
ENV DATA_MOUNT=/data_mount \
    DATA_DIRECTORY="" \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Remap http user to the UID/GID that owns mounted host files (CapRover VMs: usually 1000).
ARG HTTP_UID=1000
ARG HTTP_GID=1000
RUN addgroup -g ${HTTP_GID} http \
  && adduser -D -H -u ${HTTP_UID} -G http http \
  && mkdir -p /data_mount /etc/ssl/certs \
  && chown http:http /data_mount

# Static oauth2-proxy binary and the CA bundle from its distroless image.
COPY --from=oauth2-proxy /bin/oauth2-proxy /bin/oauth2-proxy
COPY --from=oauth2-proxy /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

COPY httpd.conf /etc/httpd.conf
COPY mime.types /etc/mime.types
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER http

# Non-root cannot bind privileged ports; CapRover Container HTTP Port must be 8080.
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
