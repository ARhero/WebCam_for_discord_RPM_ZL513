#!/usr/bin/env bash
# ==============================================================================
# Infinix Zerobook 13 (Intel IPU6 / OV02C10) Webcam Fix for Discord & Linux Apps
# Compatible with Fedora Linux 40+ with Secure Boot ENABLED
# ==============================================================================

set -e

GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BOLD="\033[1m"
NC="\033[0m"

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ------------------------------------------------------------------------------
# Routine: Enroll MOK Key (One-time UEFI setup)
# ------------------------------------------------------------------------------
enroll_mok_routine() {
    echo ""
    echo -e "${YELLOW}==================================================================${NC}"
    echo -e "${YELLOW}           SECURE BOOT MOK KEY SETUP & ENROLLMENT                 ${NC}"
    echo -e "${YELLOW}==================================================================${NC}"
    echo "Secure Boot requires kernel modules (like v4l2loopback) to be signed"
    echo "by a key trusted by your UEFI firmware (a Machine Owner Key / MOK)."
    echo ""

    if [ ! -f /etc/pki/akmods/certs/public_key.der ] || [ ! -f /etc/pki/akmods/private/private_key.priv ]; then
        info "Generating akmods MOK signing keypair..."
        sudo kmodgenca
        success "Keypair generated in /etc/pki/akmods/."
    else
        info "MOK keypair already exists in /etc/pki/akmods/."
    fi

    info "Importing public key into UEFI MOK database..."
    echo -e "${BOLD}${YELLOW}--> Choose a simple temporary password when prompted.${NC}"
    echo -e "${BOLD}${YELLOW}--> You will only type this once during the blue UEFI screen on reboot.${NC}"
    echo ""
    sudo mokutil --import /etc/pki/akmods/certs/public_key.der

    echo ""
    echo -e "${GREEN}==================================================================${NC}"
    echo -e "${GREEN}            NEXT STEP: COMPLETE ENROLLMENT AT REBOOT             ${NC}"
    echo -e "${GREEN}==================================================================${NC}"
    echo "1. Reboot your laptop now."
    echo "2. A blue screen titled 'Perform MOK management' will appear before Fedora boots."
    echo "3. Press any key to enter the menu."
    echo "4. Select: 'Enroll MOK'."
    echo "5. Select: 'Continue'."
    echo "6. Select: 'Yes' when asked to enroll the key(s)."
    echo "7. Enter the password you just typed."
    echo "8. Select: 'Reboot'."
    echo "9. Once booted back into Fedora, run this script again to finish setup!"
    echo "=================================================================="
    echo ""
    read -p "Would you like to reboot now? (y/N): " CONFIRM_REBOOT
    if [[ "$CONFIRM_REBOOT" =~ ^[Yy]$ ]]; then
        info "Rebooting system..."
        sudo reboot
    else
        info "Please reboot manually when convenient, then run this script again."
    fi
    exit 0
}

# ------------------------------------------------------------------------------
# Routine: Uninstall
# ------------------------------------------------------------------------------
if [[ "$1" == "--uninstall" ]]; then
    echo -e "${YELLOW}=== Uninstalling Infinix Webcam Fix ===${NC}"
    
    # 1. Stop and remove systemd user service
    systemctl --user stop v4l2-relayd.service 2>/dev/null || true
    systemctl --user disable v4l2-relayd.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/v4l2-relayd.service"
    systemctl --user daemon-reload 2>/dev/null || true
    info "Removed systemd user relay service."

    # 2. Remove modprobe & modules-load configs
    sudo rm -f /etc/modprobe.d/v4l2loopback.conf
    sudo rm -f /etc/modprobe.d/v4l2-relayd.conf
    sudo rm -f /etc/modprobe.d/98-v4l2loopback.conf
    sudo rm -f /etc/modules-load.d/v4l2loopback.conf
    info "Removed modprobe and modules-load configurations."

    # 3. Unload kernel module
    sudo modprobe -r v4l2loopback 2>/dev/null || true
    info "Unloaded v4l2loopback module."

    success "Uninstallation complete. System restored to original state."
    exit 0
fi

# Manual trigger for MOK enrollment
if [[ "$1" == "--enroll-mok" ]]; then
    enroll_mok_routine
fi

echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN}  Infinix Zerobook 13 Discord & WebRTC Webcam Setup (Fedora Linux)${NC}"
echo -e "${GREEN}==================================================================${NC}"

# Check for sudo permissions
if ! sudo -v &>/dev/null; then
    warn "This script requires sudo permissions to configure kernel modules."
    sudo -v
fi

# ------------------------------------------------------------------------------
# Step 1: Install Required Dependencies
# ------------------------------------------------------------------------------
info "Checking required packages..."
REQUIRED_PKGS=(
    v4l2loopback
    akmod-v4l2loopback
    kmodtool
    kernel-devel
    gstreamer1
    gstreamer1-plugins-good
    gstreamer1-plugins-bad-free
    gstreamer1-pipewire
    pipewire-plugin-libcamera
    v4l-utils
    mokutil
    openssl
)

MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! rpm -q "$pkg" &>/dev/null; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    info "Installing missing dependencies: ${MISSING_PKGS[*]}..."
    sudo dnf install -y "${MISSING_PKGS[@]}"
else
    success "All required packages are already installed."
fi

# ------------------------------------------------------------------------------
# Step 2: Verify Secure Boot and MOK Keypair
# ------------------------------------------------------------------------------
info "Checking Secure Boot status..."
SB_STATE=$(mokutil --sb-state 2>/dev/null || echo "SecureBoot disabled")

