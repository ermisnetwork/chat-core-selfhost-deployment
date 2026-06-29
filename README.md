# Bellboy Setup Guide

This guide walks you through setting up the **Bellboy** backend using Docker and Docker Compose.

> [!IMPORTANT]
> **Requirements**:
> - Docker
> - Docker Compose
> - A Linux-based OS (or macOS running Docker Desktop)

---

## Step-by-Step Setup

### Step 1: Create the `config/` Directory and Setup Credentials
Before starting Docker Compose, you must create a `config/` directory inside the deployment directory and prepare the required files.

> [!WARNING]
> You **must** create these files on the host before running `docker compose up`. If they do not exist, Docker will automatically create empty directories with these names on the host, causing mounting conflicts and container crashes.

1. **Create the `config/` folder**:
   ```bash
   mkdir -p config
   ```

2. **Add APNs Auth Key (`.p8` file)**:
   - Generate your VoIP APNs key from your [Apple Developer Account](https://developer.apple.com/account) (Certificates, Identifiers & Profiles → Keys).
   - Download the `.p8` file (e.g. `AuthKey_XXXXXX.p8`) and place it inside the `config/` folder.
   - For simplicity, you can rename it to `AppleAuthKey.p8` or keep the default name and update `bellboy.toml` accordingly.

3. **Add Firebase Service Account Key**:
   - Go to Google Cloud Console → Firebase Project → Service Accounts.
   - Create a service account key in **JSON** format, download it, rename it to `firebase_config.json`, and place it inside the `config/` folder.

---

### Step 2: Configure Environment Variables (`.env`)
Copy `.env.example` to `.env` and fill in your environment variables:
```bash
cp .env.example .env
```
Key configurations:
- **`AUTH_SHARED_SECRET`**: HS256 auth secret shared by user-service and bellboy.
- **`OTP_SECRET`**: Even if `OTP_ENABLED` is set to `false`, a value for `OTP_SECRET` **must** be provided in `.env` (e.g. `OTP_SECRET=replace-with-otp-secret`) because the `user-service` configuration parser requires the variable to parse successfully.

---

### Step 3: Configure `bellboy.toml`
Copy the default config template or edit `config/bellboy.toml`. Inside `bellboy.toml`, update the following fields:

1. **Secrets Alignment**:
   For the stack components to authenticate and communicate securely, several secrets must match across different configuration files. 

   #### A. Datastore Secret Connection
   The Datastore service defines a master secret which must be used by any client connecting to it (Concierge and Bellboy):
   - **Datastore Server**: `config/datastore-config.yaml` → `secret`
   - **Concierge Client**: `config/concierge-config.yaml` → `db_secret`
   - **Bellboy Client**: `config/bellboy.toml` → `datastore_secret`
   
   > [!IMPORTANT]
   > The three values above **must be identical** (e.g., `"datastore-secret"`).

   #### B. Concierge Secret Connection
   The Room Server (Concierge) defines its own secret, which must be used by the main API server (Bellboy) to connect to it:
   - **Concierge Server**: `config/concierge-config.yaml` → `secret`
   - **Bellboy Client**: `config/bellboy.toml` → `concierge_secret`

   > [!IMPORTANT]
   > The two values above **must be identical** (e.g., `"concierge-quic-secret"`).

   #### C. JWT Shared Secret
   The auth token secret shared between the User Service and the Chat Engine (Bellboy):
   - **User Service (loco-rs)**: `.env` → `AUTH_SHARED_SECRET`
   - **Bellboy Client**: `config/bellboy.toml` → `jwt_secret`

   > [!IMPORTANT]
   > The two values above **must be identical** (e.g., `"replace-with-strong-shared-auth-secret"`).

   #### D. PostgreSQL Database Credentials
   The database credentials configured for the PostgreSQL container (`uhm-db`) must align with the database connection credentials in `bellboy.toml`:
   - **PostgreSQL Container (`uhm-db`)**: `docker-compose.yml` → `environment` → `POSTGRES_USER` & `POSTGRES_PASSWORD` & `POSTGRES_DB`
   - **Bellboy Server**: `config/bellboy.toml` → `postgres_user` & `postgres_password` & `postgres_database`

   > [!IMPORTANT]
   > The database username, password, and database name configured in both files **must be identical** to avoid database connection failures.

2. **File Paths (Absolute Paths)**:
   Because the entire `config/` directory is mounted to `/app/config/` inside the container, configure paths inside `bellboy.toml` as absolute paths to prevent atomic write/rename failures (`EBUSY` or `Is a directory` errors):
   ```toml
   firebase_config_path = "/app/config/firebase_config.json"
   voip_secret_path = "/app/config/AppleAuthKey.p8"
   license_state_path = "/app/config/license-state.json"
   ```

3. **Set a Valid `instance_id`**:
   Replace the placeholder `instance_id = "<gen-your-uuid-v4>"` with a valid UUID v4 (e.g., you can generate one using `uuidgen` in terminal). Leaving the placeholder string will cause the container to crash on startup.

4. **License Configuration (`auth_mode`)**:
   - Set `auth_mode = "self_host"`.
   - Configure the `license_install_key` provided by the vendor.

---

### Step 4: Run the Deployment
Once all files are configured and present in the `config/` folder, start the services using:
```bash
docker compose up -d
```

Check the running status of your containers:
```bash
docker compose ps
```

---

## 🔍 Troubleshooting Common Errors

### 1. `failed to read or persist activation state: Device or resource busy (os error 16)`
- **Cause**: `license-state.json` was bind-mounted directly as a file. The Rust client attempts to write changes atomically by writing to `.tmp` and renaming over the file, which fails on direct file bind-mounts.
- **Fix**: Ensure you mount the entire folder `./config:/app/config` and configure `license_state_path = "/app/config/license-state.json"` in `bellboy.toml` as described in Step 3.

### 2. `Error: OTP_SECRET is required`
- **Cause**: `user-service` config parsing failed because `OTP_SECRET` was missing from `.env`.
- **Fix**: Add `OTP_SECRET=replace-with-otp-secret` to `.env` even if `OTP_ENABLED=false`.

---

## 💡 Additional Deployment Notes

### 1. Network Modes (`host` vs `bridge`)
This deployment uses a hybrid networking layout:
- **Host Network Mode (`network_mode: "host"`)**:
  Used by `uhm-datastore`, `uhm-roomserver`, `uhm-bellboy`, and `uhm-db` to bind directly to the host network interface. This is crucial for optimal performance of the QUIC-based Room Server (`uhm-roomserver`) and real-time socket connections.
- **Bridge Network Mode**:
  Used by other containers (e.g. `user-service`, `postgres`, `redis`, `uhm-meilisearch`).
  
> [!NOTE]
> On macOS (Docker Desktop), the `host` containers bind to the Docker virtual machine network, not the macOS network itself. If bridge containers need to access host containers, they must connect using `host.docker.internal` or through mapped ports. Fortunately, they are pre-configured to communicate properly in this layout.

### 2. Apple Push Notification (APNs/VoIP) Checklist
To enable iOS VoIP calls and push notifications:
1. Ensure the correct APNs private key is placed in `config/AppleAuthKey.p8` (and matches the `voip_secret_path` in `bellboy.toml`).
2. Fill in the following fields in `config/bellboy.toml` using your Apple Developer portal details:
   - `voip_key_id`: The 10-character Key ID associated with the `.p8` key.
   - `voip_team_id`: Your Apple Developer Team ID.
   - `voip_topic`: Your iOS App ID Bundle suffixed with `.voip` (e.g., `network.ermis.ermischat.voip`).
   - `voip_domain`: Keep as `"https://api.push.apple.com:443/3/device/"` for production or `"https://api.sandbox.push.apple.com:443/3/device/"` for sandbox.

### 3. Media & File Storage (S3-Compatible)
To allow file attachments (images, video, documents) upload and download, configure an S3-compatible bucket (like Cloudflare R2, MinIO, AWS S3) in `config/bellboy.toml` under the `storage_` config block:
- `storage_access_token` & `storage_secret_key`: Access/Secret keys.
- `storage_private_url`: Private endpoint for writes.
- `storage_public_url`: Public endpoint for client access.
- `storage_bucket_name` & `storage_bucket_path`: Target bucket details.

### 4. Meilisearch Master Key Alignment
The search indexing engine relies on Meilisearch:
- **Meilisearch Server**: `docker-compose.yml` → `MEILI_MASTER_KEY`
- **Bellboy Client**: `config/bellboy.toml` → `meilisearch_secret`
Ensure these match exactly (default is `"ms-secret"`).

---

## E2EE Topic And Scope Sync
E2EE topics support hybrid MLS scope behavior:
- Non-gated topics under an E2EE parent inherit the parent MLS group. API responses expose `e2ee_group_id` as the parent cid.
- Gated E2EE topics use their own MLS group. Topic creation requires the MLS bootstrap bundle and responses expose `e2ee_group_id` as the topic cid.
- Non-gated E2EE topics under non-E2EE parents are rejected.

E2EE send and update payloads may include `e2ee_group_id`. When present, Bellboy validates it against the server-resolved MLS scope before accepting the message.

`POST /v1/e2ee/scope_sync` syncs by MLS scope. Parent scopes include parent events plus inherited non-gated topic application and metadata events. Gated topic scopes remain isolated to the topic cid. The response includes each event `cid`, optional `parent_cid`, `event_id`, `created_at`, and normalized event `data`.

For initial scope sync, a scope cursor may be `null`; Bellboy starts from the member's join boundary and then returns an `EventCursor` for the next request.

No SQL migration is required for scope sync. Sync pointers are stored in Concierge rooms named `sync_index:{scope_cid}`.
