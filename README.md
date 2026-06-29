# Bellboy Setup Guide

This guide walks you through setting up the **Bellboy** backend using Docker and Docker Compose.

> **Requirements**:
>
> - Docker
> - Docker Compose
> - A Linux-based OS
> - Rust

## Setup and Run Bellboy

Create `firebase_config.json`.
   - Go to [Google Cloud Console](https://console.cloud.google.com)
   - Open your Firebase project
   - Navigate to **APIs & Services → Credentials → Service Accounts → Manage service accounts**, then click **Create service account**
     - Enter a name, then click **Done**
   - Click the newly created service account → **Keys → Add key → Create new key**
     - Select **JSON**, then click **Create**
     - Download and save the key file
     - Put `firebase_config.json` file into `config` folder.


Create APNs Auth Key (`.p8` file).
   - Go to [Apple Developer](https://developer.apple.com/account)
   - Navigate to **Certificates, Identifiers & Profiles**
   - Select **Keys** on the left sidebar, then click the **+** button to add a new key
     - Enter a Key Name (e.g., "VoIP Push Key")
     - Check the box for **Apple Push Notification service (APNs)**
     - Click **Continue**, then click **Register**
   - Click **Download** to save the `.p8` file
     - *Important: You can only download this file once. Keep it safe.*
   - Note down the **Key ID** (from this page) and your **Team ID** (found in your Apple Developer account settings), as your server will need them alongside the `.p8` file.
   - Put `.p8` file into `config` folder.

Create the runtime `.env` file from `.env.example`.
   - Configure only PostgreSQL, Redis, and `AUTH_SHARED_SECRET` if you use external auth.
   - Other variables can keep their default values unless you need to customize those features.
   - S3-compatible avatar storage only needs to be configured when the end-user service must update user avatars without sharing the main service storage.

Edit `bellboy.toml` to include:
   - Datastore, Concierge, PostgreSQL, Meilisearch connection info
   - Link preview service URL under `link_preview_domain`
   - S3-compatible object storage configuration:
     - `storage_access_token`, `storage_secret_key`, `storage_private_url`, `storage_public_url`
     - `storage_bucket_name`, `storage_bucket_path`
   - `license_install_key` in the Bellboy config

Please ensure that all necessary configurations within the `config/` directory are updated and properly filled out. Upon successful completion of the prerequisite steps above, deploy the services by running the following command:

```bash
docker compose up -d
```

## E2EE Topic And Scope Sync

E2EE topics support hybrid MLS scope behavior:

- Non-gated topics under an E2EE parent inherit the parent MLS group. API responses expose `e2ee_group_id` as the parent cid.
- Gated E2EE topics use their own MLS group. Topic creation requires the MLS bootstrap bundle and responses expose `e2ee_group_id` as the topic cid.
- Non-gated E2EE topics under non-E2EE parents are rejected.

E2EE send and update payloads may include `e2ee_group_id`. When present, Bellboy validates it against the server-resolved MLS scope before accepting the message.

`POST /v1/e2ee/scope_sync` syncs by MLS scope. Parent scopes include parent events plus inherited non-gated topic application and metadata events. Gated topic scopes remain isolated to the topic cid. The response includes each event `cid`, optional `parent_cid`, `event_id`, `created_at`, and normalized event `data`.

For initial scope sync, a scope cursor may be `null`; Bellboy starts from the member's join boundary and then returns an `EventCursor` for the next request.

No SQL migration is required for scope sync. Sync pointers are stored in Concierge rooms named `sync_index:{scope_cid}`.


## ✅ All done!

Bellboy should now be running and connected to all required services.

If you encounter issues, check the logs of each service using:

```bash
docker-compose logs -f
```
