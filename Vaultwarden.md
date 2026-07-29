# 🔐 Self-Hosted Vaultwarden (Bitwarden) on 100% Free Cloud Infrastructure

A complete step-by-step guide to deploying, configuring, and hardening a **free, production-ready, self-hosted password manager** using **Vaultwarden**, **Render**, **Neon PostgreSQL**, and **UptimeRobot**.

---

## 📌 Architecture Overview

```
┌───────────────────────────────────────────────────────────┐
│                    Bitwarden Clients                      │
│      (Browser Extension / Android / iOS / Desktop)        │
└──────────────────────────┬────────────────────────────────┘
                           │ HTTPS (TLS 1.3)
                           ▼
┌───────────────────────────────────────────────────────────┐
│                    Render Web Service                     │
│  • Image: vaultwarden/server:latest (Rust implementation) │
│  • URL: https://vaultwarden-r4ro.onrender.com (example)   │
│  • Memory footprint: ~20-30 MB RAM                        │
└─────────────┬────────────────────────────────▲────────────┘
              │ Encrypted SSL                  │ 5-min HTTP ping
              ▼                                │ (prevents sleep)
┌───────────────────────────┐    ┌─────────────┴────────────┐
│    Neon.tech PostgreSQL   │    │        UptimeRobot       │
│  • Serverless database    │    │  • HTTP(s) monitor       │
│  • Region: AWS Singapore  │    │  • Interval: 5 minutes   │
│  • Storage limit: 0.5 GB  │    │  • Prevents cold starts  │
└───────────────────────────┘    └──────────────────────────┘
```

### Why this stack?

- **Vaultwarden (server):** an ultra-lightweight, open-source rewrite of the Bitwarden server, written in **Rust**. It runs on ~30 MB of RAM — versus roughly 2 GB for Bitwarden's official .NET stack — while unlocking all Bitwarden Premium features for free, including integrated 2FA/TOTP code generation and emergency access.
- **Render (compute):** free cloud container hosting (512 MB RAM, 750 free hours/month).
- **Neon.tech (database):** serverless PostgreSQL with 0.5 GB (500 MB) of free storage.
- **UptimeRobot (keep-alive):** pings the Render service every 5 minutes so it never hits Render's 15-minute inactivity sleep timer, keeping cold-start latency effectively at zero.

---

## 🛠️ Step-by-Step Setup Guide

### Step 1 — Create the managed database (Neon.tech)

1. Log into [Neon.tech](https://neon.tech) and create a new project named `vaultwarden`.
2. Select **AWS Asia Pacific 1 (Singapore)** — or whichever region is closest to you for lowest latency.
3. On the **Project Dashboard**, locate your **Connection String**.
4. Select **PostgreSQL** and copy the URI, which looks like:

   ```text
   postgresql://neondb_owner:<PASSWORD>@<ENDPOINT>.c-3.ap-southeast-1.aws.neon.tech/neondb?sslmode=require
   ```

   Make sure `?sslmode=require` is appended, to guarantee encrypted transport to the database.

---

### Step 2 — Deploy the Vaultwarden container (Render)

1. Log into [Render.com](https://render.com) and click **New +** → **Web Service**.
2. Choose **Existing Image** and enter:

   ```text
   vaultwarden/server:latest
   ```

3. Set the service parameters:
   - **Name:** `vaultwarden`
   - **Region:** Singapore / Asia Pacific (matching Neon, for lowest latency)
   - **Instance Type:** `Free`

4. Scroll down to **Environment Variables** and add the following:

   | Environment Variable | Value | Purpose |
   |---|---|---|
   | `DATABASE_URL` | `postgresql://neondb_owner:...@.../neondb?sslmode=require` | Connection string to your Neon PostgreSQL database |
   | `SIGNUPS_ALLOWED` | `true` | Temporarily enables account registration (disable after Step 4) |
   | `WEBSOCKET_ENABLED` | `true` | Enables real-time sync notifications between browser/app clients |
   | `IP_HEADER` | `X-Forwarded-For` | Correctly parses client IPs from behind Render's reverse proxy |

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

UptimeRobot now pings your instance around the clock. Since the interval (5 min) is shorter than Render's idle timeout (15 min), the sleep timer never triggers.

---

### Step 4 — Initial account creation & security hardening

> ⚠️ **Critical security step:** don't leave public signups enabled on a self-hosted instance any longer than necessary.

1. Open your live app URL (e.g. `https://vaultwarden-r4ro.onrender.com`) in a browser.
2. Click **Create Account**, enter your email, and set a high-entropy master password.
3. Log in, then go to **Account Settings → Security → Two-Step Login** and enable 2FA via an authenticator app (e.g. Aegis, 2FAS, or Ente Auth).
4. Save your 2FA recovery code somewhere offline and safe.
5. **Lock down signups:**
   - Return to your **Render Dashboard → Environment**.
   - Change `SIGNUPS_ALLOWED` from `true` to `false`.
   - Click **Save Changes** — Render will automatically redeploy with signups permanently closed.

---

### Step 5 — Connecting Bitwarden clients & importing data

**Browser extensions & mobile apps:**

1. Install the official Bitwarden extension or mobile app (Android/iOS).
2. On the login screen, click the gear icon (⚙️ Settings) at the top.
3. In the **Server URL** field, enter your full domain, e.g.:

   ```text
   https://vaultwarden-r4ro.onrender.com
   ```

4. Click **Save**, then log in with your master password and 2FA code.

**Importing existing vault data:**

1. In the Vaultwarden web vault, go to **Tools → Import Data**.
2. Choose your source format (`Bitwarden (json)`, `Bitwarden (csv)`, `1Password`, `LastPass`, etc.).
3. Select your export file and click **Import**.
4. Any imported TOTP/2FA secrets immediately render as live, rotating 6-digit codes in the client apps. When autofilling logins, Bitwarden automatically copies the current TOTP code to your clipboard for pasting.

---

## 🔒 Security & encryption architecture

- **Zero-knowledge architecture:** master-key derivation and all cryptographic operations happen client-side, using PBKDF2 (or Argon2) plus AES-256 encryption.
- **Database security:** what's stored in Neon PostgreSQL is encrypted ciphertext only — neither Neon, Render, nor anyone else can read your passwords or notes.
- **Mandatory TLS:** Render automatically provisions Let's Encrypt certificates, and all HTTP traffic is force-redirected to HTTPS.

---

## 📊 Resource usage & storage footprint

- **RAM usage:** roughly 25–35 MB out of the 512 MB available on Render's free tier.
- **Database storage:** credentials, URLs, notes, and 2FA seeds are stored as compact text. A vault with 500+ items typically uses under 2 MB of Neon's 500 MB free tier.
- **Compute hours:** running 24/7 uses about 744 hours in a 31-day month — within Render's 750 free monthly hours, but with very little headroom if you run other free services on the same account.

---

## 📁 Recommended disaster recovery & backups

1. **Encrypted vault exports:** periodically export your vault from **Tools → Export Vault** as an encrypted `.json` file and store it somewhere safe outside of Render/Neon.
2. **Neon point-in-time recovery:** Neon retains database history, letting you roll back or branch data from the Neon console if something goes wrong.

---

*Enjoy your fully self-hosted, private, zero-cost password and 2FA manager!*
