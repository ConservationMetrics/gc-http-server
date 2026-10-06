# gc-http-server: minimal static HTTP server

A lightweight HTTP server for serving static content directly from the Guardian Connector data lake (or any mounted volume).

This service runs a minimal BusyBox `httpd` web server and is intended to expose files stored within the Guardian Connector data lake over HTTP. It is particularly useful for hosting custom HTML, JavaScript, CSS, images, or other static assets that interact with data already managed by Guardian Connector.

## How it works

By default, the container mounts the Guardian Connector data lake and serves files directly from it.

The service supports the following environment variables:

| Env var          | Required | Default | Purpose                                             |
| ---------------- | -------- | ------- | --------------------------------------------------- |
| `DIRECTORY`      | yes      | —       | App subdirectory under the datalake to serve at `/` |
| `DATA_DIRECTORY` | no       | —       | Additional subdirectory exposed at `/data/`         |

Host layout (CapRover default): `/mnt/persistent-storage/datalake/{DIRECTORY}`

When `DATA_DIRECTORY` is configured, the server creates a temporary document
root containing links to the app files and the selected data directory. The
source directories are not modified, and no other datalake directories are
exposed.

For example:

```text
DIRECTORY=my_app
DATA_DIRECTORY=comapeo_data
```

serves the app at `/` and its selected data at `/data/`.

## Why this fits Guardian Connector

One of Guardian Connector's goals is to allow communities and organizations to control their own data and the applications built around it.

Users can upload files or entire directories into the data lake using tools such as File Browser. Once uploaded, this HTTP server can simply be pointed at that directory, immediately making those files available over HTTP without requiring another deployment pipeline.

When deployed through CapRover, the application can also be protected using CapRover's built-in authentication features, allowing access to be restricted where appropriate.

This creates a simple workflow:

1. Upload files into the Guardian Connector data lake.
2. Point the HTTP server at that directory using `DIRECTORY`.
3. Access the application through the web.

## Example use case

Guardian Connector already provides tools such as [GC Explorer](https://github.com/ConservationMetrics/gc-explorer) for visualizing ingested datasets.

However, sometimes a project requires a completely custom experience—a presentation-quality map, a storytelling application, or a bespoke dashboard tailored to a particular audience.

In that case, you can:

- Ingest field data using [GC Scripts Hub](https://github.com/ConservationMetrics/gc-scripts-hub) (for example, CoMapeo observations).
- Create your own HTML and JavaScript application using Leaflet, Mapbox GL JS, OpenLayers, or any other frontend framework.
- Upload the application into the Guardian Connector data lake using File Browser.
- Configure this HTTP server to serve that directory.

Your application can then load and visualize the same Guardian Connector data while remaining entirely user-controlled. Both the underlying datasets and the web application itself live inside the Guardian Connector data lake, providing a lightweight and flexible way to build custom exploration experiences without requiring additional infrastructure.

# Quick Start

### 1. Build the Docker Image

```bash
docker build <YOUR_REGISTRY>/gc-http-server:latest .
```

The Docker image size is 2.6MB and the service takes up 308KB memory at rest.

On a fresh CapRover VM the data UID/GID is usually `1000`.

### 2. Run Locally with Docker

```bash
docker run -p 8080:8080 \
  -e DIRECTORY=demo \
  -e DATA_DIRECTORY=demo-data \
  -v "$(pwd)/data_mount:/data_mount" \
  <YOUR_REGISTRY>/gc-http-server:latest
```

Open http://localhost:8080

### 3. Deploy to CapRover

> [!NOTE]
>
> Until this image is available publicly i.e. on Docker Hub, you need to build it yourself and host it on your own registry.
>
> And, you need to add your Docker Registry to CapRover in the **Cluster** tab of the CapRover dashboard UI.

Prefer the one-click app in [`caprover/gc-http-server.yml`](caprover/gc-http-server.yml).
It mounts the host datalake at `/data_mount` and asks for `DIRECTORY` plus an
optional `DATA_DIRECTORY`.

**Manual (Method 6) — one-time Persistent Directories setup:**

1. Push the image to your registry.

2. Create the app with **Has Persistent Data**.

3. Persistent Directories (set once, then leave alone):
   - Path in App: `/data_mount`
   - Path on Host: `/mnt/persistent-storage/datalake`

4. Environment Variables:

   ```
   DIRECTORY=<your-folder>
   DATA_DIRECTORY=<optional-data-folder>
   ```

5. Container HTTP Port: `8080`.

6. Deploy via ImageName.

To serve a different folder later, change `DIRECTORY` only — do not edit Persistent Directories.

## Troubleshooting

- **`DIRECTORY is required`:** set the `DIRECTORY` env var.
- **`serve path does not exist`:** Path on Host must be the **whole data lake**
  (`/mnt/persistent-storage/datalake`), not a single subdirectory. Then
  `DIRECTORY` selects the folder under it.
- **`data path does not exist`:** `DATA_DIRECTORY`, when set, must identify a
  directory beneath the mounted data lake.
- **`reserved path .../data`:** The app directory cannot contain a top-level
  `data` entry when `DATA_DIRECTORY` is enabled because `/data/` is reserved.
