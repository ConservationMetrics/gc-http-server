#!/bin/sh
set -eu

DATA_MOUNT="${DATA_MOUNT:-/data_mount}"

if [ -z "${DIRECTORY:-}" ]; then
  echo "error: DIRECTORY is required" >&2
  exit 1
fi

case "$DIRECTORY" in
  /*|*..*)
    echo "error: DIRECTORY must be a relative path without '..' (got: $DIRECTORY)" >&2
    exit 1
    ;;
esac

SERVE_PATH="${DATA_MOUNT}/${DIRECTORY}"

if [ ! -d "$SERVE_PATH" ]; then
  echo "error: serve path does not exist or is not a directory: $SERVE_PATH" >&2
  echo "hint: mount the host datalake at $DATA_MOUNT, then set DIRECTORY to a folder under it" >&2
  exit 1
fi

exec httpd -f -p 8080 -h "$SERVE_PATH" -c /etc/httpd.conf
