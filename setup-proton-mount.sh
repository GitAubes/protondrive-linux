#!/bin/bash

set -e  # Exit on any error

# Configuration
REMOTE_NAME="proton"
MOUNT_POINT="$HOME/ProtonDrive"
SYSTEMD_UNIT="$HOME/.config/systemd/user/rclone-proton.mount.service"
RCLONE_BIN="/usr/local/bin/rclone"
LOG_DIR="$HOME/.cache/rclone"
LOG_FILE="$LOG_DIR/rclone-proton.log"

echo "=========================================="
echo "🔧 Proton Drive Setup Script"
echo "=========================================="
echo ""

# Step 1: Ensure required directories
echo "[1/4] Creating mount point and log directory..."
mkdir -p "$MOUNT_POINT" "$LOG_DIR" "$HOME/.config/systemd/user"
chmod 700 "$LOG_DIR"  # Secure log directory
echo "[✓] Directories created and secured"
echo ""

# Step 2: Write systemd unit
echo "[2/4] Writing systemd user unit..."
cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=Mount Proton Drive via rclone
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStartPre=/bin/sh -c 'findmnt -rn $MOUNT_POINT >/dev/null && fusermount3 -u $MOUNT_POINT || true'
ExecStart=$RCLONE_BIN mount $REMOTE_NAME: $MOUNT_POINT \\
    --vfs-cache-mode writes \\
    --vfs-cache-max-size 500M \\
    --vfs-cache-max-age 1h \\
    --dir-cache-time 12h \\
    --poll-interval 1m \\
    --log-level INFO \\
    --log-file $LOG_FILE \\
    --umask 002 \\
    --allow-other
ExecStop=/bin/fusermount3 -u $MOUNT_POINT
ExecStopPost=/bin/sh -c 'findmnt -rn $MOUNT_POINT >/dev/null && umount -l $MOUNT_POINT || true'
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF
chmod 644 "$SYSTEMD_UNIT"
echo "[✓] Systemd unit written"
echo ""

# Step 3: Enable allow-other (if not already)
echo "[3/4] SUDO1: Configuring FUSE permissions..."
if ! grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
    echo "  → Adding 'user_allow_other' to /etc/fuse.conf"
    sudo sh -c 'echo "user_allow_other" >> /etc/fuse.conf'
    echo "[✓] FUSE configured"
else
    echo "[✓] FUSE already configured"
fi
echo ""

# Step 4: Add user to fuse group if not already
echo "[4/4] SUDO2: Adding user to 'fuse' group..."
if ! groups | grep -qw fuse; then
    echo "  → User not in fuse group, adding..."
    sudo usermod -aG fuse "$USER"
    echo "[!] ⚠️  IMPORTANT: You must LOG OUT and LOG BACK IN for group changes to apply!"
    echo "[!] Then verify with: groups | grep fuse"
else
    echo "[✓] User already in fuse group"
fi
echo ""

# Step 5: Reload and start service
echo "[✓] Enabling and starting rclone mount via systemd..."
systemctl --user daemon-reexec
systemctl --user daemon-reload
systemctl --user enable --now rclone-proton.mount.service 2>&1 || {
    echo ""
    echo "[!] Service failed to start. This may be normal if you just added to fuse group."
    echo "[!] After logging back in, verify with:"
    echo "    systemctl --user status rclone-proton.mount.service"
    exit 0
}

echo ""
echo "=========================================="
echo "[✓] Setup Complete!"
echo "=========================================="
echo ""
echo "📍 Mount point: $MOUNT_POINT"
echo ""
echo "🔄 Next steps:"
echo "   1. If you added the fuse group, LOG OUT and LOG BACK IN"
echo "   2. Verify mount with: ls ~/ProtonDrive"
echo "   3. Check status: systemctl --user status rclone-proton.mount.service"
echo ""