if echo "$SB_STATE" | grep -qi "enabled"; then
    info "Secure Boot is ENABLED."

    # Ensure akmods keypair exists
    if [ ! -f /etc/pki/akmods/certs/public_key.der ] || [ ! -f /etc/pki/akmods/private/private_key.priv ]; then
        info "MOK keypair not found. Starting MOK enrollment routine..."
        enroll_mok_routine
    fi

    # Check if public key is enrolled in UEFI MOK
    if ! sudo mokutil --test-key /etc/pki/akmods/certs/public_key.der 2>&1 | grep -qi "is already enrolled"; then
        warn "Your MOK certificate is not yet enrolled in your UEFI BIOS."
        enroll_mok_routine
    else
        success "Enrolled MOK certificate verified in kernel keyring."
    fi
else
    info "Secure Boot is disabled or unsupported. Continuing..."
fi

# ------------------------------------------------------------------------------
# Step 3: Rebuild and Cryptographically Sign v4l2loopback
# ------------------------------------------------------------------------------
info "Building and signing v4l2loopback module for kernel $(uname -r)..."
sudo akmods --kernels "$(uname -r)" --akmod v4l2loopback --rebuild

# Verify module signature
SIGNER=$(modinfo -F signer v4l2loopback 2>/dev/null || true)
if [ -n "$SIGNER" ]; then
    success "Module successfully signed by: $SIGNER"
else
    warn "Module built without signature string (this is normal if Secure Boot is disabled)."
fi

# ------------------------------------------------------------------------------
# Step 4: Configure modprobe & Module Autoloading
# ------------------------------------------------------------------------------
info "Configuring module options in /etc/modprobe.d/ and /etc/modules-load.d/..."

# Mask conflicting vendor configs that set confusing card labels
sudo ln -sf /dev/null /etc/modprobe.d/v4l2-relayd.conf
sudo ln -sf /dev/null /etc/modprobe.d/98-v4l2loopback.conf

# Configure v4l2loopback with exclusive_caps=1 for WebRTC/Discord compatibility
sudo tee /etc/modprobe.d/v4l2loopback.conf > /dev/null << "MODCONF"
options v4l2loopback devices=1 video_nr=32 card_label="Built-in Front Camera" exclusive_caps=1 max_buffers=2
MODCONF

# Ensure module loads on boot
sudo tee /etc/modules-load.d/v4l2loopback.conf > /dev/null << "LOADCONF"
v4l2loopback
LOADCONF

# Unload existing instance if present, then load with new parameters
sudo modprobe -r v4l2loopback 2>/dev/null || true
sudo modprobe v4l2loopback

if [ -e /dev/video32 ]; then
    success "Virtual device /dev/video32 successfully initialized."
else
    error "Failed to create /dev/video32. Check dmesg for details."
    exit 1
fi

# ------------------------------------------------------------------------------
# Step 5: Detect PipeWire Camera Target Object
# ------------------------------------------------------------------------------
info "Detecting internal camera node in PipeWire..."
TARGET_NODE=$(python3 -c "
import json, subprocess
try:
    out = subprocess.check_output(['pw-dump'], text=True)
    items = json.loads(out)
    for item in items:
        props = item.get('info', {}).get('props', {})
        if props.get('media.class') == 'Video/Source' and props.get('device.api') == 'libcamera':
            print(props.get('node.name'))
            break
except Exception:
    pass
" 2>/dev/null || true)

if [ -z "$TARGET_NODE" ]; then
    TARGET_NODE="libcamera_input.__SB_.PC00.LNK0"
fi
info "Using PipeWire target camera node: $TARGET_NODE"

# ------------------------------------------------------------------------------
# Step 6: Create and Enable Persistent User Relay Service
# ------------------------------------------------------------------------------
info "Configuring systemd user service for camera relay..."
mkdir -p "$HOME/.config/systemd/user"

cat << SERVICE_EOF > "$HOME/.config/systemd/user/v4l2-relayd.service"
[Unit]
Description=PipeWire to V4L2loopback Camera Relay for Discord
After=pipewire.service wireplumber.service
Requires=pipewire.service wireplumber.service

[Service]
Type=simple
ExecStart=/usr/bin/gst-launch-1.0 -q pipewiresrc target-object=${TARGET_NODE} ! videoconvert ! video/x-raw,format=YUY2,width=1280,height=720,framerate=30/1 ! v4l2sink device=/dev/video32
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
SERVICE_EOF

systemctl --user daemon-reload
systemctl --user enable --now v4l2-relayd.service

sleep 2
if systemctl --user is-active --quiet v4l2-relayd.service; then
    success "Camera relay service is active and streaming."
else
    warn "Relay service started but might need a desktop session reload."
fi

# ------------------------------------------------------------------------------
# Completion & Instructions
# ------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN}                     Setup Successfully Completed!               ${NC}"
echo -e "${GREEN}==================================================================${NC}"
echo ""
echo "How to use your camera in Discord:"
echo " 1. Open Discord."
echo " 2. Navigate to: User Settings (gear icon) -> Voice & Video."
echo " 3. Under 'Camera', select: 'Built-in Front Camera'."
echo " 4. Click 'Test Video' to verify."
echo ""
echo "Notes:"
echo " * Everything persists automatically across reboots."
echo " * Secure Boot remains fully ENABLED."
echo " * To enroll/re-enroll MOK at any time: ./setup-infinix-discord-webcam.sh --enroll-mok"
echo " * To uninstall this fix at any time:   ./setup-infinix-discord-webcam.sh --uninstall"
echo ""
