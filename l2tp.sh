# xl2tpd.conf
cat >/etc/xl2tpd/xl2tpd.conf <<'EOF'
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
EOF

# options.xl2tpd
cat >/etc/ppp/options.xl2tpd <<'EOF'
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
EOF

# chap-secrets (пароли в кавычках!)
cat >/etc/ppp/chap-secrets <<'EOF'
# client   server   secret                 IP-addr
router01   *        "hT9!sF7wP@lZ3q#M"     *
router02   *        "X4z!Lm8kQ@r9"         *
router03   *        "B7q$Vp2nHs1%"         *
router04   *        "T2n@Kw6dFz8#"         *
router05   *        "M9y#Gh3vLp4^"         *
router06   *        "J6f!Qr8xDn5@"         *
router07   *        "Z3k^Ty1mWc7$"         *
router08   *        "P8w%Xn2gVr6!"         *
router09   *        "C5d$Fb4hKs9@"         *
router10   *        "R1v@Nj7yLt3#"         *
EOF
chmod 600 /etc/ppp/chap-secrets

# sysctl
cat >/etc/sysctl.d/99-l2tp-forwarding.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=2
net.ipv4.conf.default.rp_filter=2
EOF
sysctl -p /etc/sysctl.d/99-l2tp-forwarding.conf >/dev/null

# nftables
SSH_PORT=$(awk 'tolower($1)=="port"{print $2}' /etc/ssh/sshd_config); [ -z "$SSH_PORT" ] && SSH_PORT=22
cat >/etc/nftables.conf <<EOF
flush ruleset
table inet filter {
  chain input { type filter hook input priority 0; policy drop;
    ct state established,related accept
    iif "lo" accept
    tcp dport ${SSH_PORT} accept
    icmp type echo-request accept
    udp dport 1701 accept
  }
  chain forward { type filter hook forward priority 0; policy drop;
    ct state established,related accept
    ip saddr 172.16.0.0/24 accept
  }
}
table inet nat {
  chain postrouting { type nat hook postrouting priority 100; policy accept;
    oifname != "lo" ip saddr 172.16.0.0/24 masquerade
  }
}
EOF
systemctl enable --now nftables
nft -f /etc/nftables.conf

# сервис
systemctl enable xl2tpd
systemctl restart xl2tpd
