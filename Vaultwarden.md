# 🔐 Self-Hosted Vaultwarden (Bitwarden) on 100% Free Cloud Infrastructure

A complete step-by-step guide to deploying, configuring, and hardening a **free, production-ready, self-hosted password manager** using **Vaultwarden**, **Render**, **Aiven for PostgreSQL**, and **UptimeRobot**.

> ⚠️ **Read this before you commit to Aiven over Neon:** Aiven's free tier database can power itself off after a period of inactivity, and — unlike Neon's scale-to-zero — it does **not** automatically wake back up on a new connection. Waking it back up is a manual "Power on" click in the Aiven console (restoring from the latest backup, which can take anywhere from a few minutes to a few hours depending on size). No amount of pinging Render with UptimeRobot can prevent or fix this, since a ping to your web app has no guaranteed path to touching the database at all. If Aiven powers off, Vaultwarden will simply fail to connect until you manually restart it. Keep this in mind if "fully hands-off, always-on" is your goal — see the caveats section at the bottom before deciding.

---

## 📌 Architecture Overview

```
┌───────────────────────────────────────────────────────┐
│                     Bitwarden Clients                 │
│       (Browser Extension / Android / iOS / Desktop)   │
└───────────────────────────────────────────────────────┘
                           │ HTTPS (TLS 1.3)
                           ▼
┌───────────────────────────────────────────────────────┐
│                     Render Web Service                │
│ Image: vaultwarden/server:latest (Rust)               │
│ URL: https://vaultwarden-r4ro.onrender.com            │
│ Memory footprint: ~20-30 MB RAM                       │
└─────────────┬───────────────────────────────▲─────────┘
              │ Encrypted SSL                 │ 5-min HTTP ping
              ▼                               │ (keeps Render awake)
┌───────────────────────────┐     ┌───────────┴─────────┐
│    Aiven for PostgreSQL   │     │      UptimeRobot    │
│ Free-1-1GB tier           │     │ HTTP(s) monitor     │
│ Geo: Asia Pacific         │     │ Interval: 5 minutes │
│ Storage limit: 1.0 GB     │     │ Pings Render only   │
└───────────────────────────┘     └─────────────────────┘
```

Note: unlike the Neon version of this guide, UptimeRobot here only keeps **Render** awake. It has no effect on Aiven's power state — that's a separate, manual concern (see the caveats section).

### Why this stack?

- **Vaultwarden (server):** an ultra-lightweight, open-source rewrite of the Bitwarden server, written in **Rust**. It runs on ~30 MB of RAM — versus roughly 2 GB for Bitwarden's official .NET stack — while unlocking all Bitwarden Premium features for free, including integrated 2FA/TOTP code generation and emergency access.
- **Render (compute):** free cloud container hosting (512 MB RAM, 750 free hours/month).
- **Aiven for PostgreSQL (database):** a real, dedicated managed PostgreSQL instance — same infrastructure as Aiven's paid tiers — with 1 GB storage, 1 GB RAM, and 1 CPU, no credit card required, and automated backups included.
- **UptimeRobot (keep-alive):** pings the Render service every 5 minutes so it never hits Render's 15-minute inactivity sleep timer.

---

## 🛠️ Step-by-Step Setup Guide

### Step 1 — Create the managed database (Aiven for PostgreSQL)

