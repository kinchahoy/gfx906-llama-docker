#!/usr/bin/env bash

echo "=== SYSTEM PCIe LINK MAP ==="
echo

for dev in /sys/bus/pci/devices/*; do
    # Only list devices that expose PCIe link info
    if [[ -f "$dev/current_link_speed" ]]; then
        bdf=$(basename "$dev")
        name=$(lspci -s "$bdf")

        cur_speed=$(cat "$dev/current_link_speed")
        cur_width=$(cat "$dev/current_link_width")

        max_speed=$(cat "$dev/max_link_speed")
        max_width=$(cat "$dev/max_link_width")

        echo "$name"
        echo "  BDF: $bdf"
        echo "  Current link: $cur_speed x$cur_width"
        echo "  Maximum link: $max_speed x$max_width"
        echo
    fi
done
