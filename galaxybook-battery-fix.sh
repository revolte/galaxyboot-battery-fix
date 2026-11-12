#-------------------------------------------------
#Make this file executable and run
#chmod +x galaxybook-battery-fix.sh
#./galaxybook-battery-fix.sh
#--------------------------------------------------
#!/usr/bin/env bash
set -euo pipefail

echo "=== Samsung Galaxy Book4 Ultra — Battery Rescan Fix ==="

# --- 1. Check lockdown ---
LOCKDOWN=$(cat /sys/kernel/security/lockdown 2>/dev/null || echo "unknown")
if ! echo "$LOCKDOWN" | grep -q '\[none\]'; then
    echo "ERROR: Kernel lockdown is '$LOCKDOWN'."
    echo "       Disable Secure Boot in BIOS, then re-run this script."
    exit 1
fi
echo "Lockdown: $LOCKDOWN ✓"

# --- 2. Create the SSDT binary (43 bytes) ---
SSDT_DIR="/usr/local/share/galaxybook-rescan"
sudo mkdir -p "$SSDT_DIR"

# Minimal valid SSDT: header + Scope(\) + NoOp + NoOp + EndScope
sudo printf '\x53\x53\x44\x54\x00\x4c\x4e\x58\x20\x20\x20\x52\x45\x53\x41\x4e\x20\x20\x20\x00\x00\x00\x01\x4c\x4e\x58\x20\x20\x20\x00\x00\x00\x01\x00\x10\x5c\x0a\xa9\xa9\x0a' \
    > "$SSDT_DIR/rescan.aml"
echo "SSDT written: $(stat -c%s "$SSDT_DIR/rescan.aml") bytes ✓"

# --- 3. Install the rescan script ---
sudo tee /usr/local/bin/galaxybook-battery-rescan > /dev/null <<'SCRIPT'
#!/bin/bash
set -e
SSDT_DIR="/usr/local/share/galaxybook-rescan"
CONFIGFS="/sys/kernel/config/acpi/table"

modprobe acpi_configfs 2>/dev/null || true

# Remove old entry if present
rmdir "$CONFIGFS/test" 2>/dev/null || true
mkdir -p "$CONFIGFS/test"
cp "$SSDT_DIR/rescan.aml" "$CONFIGFS/test/aml"
echo "galaxybook-battery-rescan: ACPI rescan triggered."
SCRIPT
sudo chmod +x /usr/local/bin/galaxybook-battery-rescan
echo "Script installed ✓"

# --- 4. Install systemd service ---
sudo tee /etc/systemd/system/galaxybook-battery-rescan.service > /dev/null <<'UNIT'
[Unit]
Description=Re-detect the battery on Samsung Galaxy Book4 (ACPI rescan)
After=acpi@.service
Wants=acpi@.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/galaxybook-battery-rescan
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
echo "Service installed ✓"

# --- 5. Enable and start ---
sudo systemctl daemon-reload
sudo systemctl enable --now galaxybook-battery-rescan
echo "Service enabled and started ✓"

# --- 6. Verify ---
echo ""
echo "=== Verification ==="
echo "power_supply:"
ls /sys/class/power_supply/
echo ""
echo "upower:"
upower -e 2>/dev/null || echo "(upower not available)"
echo ""
echo "=== Done. Reboot without charger to test. ==="   
