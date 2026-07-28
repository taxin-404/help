# 🔐 Self-Hosted Vaultwarden (Bitwarden) on 100% Free Cloud Infrastructure

A complete step-by-step guide to deploying, configuring, and hardening a **100% free, production-ready, self-hosted password manager** using **Vaultwarden**, **Render**, **Neon PostgreSQL**, and **UptimeRobot**.

---

## 📌 Architecture Overview


```

┌─────────────────────────────────────────────────────────┐
│                   Bitwarden Clients                     │
│     (Browser Extension / Android / iOS / Desktop)       │
└──────────────────────────┬──────────────────────────────┘
│ HTTPS (TLS 1.3)
▼
┌─────────────────────────────────────────────────────────┐
│                    Render Web Service                   │
│   • Image: vaultwarden/server:latest (Rust implementation)│
│   • URL: [https://vaultwarden-r4ro.onrender.com](https://www.google.com/url?sa=E&source=gmail&q=https://vaultwarden-r4ro.onrender.com)         │
│   • Memory Footprint: ~20–30 MB RAM                     │
└─────────────┬─────────────────────────────▲─────────────┘
│ Encrypted SSL               │ 5-min HTTP Ping
▼                             │ (Prevents Sleep)
┌───────────────────────────┐ ┌─────────────┴─────────────┐
│    Neon.tech PostgreSQL   │ │        UptimeRobot        │
│  • Serverless Database    │ │  • HTTP/S Monitor         │
│  • Region: AWS Singapore  │ │  • Interval: 5 minutes    │
│  • Storage Limit: 0.5 GB  │ │  • Prevents cold starts   │
└───────────────────────────┘ └───────────────────────────┘

```

### Why This Stack?