1. Log into [Aiven.io](https://aiven.io) and create a project named `vaultwarden`.
2. On the console dashboard, click **Create Service**.
3. Select **Aiven for PostgreSQL®**.
4. Choose the **Free** plan (`Free-1-1GB` — 1 CPU, 1 GB RAM, 1 GB storage).
5. On the free tier you can only choose a broad geographical area (Asia Pacific, Australia, Europe, or North America) — not a specific city or cloud provider. Pick whichever is closest to you.
6. Click **Create Service** and wait for it to switch to **Running**.
7. Go to the **Overview** (or **Connect**) tab and copy your **Service URI**:

   ```text
   postgres://avnadmin:<PASSWORD>@<HOST>:<PORT>/defaultdb?sslmode=require
   ```

---

### Step 2 — Deploy the Vaultwarden container (Render)

1. Log into [Render.com](https://render.com) and click **New +** → **Web Service**.
2. Choose **Existing Image** and enter:

   ```text
   vaultwarden/server:latest
   ```

3. Set the service parameters:
   - **Name:** `vaultwarden`
   - **Region:** whichever's closest to you (note: Render and Aiven are different infrastructure providers, so region-matching between them doesn't meaningfully reduce latency the way it would if both were on the same cloud)
   - **Instance Type:** `Free`

4. Scroll down to **Environment Variables** and add the following:

   | Environment Variable | Value | Purpose |
   |---|---|---|
   | `DATABASE_URL` | `postgres://avnadmin:...@.../defaultdb?sslmode=require` | Connection string to your Aiven PostgreSQL database |
   | `DOMAIN` | `https://vaultwarden-r4ro.onrender.com` | Your instance's public URL. Required for correct icon downloads, WebAuthn/FIDO2 login, and email links to work |
   | `SIGNUPS_ALLOWED` | `true` | Temporarily enables account registration (disable after Step 4) |
   | `WEBSOCKET_ENABLED` | `true` | Enables real-time sync notifications between browser/app clients |
   | `IP_HEADER` | `X-Forwarded-For` | Correctly parses client IPs from behind Render's reverse proxy |
   | `ADMIN_TOKEN` | an Argon2 hash — see below | Enables and protects the `/admin` panel. Without this variable set, the admin panel is disabled entirely |

   **Generating `ADMIN_TOKEN`:**

   ```bash
   docker run --rm -it vaultwarden/server /vaultwarden hash
   ```

   This prompts for a password and prints a ready-to-use line like:

   ```text
   ADMIN_TOKEN='$argon2id$v=19$m=65540,t=3,p=4$...'
   ```

   Copy only the hash itself — the part between (and including) the quotes, without `ADMIN_TOKEN=` and without the surrounding quote marks — and paste that as the value in Render. Keep the plain-text password safe; that's what you'll type into the `/admin` login form, not the hash.

5. Click **Create Web Service** and wait 1–2 minutes for the initial build and database migration to finish, until the status shows **Deploy live**.
6. Note your live app URL (e.g. `https://vaultwarden-r4ro.onrender.com`) — you'll need it for the next steps.

---

### Step 3 — Prevent the container from sleeping (UptimeRobot)

Render puts free web services to sleep after 15 minutes without incoming requests. Bypass this with a keep-alive monitor:

1. Log into [UptimeRobot.com](https://uptimerobot.com) and click **Add New Monitor**.
2. Configure:
   - **Monitor Type:** `HTTP(s)`
   - **Friendly Name:** `Vaultwarden Render`
   - **URL (or IP):** `https://vaultwarden-r4ro.onrender.com`
   - **Monitoring Interval:** `Every 5 minutes`
3. Click **Create Monitor**.

This keeps **Render** awake. It does **not** keep Aiven awake — see the caveats section below for what that means in practice.

---

### Step 4 — Initial account creation & security hardening

> ⚠️ **Critical security step:** don't leave public signups enabled on a self-hosted instance any longer than necessary.

1. Open your live app URL in a browser.
2. Click **Create Account**, enter your email, and set a high-entropy master password.
3. Log in, then go to **Account Settings → Security → Two-Step Login** and enable 2FA via an authenticator app (e.g. Aegis, 2FAS, or Ente Auth).
4. Save your 2FA recovery code somewhere offline and safe.
5. **Lock down signups:**
   - Return to your **Render Dashboard → Environment**.
   - Change `SIGNUPS_ALLOWED` from `true` to `false`.
   - Click **Save Changes** — Render will automatically redeploy with signups permanently closed.
6. **Confirm the admin panel works:** visit `https://vaultwarden-r4ro.onrender.com/admin` and log in with the plain-text password from Step 2 (not the hash).

---

### Step 5 — Connecting Bitwarden clients & importing data

**Browser extensions & mobile apps:**

1. Install the official Bitwarden extension or mobile app (Android/iOS).
2. On the login screen, click the gear icon (⚙️ Settings) at the top.
3. In the **Server URL** field, enter your full domain:

   ```text
   https://vaultwarden-r4ro.onrender.com
   ```

4. Click **Save**, then log in with your master password and 2FA code.

**Importing existing vault data:**

1. In the Vaultwarden web vault, go to **Tools → Import Data**.
2. Choose your source format (`Bitwarden (json)`, `Bitwarden (csv)`, `1Password`, `LastPass`, etc.).
3. Select your export file and click **Import**.

---

## 🔒 Security & encryption architecture

- **Zero-knowledge architecture:** master-key derivation and all cryptographic operations happen client-side, using PBKDF2 (or Argon2) plus AES-256 encryption.
- **Database security:** what's stored in Aiven PostgreSQL is encrypted ciphertext only — neither Aiven, Render, nor anyone else can read your passwords or notes.
- **Mandatory TLS:** Render automatically provisions Let's Encrypt certificates, and all HTTP traffic is force-redirected to HTTPS.
- **Admin panel:** protected by the Argon2-hashed `ADMIN_TOKEN` — without it set, `/admin` is disabled entirely, not merely unprotected.

---

## 📊 Resource usage & storage footprint

- **RAM usage:** roughly 25–35 MB out of the 512 MB available on Render's free tier.
- **Database storage:** a fresh PostgreSQL instance has some baseline overhead for system catalogs, but it's small relative to Aiven's 1 GB free limit. Vaultwarden's own data (credentials, URLs, notes, 2FA seeds) is stored as compact text — a vault with 500+ items typically uses only a few MB.
- **Compute hours:** running Render 24/7 uses about 744 hours in a 31-day month — within Render's 750 free monthly hours, with little headroom if you run other free services on the same account.

---

## ⚠️ Aiven-specific caveats (read before relying on this for daily use)

- **Free-tier services can power off after inactivity**, and restarting them is a **manual action** in the Aiven console — there's no automatic wake-on-connect the way Neon or Render behave. If your vault has been untouched for a while and Vaultwarden suddenly can't connect to its database, this is the first thing to check.
- **Services powered off for more than 180 days are automatically deleted.** If you go a long stretch without touching either the vault or the Aiven console, set a reminder to log in periodically.
- Realistically, if you actually check your vault regularly (which most people do — it's a password manager), this may rarely bite you. But it's meaningfully less "fire and forget" than Neon, and worth testing yourself: let the Aiven service sit idle, then see whether a client login attempt fails outright or eventually succeeds after a delay, so you know what to expect.

---

## 📁 Recommended disaster recovery & backups

1. **Encrypted vault exports:** periodically export your vault from **Tools → Export Vault** as an encrypted `.json` file and store it somewhere safe outside of Render/Aiven.
2. **Aiven automated backups:** Aiven includes automated backups on the free tier, used when a powered-off service is restarted — but a manual export is still a good independent backup you control yourself.

---

*Enjoy your fully self-hosted, private, zero-cost password and 2FA manager!*
