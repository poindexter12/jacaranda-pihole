#!/bin/bash
# Configure iptables firewall rules for Pi-hole macvlan container network segmentation
#
# Network Policy:
# - DNS (53/tcp, 53/udp): Only accessible on container's trusted IP (192.168.1.x)
# - Web UI (80/tcp, 443/tcp): Only accessible on container's management IP (192.168.5.x)
# - All other traffic: Allowed
#
# Arguments:
#   $1 - trusted_ip (e.g., 192.168.1.20)
#   $2 - management_ip (e.g., 192.168.5.20)
#   $3 - transfer_ip (e.g., 192.168.11.20)

set -e

if [ $# -ne 3 ]; then
    echo "Usage: $0 <trusted_ip> <management_ip> <transfer_ip>"
    echo "Example: $0 192.168.1.20 192.168.5.20 192.168.11.20"
    exit 1
fi

TRUSTED_IP="$1"
MGMT_IP="$2"
TRANSFER_IP="$3"

echo "Configuring iptables rules for Pi-hole macvlan containers..."
echo "  Trusted IP:    $TRUSTED_IP (DNS allowed)"
echo "  Management IP: $MGMT_IP (Web UI allowed)"
echo "  Transfer IP:   $TRANSFER_IP (Gravity Sync)"
echo ""

# Create custom chain for Pi-hole rules
iptables -N PIHOLE-FILTER 2>/dev/null || iptables -F PIHOLE-FILTER

# Flush existing rules in our chain
iptables -F PIHOLE-FILTER

# DNS Rules: Block port 53 to management and transfer IPs
iptables -A PIHOLE-FILTER -d "$MGMT_IP" -p tcp --dport 53 -j REJECT --reject-with tcp-reset -m comment --comment "Block DNS on management IP"
iptables -A PIHOLE-FILTER -d "$MGMT_IP" -p udp --dport 53 -j REJECT --reject-with icmp-port-unreachable -m comment --comment "Block DNS on management IP"
iptables -A PIHOLE-FILTER -d "$TRANSFER_IP" -p tcp --dport 53 -j REJECT --reject-with tcp-reset -m comment --comment "Block DNS on transfer IP"
iptables -A PIHOLE-FILTER -d "$TRANSFER_IP" -p udp --dport 53 -j REJECT --reject-with icmp-port-unreachable -m comment --comment "Block DNS on transfer IP"

# Web UI Rules: Block ports 80/443 to trusted and transfer IPs
iptables -A PIHOLE-FILTER -d "$TRUSTED_IP" -p tcp --dport 80 -j REJECT --reject-with tcp-reset -m comment --comment "Block HTTP on trusted IP"
iptables -A PIHOLE-FILTER -d "$TRUSTED_IP" -p tcp --dport 443 -j REJECT --reject-with tcp-reset -m comment --comment "Block HTTPS on trusted IP"
iptables -A PIHOLE-FILTER -d "$TRANSFER_IP" -p tcp --dport 80 -j REJECT --reject-with tcp-reset -m comment --comment "Block HTTP on transfer IP"
iptables -A PIHOLE-FILTER -d "$TRANSFER_IP" -p tcp --dport 443 -j REJECT --reject-with tcp-reset -m comment --comment "Block HTTPS on transfer IP"

# Accept all other traffic
iptables -A PIHOLE-FILTER -j ACCEPT

# Insert jump to our chain at the beginning of FORWARD chain (for routed traffic to containers)
# Remove any existing jump first
iptables -D FORWARD -j PIHOLE-FILTER 2>/dev/null || true
iptables -I FORWARD 1 -j PIHOLE-FILTER

# NOTE: We do NOT apply this to INPUT chain
# The VM host and containers may share IPs (192.168.5.20 for both host and container)
# INPUT chain affects traffic to the host itself (SSH, etc.)
# FORWARD chain affects traffic being routed to containers (what we want to filter)

echo ""
echo "iptables configuration complete!"
echo ""
echo "Active PIHOLE-FILTER rules:"
iptables -L PIHOLE-FILTER -n -v --line-numbers

echo ""
echo "Network access policy:"
echo "  DNS (53):        Only on $TRUSTED_IP (trusted network)"
echo "  Web UI (80/443): Only on $MGMT_IP (management network)"
echo "  Transfer:        $TRANSFER_IP (Gravity Sync, no restrictions)"
echo ""
echo "NOTE: These rules are NOT persistent. Add to /etc/rc.local or use iptables-persistent to survive reboots."
