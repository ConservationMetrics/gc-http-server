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

HTTP_ROOT="$SERVE_PATH"

if [ -n "${DATA_DIRECTORY:-}" ]; then
  case "$DATA_DIRECTORY" in
    .|/*|*..*)
      echo "error: DATA_DIRECTORY must be a non-root relative path without '..' (got: $DATA_DIRECTORY)" >&2
      exit 1
      ;;
  esac

  DATA_PATH="${DATA_MOUNT}/${DATA_DIRECTORY}"
  if [ ! -d "$DATA_PATH" ]; then
    echo "error: data path does not exist or is not a directory: $DATA_PATH" >&2
    exit 1
  fi

  if [ -e "$SERVE_PATH/data" ] || [ -L "$SERVE_PATH/data" ]; then
    echo "error: app directory already contains the reserved path: $SERVE_PATH/data" >&2
    exit 1
  fi

  HTTP_ROOT="/tmp/gc-http-server-root"
  rm -rf "$HTTP_ROOT"
  mkdir -p "$HTTP_ROOT"
  find "$SERVE_PATH" -mindepth 1 -maxdepth 1 -exec ln -s {} "$HTTP_ROOT/" \;
  ln -s "$DATA_PATH" "$HTTP_ROOT/data"
fi

exec httpd -f -p 8080 -h "$HTTP_ROOT" -c /etc/httpd.conf