* **Vaultwarden (Server):** An ultra-lightweight, open-source rewrite of Bitwarden written in **Rust**. It uses ~30 MB of RAM (compared to Bitwarden's official .NET stack which requires ~2 GB), unlocking **all Bitwarden Premium features for free** (including integrated 2FA/TOTP generation and emergency access).
* **Render (Compute):** Provides free cloud container hosting (512 MB RAM, 750 free hours/month).
* **Neon.tech (Database):** Serverless PostgreSQL database with 0.5 GB (500 MB) of free storage.
* **UptimeRobot (Keep-Alive):** Pings the Render service every 5 minutes to prevent Render's free tier from going to sleep after 15 minutes of inactivity, guaranteeing **0ms cold-start latency**.

---

## 🛠️ Step-by-Step Setup Guide

### Step 1: Create the Managed Database (Neon.tech)

1. Log into [Neon.tech](https://neon.tech) and create a new project named **`vaultwarden`**.
2. Select **AWS Asia Pacific 1 (Singapore)** (or your nearest low-latency region).
3. On the **Project Dashboard**, locate your **Connection String**.
4. Select **PostgreSQL** and copy the URI format:
   ```text
   postgresql://neondb_owner:<PASSWORD>@<ENDPOINT>.c-3.ap-southeast-1.aws.neon.tech/neondb?sslmode=require

```

*(Ensure `?sslmode=require` is appended to guarantee encrypted transport).*

---

### Step 2: Deploy Vaultwarden Container (Render)

1. Log into [Render.com](https://render.com) and click **New +** → **Web Service**.
2. Choose **Existing Image** and enter:
```text
vaultwarden/server:latest

```


3. Set the service parameters:
* **Name:** `vaultwarden`
* **Region:** Singapore / Asia Pacific (matching Neon for lowest latency)
* **Instance Type:** `Free`


4. Scroll down to **Environment Variables** and add the following keys:

| Environment Variable | Value | Purpose |
| --- | --- | --- |
| `DATABASE_URL` | `postgresql://neondb_owner:.../neondb?sslmode=require` | Direct connection link to Neon PostgreSQL |
| `SIGNUPS_ALLOWED` | `true` | Temporarily enables account registration |
| `WEBSOCKET_ENABLED` | `true` | Enables real-time browser/app sync notifications |
| `IP_HEADER` | `X-Forwarded-For` | Correctly parses client IP addresses behind Render's reverse proxy |

5. Click **Create Web Service**. Wait 1–2 minutes for the initial build and database table migration to complete until status displays **Deploy live**.
6. Note your live app URL (e.g., `https://vaultwarden-r4ro.onrender.com`).

---

### Step 3: Prevent Container Sleep (UptimeRobot)

Render puts free containers to sleep after 15 minutes without web requests. We bypass this using UptimeRobot:

1. Log into [UptimeRobot.com](https://uptimerobot.com) and click **Add New Monitor**.
2. Configure the monitor details:
* **Monitor Type:** `HTTP(s)`
* **Friendly Name:** `Vaultwarden Render`
* **URL (or IP):** `https://vaultwarden-r4ro.onrender.com`
* **Monitoring Interval:** `Every 5 minutes`


3. Click **Create Monitor**.
4. UptimeRobot will now ping your instance around the clock. Because the interval is 5 minutes, Render's 15-minute idle timer will **never** trigger.

---

### Step 4: Initial Account Creation & Security Hardening

> ⚠️ **CRITICAL SECURITY STEP:** Do not leave public signups enabled on a self-hosted instance!

1. Open your live application URL (`https://vaultwarden-r4ro.onrender.com`) in your web browser.
2. Click **Create Account**, enter your primary email, and set a high-entropy **Master Password**.
3. Immediately log into your account, go to **Account Settings** → **Security** → **Two-Step Login**, and enable 2FA using an external authenticator app (e.g., Aegis, 2FAS, or Ente Auth).
4. Save your **2FA Recovery Code** offline.
5. **Lock Down Signups:**
* Return to your **Render Dashboard** → **Environment**.
* Change `SIGNUPS_ALLOWED` from `true` to **`false`**.
* Click **Save Changes**. Render will automatically redeploy the service with signups permanently closed.



---

### Step 5: Connecting Bitwarden Clients & Importing Data

#### Browser Extensions & Mobile Apps:

1. Download the official Bitwarden extension or mobile application (Android/iOS).
2. On the login screen, click the **Gear Icon ⚙️ (Settings)** at the top.
3. In the **Server URL** field, enter your full domain:
```text
[https://vaultwarden-r4ro.onrender.com](https://vaultwarden-r4ro.onrender.com)

```


4. Click **Save**, then log in using your Master Password and 2FA.

#### Importing Existing Vault Data:

1. In the Vaultwarden Web Vault, navigate to **Tools** → **Import Data**.
2. Choose your format (`Bitwarden (json)`, `Bitwarden (csv)`, `1Password`, `LastPass`, etc.).
3. Choose the export file and click **Import**.
4. **2FA / TOTP Integration:** All imported 2FA keys (`totp`) will immediately render as live, rotating 6-digit codes directly in the client apps. When logging into sites, the Bitwarden extension will automatically copy the TOTP code to your clipboard upon autofill (`Ctrl + V` to paste).

---

## 🔒 Security & Encryption Architecture

* **Zero-Knowledge Architecture:** Master Key generation and cryptographic operations occur entirely client-side using **PBKDF2** (or Argon2) and **AES-256 bit encryption**.
* **Database Security:** What resides in Neon PostgreSQL is purely encrypted ciphertext. Neither Neon, Render, nor any third party can inspect your stored passwords or notes.
* **SSL/TLS Mandatory:** Render automatically provisions Let's Encrypt TLS certificates. All HTTP traffic is force-redirected over HTTPS.

---

## 📊 Resource Usage & Storage Footprint

* **RAM Usage:** ~25 MB to 35 MB / 512 MB available on Render Free Tier.
* **Database Storage:** Credentials, URLs, notes, and 2FA seeds use compressed text formats. A typical vault with 500+ items occupies **< 2 MB** of Neon's **500 MB** free tier.
* **Compute Hours:** 24/7 continuous uptime uses 744 hours per 31-day month, well within Render's 750 free monthly compute hours.

---

## 📁 Recommended Disaster Recovery & Backups

1. **Encrypted Vault Exports:** Regularly export your vault from **Tools** → **Export Vault** as an encrypted `.json` file and back it up to secure storage.
2. **Neon Point-in-Time Recovery:** Neon retains database state history, allowing you to roll back tables or branch data from the Neon console if needed.

---

*Enjoy your fully self-hosted, private, zero-cost password & 2FA manager!*
