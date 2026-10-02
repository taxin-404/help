# Instant Firefox New Tab Setup (`start.me` Optimization)

This documentation provides a step-by-step guide to eliminate loading lag when opening custom homepage/new-tab extensions (such as **New Tab Override** paired with **start.me**) in Mozilla Firefox.

---

## 🛠️ Performance Tuning Settings (`about:config`)

These preferences enable **DNS prefetching**, **speculative connection pooling**, and **predictive resource caching** inside Firefox. This allows the browser to resolve domain names and open encrypted background connections *before* you press `Ctrl + T`.

### 1. Configuration Matrix

| Preference Key | Value | Type | Description |
| :--- | :---: | :---: | :--- |
| `network.dns.disablePrefetch` | `false` | Boolean | Pre-resolves domain names into cached IP addresses. |
| `network.http.speculative-parallel-limit` | `8` | Number | Keeps background TCP/TLS sockets open for instant connection. |
| `network.predictor.enable-prefetch` | `true` | Boolean | Pre-loads essential CSS, JS, and asset files for frequently visited pages. |

---

## 🚀 Setup Instructions

1. Open **Firefox**.
2. Type `about:config` into the address bar and press **Enter**.
3. Click **Accept the Risk and Continue**.
4. Configure each setting:

#### A. Configure DNS Prefetching
* Search for `network.dns.disablePrefetch`.
* Ensure its value is set to **`false`**.

#### B. Increase Speculative Connections
* Search for `network.http.speculative-parallel-limit`.
* Double-click the entry and change the numerical value from default (`6`) to **`8`**.

#### C. Enable Network Predictor (Create New Entry)
1. Search for `network.predictor.enable-prefetch`.
2. Select the **Boolean** radio option.
3. Click the **`+` (Plus)** icon on the right side.
4. Verify the created toggle is set to **`true`**.

---

## 📊 Technical Overview

```
[ User Presses Ctrl + T ]
           │
           ├─► Old Flow:  DNS Lookup ──► TCP/TLS Handshake ──► Fetch Assets ──► Render Page (Visible Lag)
           │
           └─► New Flow:  [DNS Cached] ─► [Sockets Ready] ───► [Assets Ready] ─► Instant Render (0ms Lag)
```

---

## ⚖️ Trade-offs & Analysis

* **Security:** 🟢 **Safe**. Operates strictly within standard web security policies (CORS, SSL/TLS).
* **Performance:** 🟢 **High Speed**. Drastically reduces page paint time.
* **Bandwidth:** 🟡 **Minimal Increase**. Background pre-fetching uses a negligible amount of extra network data.
* **Privacy:** 🟡 **Minor Consideration**. DNS queries are issued prior to user navigation.

---

## 💡 Optional Extension Setting (New Tab Override)

If you use the **New Tab Override** extension:
1. Navigate to `about:addons` $\rightarrow$ **Extensions** $\rightarrow$ **New Tab Override**.
2. Go to **Options**.
3. Enable **Cache URL contents** if available, or point the extension to a local `start.me` HTML backup for offline zero-latency rendering.
