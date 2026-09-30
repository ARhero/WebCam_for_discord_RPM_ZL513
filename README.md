# Infinix Zerobook 13 (Intel IPU6) Webcam Fix for Discord & Linux Desktop

This guide and script resolve the non-functioning built-in webcam issue on the **Infinix Zerobook 13** (and other Intel IPU6 / OV02C10 laptops) running **Fedora Linux** (40, 41, 42, 43, 44+) with **Secure Boot ENABLED**.

---

## Why This Problem Happens

1. **Intel IPU6 & libcamera Architecture:**
   * The laptop uses an Intel IPU6 imaging processor with an OmniVision OV02C10 sensor (`ov02c10 1-0036`).
   * The `/dev/video0` through `/dev/video31` devices created by the kernel are raw hardware capture/subdev nodes that do not output demosaiced/debayered image frames.
   * Frame processing is handled in userspace by `libcamera` (Software ISP) and exposed through **PipeWire** as `"Built-in Front Camera"`.
   * Web browsers (Chrome, Chromium, Firefox) support the PipeWire camera portal directly, which is why the webcam works in a browser.

2. **Discord / Electron Limitation:**
   * Discord is an Electron app. Its WebRTC media engine only enumerates traditional **V4L2** (`/dev/video*`) capture devices.
   * Because Discord cannot see PipeWire cameras directly, it only detected the 32 raw `ipu6` nodes, producing a black/unusable screen.

3. **Secure Boot Module Rejection:**
   * To bridge PipeWire to V4L2, we need the `v4l2loopback` kernel module.
   * On Fedora with Secure Boot enabled, the kernel enforces lockdown mode and rejects any module not signed by a key enrolled in the UEFI **Machine Owner Key (MOK)** database (`Key was rejected by service`).
   * If `akmods` builds `kmod-v4l2loopback` before the MOK key is enrolled, it packages an unsigned module. Subsequent `akmods --force` calls skip rebuilding because the package is marked as already installed.

---

## Complete Step-by-Step Solution

### Phase 1: Machine Owner Key (MOK) Enrollment (One-time UEFI setup)

> **Note:** If you have already enrolled your MOK key previously, skip directly to **Phase 2**.

Secure Boot requires kernel modules built locally by `akmods` to be signed by a key that your laptop's UEFI firmware trusts.

#### 1. Generate the local signing keypair (if not already present):
```bash
sudo kmodgenca
```
This creates:
* Public key: `/etc/pki/akmods/certs/public_key.der`
* Private key: `/etc/pki/akmods/private/private_key.priv`

#### 2. Import the public key into the UEFI MOK database:
```bash
sudo mokutil --import /etc/pki/akmods/certs/public_key.der
```
* You will be prompted to enter a **password** (e.g. `12345678`).
* Choose a simple password you will remember; you will only enter it once during the next reboot.

#### 3. Reboot the laptop:
```bash
sudo reboot
```

#### 4. Complete enrollment in the blue UEFI MokManager screen:
When your laptop restarts, a blue screen titled **"Perform MOK management"** will appear:
1. Press any key to enter the menu.
2. Select **Enroll MOK**.
3. Select **Continue**.
4. When asked *"Enroll the key(s)?"*, select **Yes**.
5. Enter the password you created in step 2.
6. Select **Reboot**.

---

### Phase 2: Automated Discord Camera Setup

Once booted back into Fedora:

1. Download or copy `setup-infinix-discord-webcam.sh` to your home folder.
2. Make it executable and run it:
   ```bash
   chmod +x setup-infinix-discord-webcam.sh
   ./setup-infinix-discord-webcam.sh
   ```

#### What the script does automatically:
1. Verifies that your MOK key is active and trusted by the kernel keyring.
2. Rebuilds and cryptographically signs `v4l2loopback` with your enrolled MOK key using `akmods --rebuild`.
3. Creates `/etc/modprobe.d/v4l2loopback.conf` with `exclusive_caps=1` and `card_label="Built-in Front Camera"`.
4. Creates `/etc/modules-load.d/v4l2loopback.conf` so `/dev/video32` loads on every boot.
5. Configures device permissions (adds user to `video` and `render` groups) and installs `/etc/udev/rules.d/60-libcamera-ipu6.rules` so WirePlumber can access the camera media nodes at boot time without permission errors.
6. Configures an **on-demand** `systemd` user service (`~/.config/systemd/user/v4l2-relayd.service`) using `v4l2-relayd` with splash pre-buffering. **The camera sensor and privacy LED remain completely OFF** until Discord or another application actively requests video, and turn OFF immediately when done.

---

### Phase 3: Selecting the Camera in Discord

1. Open **Discord**.
2. Go to **User Settings** (gear icon at bottom left) → **Voice & Video**.
3. Scroll down to **Video Settings**.
4. In the **Camera** dropdown, select **"Built-in Front Camera"** (platform:v4l2loopback-032).
5. Click **Test Video** — your live camera feed will appear immediately!

*(Discord will remember this setting across restarts).*

---

### Useful Commands & Troubleshooting

* **Check Secure Boot & Module Signature:**
  ```bash
  mokutil --sb-state
  modinfo -F signer v4l2loopback
  ```

* **Check the Virtual Video Device:**
  ```bash
  v4l2-ctl -d /dev/video32 -D
  ```

* **Check Relay Service Status:**
  ```bash
  systemctl --user status v4l2-relayd.service
  ```

* **To Restart the Relay Service:**
  ```bash
  systemctl --user restart v4l2-relayd.service
  ```

* **To Completely Uninstall and Revert Changes:**
  ```bash
  ./setup-infinix-discord-webcam.sh --uninstall
  ```
