# gc-http-server: minimal static HTTP server

A lightweight HTTP server for serving static content directly from the Guardian Connector data lake (or any mounted volume).

This service runs a minimal BusyBox `httpd` web server and exposes files stored within the Guardian Connector data lake over HTTP. It is particularly useful for hosting custom HTML, JavaScript, CSS, images, or other static assets that interact with data already managed by Guardian Connector.

## How it works

By default, the container mounts the Guardian Connector data lake and serves files directly from it.

The service supports the following environment variables:

| Env var          | Required | Default | Purpose                                                  |
| ---------------- | -------- | ------- | -------------------------------------------------------- |
| `DIRECTORY`      | yes      | —       | App subdirectory under the datalake to serve at `/`      |
| `DATA_DIRECTORY` | no       | —       | Additional subdirectory exposed at `/data/`              |
| `AUTH_ENABLED`   | no       | `false` | `true` requires an Auth0 login before any file is served |

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

When deployed through CapRover, access can be restricted either with this server's Auth0 login or with CapRover's HTTP Basic Auth. Use one of those controls, not both. Auth0 gives each approved Guardian Connector user their own login. Basic Auth uses one shared username and password.

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

## Auth0 protection

Set `AUTH_ENABLED=true` to require login before any mounted file is served. In this mode oauth2-proxy is the only server process: it handles Auth0 and reads the selected directory itself. `/`, nested assets, and `/data/` all require a session. `/ping` and `/ready` stay open so the container can report health, and `/oauth2/` is reserved for login, callback, and logout.

An anonymous browser request is redirected to Auth0. It does not receive the file. A request that sends `Accept: application/json` gets `401` instead of a redirect. The ID token must include `Member` or `Admin` in `urn:gc:roles`, the claim the tenant's **Add Roles Claim** Post-Login action copies from the user's Auth0 roles. `Guest`, `SignedIn`, and a missing claim are refused with `403` and no session cookie. **Check Approval** can still deny login before a token is issued. An unverified email does not deny a Member or Admin.

Create one Auth0 **Regular Web Application** for each public site:

| Auth0 setting         | Value                                                 |
| --------------------- | ----------------------------------------------------- |
| Allowed Callback URLs | `https://<host>/oauth2/callback`                      |
| Allowed Logout URLs   | `https://<host>/`                                     |
| Allowed Web Origins   | `https://<host>`                                      |
| Connections           | The tenant's existing database and Google connections |

No Auth0 Management API scopes are required. Roles are read from the ID token claim `urn:gc:roles`.

| Env var                        | Required when Auth0 is enabled | Purpose                                                                                                                               |
| ------------------------------ | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| `OAUTH2_PROXY_OIDC_ISSUER_URL` | yes                            | Issuer from the tenant's `/.well-known/openid-configuration`, including its trailing slash. Example: `https://<tenant>.us.auth0.com/` |
| `OAUTH2_PROXY_CLIENT_ID`       | yes                            | Auth0 application client ID                                                                                                           |
| `OAUTH2_PROXY_CLIENT_SECRET`   | yes                            | Auth0 application client secret                                                                                                       |
| `OAUTH2_PROXY_REDIRECT_URL`    | yes                            | `https://<host>/oauth2/callback`                                                                                                      |
| `OAUTH2_PROXY_COOKIE_SECRET`   | yes                            | 32-byte secret used to sign the session cookie                                                                                        |
| `OAUTH2_PROXY_COOKIE_SECURE`   | no                             | Defaults to `true`. Set `false` only for local `http://` testing                                                                      |

Generate a cookie secret with:

```bash
openssl rand -base64 32 | tr '+/' '-_'
```

On CapRover, enable **Force HTTPS**. Leave CapRover HTTP Basic Auth off; the two prompts conflict, and Basic Auth would sit in front of the Auth0 redirect.

`/oauth2/sign_out` clears the site session. The Auth0 session can still silently sign the same browser back in. To end that session too, link to:

```text
/oauth2/sign_out?rd=<urlencoded https://<tenant>.us.auth0.com/v2/logout?client_id=<client-id>&returnTo=https://<host>/>
```

`returnTo` must match an Auth0 Allowed Logout URL. The tenant host is already allowed as a post-login redirect target.

Authenticated files use Go's built-in content types. `mime.types` adds the font, Markdown, source-map, icon, and WebM types that BusyBox otherwise gets from `httpd.conf`. HTML, CSS, JavaScript, JSON, images, fonts, PDF, and common audio and video files are served with their usual types. Unauthenticated serving still uses BusyBox and `httpd.conf`.

# Quick Start

### 1. Build the Docker Image

```bash
docker build <YOUR_REGISTRY>/gc-http-server:latest .
```

The image is about 66 MB because it includes oauth2-proxy. Without Auth0 it uses about 400 KB of memory; with Auth0 enabled it uses about 7 MB.

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
   AUTH_ENABLED=false
   ```

   For Auth0, set `AUTH_ENABLED=true` and supply the issuer, client ID, client secret, redirect URL, and cookie secret from [Auth0 protection](#auth0-protection).

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
- **`AUTH_ENABLED=true requires`:** the Auth0 client, issuer, redirect URL, and cookie secret must all be set.
- **Redirect or cookie-secure errors:** a public CapRover site uses an `https://<host>/oauth2/callback` redirect and the default secure cookie. `OAUTH2_PROXY_COOKIE_SECURE=false` is only valid with an `http://` redirect for local testing.
- **Login succeeds but the next request is anonymous:** the callback URL, Auth0 Allowed Callback URL, and public host disagree, or the app is not using HTTPS while the cookie is marked secure.
- **403 `Invalid session: unauthorized`:** the account has neither the Auth0 role `Member` nor `Admin`, or the login flow is not writing `urn:gc:roles` onto the ID token.
- **500 after Auth0 redirects back:** the proxy error page hides the cause. The container log line is `Error redeeming code during OAuth2 callback`. `email_verified: false` is accepted. The callback reads email and roles from the ID token and does not call Auth0's userinfo endpoint.
- **`/ping` or `/ready` does not show a mounted file:** those paths are health checks when Auth0 is enabled.
