# SSH Keys: Create One and Connect to GitHub

SSH keys are the safer way to authenticate to GitHub compared to tokens. The private key is a file that never leaves your machine - GitHub only ever receives the public key, which is useless to anyone else. There is no secret string to paste into chats, screenshots, or configs, so there is nothing to leak or revoke.

---

## 1. Check if you already have a key

Look in `~/.ssh/` for an existing key pair:
```
ls -la ~/.ssh/
```
You want a pair like `id_ed25519` (private) + `id_ed25519.pub` (public). If both exist, skip to step 3.

## 2. Generate a key

```
ssh-keygen -t ed25519
```
- Press Enter to accept the default file location (`~/.ssh/id_ed25519`).
- Enter a passphrase when prompted (you can leave it empty, but a passphrase means even a stolen key file is useless without it).

This creates two files:
- `~/.ssh/id_ed25519` - the private key. **Never share this with anyone, ever.**
- `~/.ssh/id_ed25519.pub` - the public key. Safe to give to GitHub.

## 3. Add the public key to GitHub

Copy the public key to your clipboard:
```
cat ~/.ssh/id_ed25519.pub
```
Then in GitHub: **Settings → SSH and GPG keys → New SSH key** - paste the whole line and save.

## 4. Test the connection

```
ssh -T git@github.com
```
The first time, accept the host fingerprint. You should see:
```
Hi <username>! You've successfully authenticated, but GitHub does not provide shell access.
```

## 5. Switch this repo to SSH

Replace the HTTPS remote so pushes no longer need a token:
```
git remote -v                      # shows the current https:// URL
git remote set-url origin git@github.com:taxin-404/help.git
git push
```
For other repos, use your own GitHub username in the URL: `git@github.com:<username>/<repo>.git`.

## 6. ssh-agent: type the passphrase once

Without an agent, every push asks for your passphrase. With the systemd user agent it is asked once per login:

```
systemctl --user enable --now ssh-agent
```

Add to `~/.ssh/config`:
```
Host github.com
    IdentityFile ~/.ssh/id_ed25519
    AddKeysToAgent yes
```

## 7. What NOT to do

- Never paste the private key (`id_ed25519`) into a chat, email, or repo.
- Keep its permissions locked: `chmod 600 ~/.ssh/id_ed25519` (they should already be).
- If you ever think a private key leaked, generate a new one and delete the old key from GitHub.

## 8. After switching

If you had a GitHub token in use, revoke it - it no longer needs to exist: **Settings → Developer settings → Personal access tokens → Delete**.
