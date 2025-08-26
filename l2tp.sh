apt update && apt install -y xl2tpd ppp nftables
cat > /root/setup_l2tp.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# --- sanity ---
[ "$EUID" -eq 0 ] || { echo "Run as root"; exit 1; }
. /etc/os-release
case "${ID}-${VERSION_CODENAME:-unknown}" in
  debian-bullseye|debian-bookworm) ;;
  *) echo "Tested on Debian 11/12. You are: ${PRETTY_NAME}";;
esac

# --- install pkgs ---
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y xl2tpd ppp nftables

# --- backups ---
ts=$(date +%F-%H%M%S)
for f in /etc/xl2tpd/xl2tpd.conf /etc/ppp/options.xl2tpd /etc/ppp/chap-secrets /etc/nftables.conf; do
  [ -f "$f" ] && cp -a "$f" "${f}.bak-${ts}" || true
done

# --- xl2tpd.conf ---
cat > /etc/xl2tpd/xl2tpd.conf <<'CFG'
[global]
port = 1701

[lns default]
ip range = 172.16.0.10-172.16.0.19
local ip = 172.16.0.1
require authentication = yes
name = l2tpd
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
CFG

# --- PPP options поддержка PAP/CHAP/MSCHAPv2; без 'lock' ---
cat > /etc/ppp/options.xl2tpd <<'CFG'
ipcp-accept-local
ipcp-accept-remote
ms-dns 1.1.1.1
ms-dns 8.8.8.8
noccp
auth
+pap
+chap
+mschap
+mschap-v2
mtu 1400
mru 1400
proxyarp
connect-delay 5000
debug
CFG

# --- 10 клиентов ---
cat > /etc/ppp/chap-secrets <<'CFG'
# client        server   secret                   IP-addr
router01        *        "Youre password"      *
router02        *        "Youre password"          *
router03        *        "Youre password"          *
router04        *        "Youre password"          *
router05        *        "Youre password"          *
router06        *        "Youre password"          *
router07        *        "Youre password"          *
router08        *        "Youre password"          *
router09        *        "Youre password"          *
router10        *        "Youre password"          *
CFG
chown root:root /etc/ppp/chap-secrets
chmod 600 /etc/ppp/chap-secrets

# --- sysctl: форвардинг и rp_filter=2 (loose) ---
cat > /etc/sysctl.d/99-l2tp-forwarding.conf <<'CFG'
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=2
net.ipv4.conf.default.rp_filter=2
CFG
sysctl -p /etc/sysctl.d/99-l2tp-forwarding.conf >/dev/null

# --- nftables ---
SSH_PORT=$(awk 'tolower($1)=="port"{p=$2} END{print p?p:22}' /etc/ssh/sshd_config)
cat > /etc/nftables.conf <<EOF2
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    iif "lo" accept
    tcp dport ${SSH_PORT} accept
    icmp type echo-request accept
    udp dport 1701 accept
  }
  chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept
    ip saddr 172.16.0.0/24 accept
  }
}

table inet nat {
  chain postrouting {
    type nat hook postrouting priority 100; policy accept;
    oifname != "lo" ip saddr 172.16.0.0/24 masquerade
  }
}
EOF2

systemctl enable --now nftables
nft -f /etc/nftables.conf

# --- enable services ---
systemctl enable xl2tpd
systemctl restart xl2tpd

# --- summary ---
echo "OK: xl2tpd up. UDP/1701 open. NAT & forwarding enabled. SSH on port ${SSH_PORT} allowed."
echo "Users:"
awk '{if($1!~/#/ && NF>=4) printf "  %s : %s\n",$1,$3}' /etc/ppp/chap-secrets
EOF

chmod +x /root/setup_l2tp.sh
