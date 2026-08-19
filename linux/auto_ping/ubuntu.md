Wayland Input Automation Setup (Ubuntu 26+)

This guide covers setting up `ydotool` on Ubuntu 26+ (Wayland) to automate keyboard inputs. Since `xdotool` is incompatible with Wayland, `ydotool` acts as the kernel-level interface for simulating inputs.

## 1. Installation
Install the necessary package:
```bash
sudo apt update
sudo apt install ydotool

```

## 2. Daemon Configuration (System-wide)

To ensure the input daemon runs with the correct permissions, we configure it as a systemd service.

1. Create the service file:
```bash
sudo nano /etc/systemd/system/ydotoold.service

```


2. Paste the following configuration:
```ini
[Unit]
Description=ydotoold - ydotool daemon
Documentation=man:ydotoold(8)

[Service]
ExecStart=/usr/bin/ydotoold --socket-path=/tmp/.ydotool_socket --socket-own=1000:1000 --socket-perm=0600
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target

```


*(Note: Adjust `--socket-own` to your user ID if it is not 1000:1000)*.
3. Enable and start the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ydotoold

```



## 3. Environment Variable

Tell your shell where to find the socket:

```bash
echo 'export YDOTOOL_SOCKET=/tmp/.ydotool_socket' >> ~/.bashrc
source ~/.bashrc

```

## 4. Scripting for Wayland

When creating your automation scripts, use `ydotool` instead of `xdotool`.

**Script:**

```bash
#!/bin/bash

# ====== CONFIGURATION ======
STARTUP_DELAY=10                 # Delay before starting (seconds)
TOTAL_DURATION=$((5 * 60 * 60))  # Total duration
INTERVAL=1800                    # Base interval between W presses
RANDOM_VARIATION=60              # Random variation ± seconds
DELAY_BEFORE_ENTER=0.2           # Delay between key and Enter
# ============================

echo "🕒 Waiting $STARTUP_DELAY seconds before starting..."
sleep $STARTUP_DELAY

START_TIME=$(date +%s)
END_TIME=$((START_TIME + TOTAL_DURATION))

echo "▶️ Auto keypress started at $(date)"
echo "Will run for $((TOTAL_DURATION / 60)) minutes."

# Type "Start" + Enter once
ydotool type "Start"
ydotool key 28:1 28:0
notify-send "Auto Keypress" "Start sent ✅"

# Loop sending W after interval, End at the last cycle
while true; do
  CURRENT_TIME=$(date +%s)
  TIME_LEFT=$((END_TIME - CURRENT_TIME))

  if (( TIME_LEFT <= INTERVAL )); then
    # Wait remaining time then type End
    sleep $TIME_LEFT
    ydotool type "End"
    ydotool key 28:1 28:0
    notify-send "Auto Keypress" "End sent 🛑"
    break
  fi

  # Wait before pressing W for the first time and all subsequent cycles
  RANDOM_SLEEP=$((INTERVAL + RANDOM % (2 * RANDOM_VARIATION + 1) - RANDOM_VARIATION))
  sleep $RANDOM_SLEEP

  # Press W (Keycode 17) + Enter (Keycode 28)
  ydotool key 17:1 17:0
  sleep $DELAY_BEFORE_ENTER
  ydotool key 28:1 28:0
  notify-send "Auto Keypress" "W sent ✔️"
done

echo "🛑 Auto keypress ended at $(date)"
```
