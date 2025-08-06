#!/bin/bash
#
# ==================================================================================
#
#   Advanced Tunnel Manager for FRP & Chisel (Final Edition - Multi-Port/Multi-Tunnel)
#   Original Concept: Ali Tabari
#   Enhanced Version: 7.3.2 (With Intelligent Service Restart)
#   Supported Protocols: TCP, KCP, QUIC, WSS
#   GitHub: https://github.com/your-repo/tunnel-manager
#
# ==================================================================================

# --- Static Configuration Variables ---
FRP_VERSION="0.62.1"
CHISEL_VERSION="1.10.1"
FRP_INSTALL_DIR="/opt/frp"
CHISEL_INSTALL_DIR="/opt/chisel"
SYSTEMD_DIR="/etc/systemd/system"

# --- Default Ports ---
FRP_PUBLIC_TCP_PORT=7000
FRP_INTERNAL_TCP_PORT=7005
DEFAULT_FRP_KCP_PORT=7001
DEFAULT_FRP_QUIC_PORT=7002
DEFAULT_FRP_DASHBOARD_PORT=7500
DEFAULT_FRP_WSS_NGINX_PORT=443
DEFAULT_CHISEL_PORT=8080

# --- Color Codes ---
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'; PURPLE='\033[1;35m'; CYAN='\033[1;36m'; WHITE='\033[1;37m'; BLACK='\033[1;30m';
BG_RED='\033[41m'; BG_GREEN='\033[42m'; BG_YELLOW='\033[43m'; BG_BLUE='\033[44m'; BG_PURPLE='\033[45m'; BG_CYAN='\033[46m';
BOLD='\033[1m'; NC='\033[0m';

# ==================================================================================
# SECTION: UI AND HELPER FUNCTIONS
# ==================================================================================

print_message() { local color=$1; local message=$2; echo -e "${color}${message}${NC}"; }
print_header() {
    clear
    echo -e "${BLUE}"
    echo "██████╗ ██████╗  ██████╗      ████████╗██╗   ██╗███╗   ██╗███╗   ██╗███████╗██╗     "
    echo "██╔══██╗██╔══██╗██╔═══██╗     ╚══██╔══╝██║   ██║████╗  ██║████╗  ██║██╔════╝██║     "
    echo "██████╔╝██████╔╝██║   ██║        ██║   ██║   ██║██╔██╗ ██║██╔██╗ ██║█████╗  ██║     "
    echo "██╔═══╝ ██╔══██╗██║   ██║        ██║   ██║   ██║██║╚██╗██║██║╚██╗██║██╔══╝  ██║     "
    echo "██║     ██║  ██║╚██████╔╝        ██║   ╚██████╔╝██║ ╚████║██║ ╚████║███████╗███████╗"
    echo "╚═╝     ╚═╝  ╚═╝ ╚═════╝         ╚═╝    ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝╚══════╝╚══════╝"
    echo -e "${PURPLE}                                      v7.3.2 (With Intelligent Service Restart)${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════════════════${NC}\n"
}
print_section() { local title=$1; echo ""; echo -e "${BG_BLUE}${WHITE}${BOLD} $title ${NC}"; echo -e "${YELLOW}────────────────────────────────────────────────────────────────────────${NC}"; }
check_root() { if [ "$(id -u)" != "0" ]; then print_message "$RED" "⚠️  This script must be run as root"; exit 1; fi; }
detect_arch() { local arch=$(uname -m); case $arch in x86_64) echo "amd64";; aarch64) echo "arm64";; armv7l) echo "arm";; *) print_message "$RED" "⚠️  Unsupported arch: $arch"; exit 1;; esac; }
get_ip() { local ip=$(curl -s https://api.ipify.org); [ -z "$ip" ] && ip="Unknown"; echo $ip; }

check_installation() {
    frp_installed=false; frps_active=false; frpc_active=false
    chisel_installed=false; chisel_server_active=false; chisel_client_active=false
    certbot_installed=false; nginx_installed=false; nginx_active=false
    [ -f "${FRP_INSTALL_DIR}/frps" ] && frp_installed=true
    systemctl is-active --quiet frps.service &> /dev/null && frps_active=true
    systemctl is-active --quiet frpc.service &> /dev/null && frpc_active=true
    [ -f "${CHISEL_INSTALL_DIR}/chisel" ] && chisel_installed=true
    systemctl is-active --quiet chisel-server.service &> /dev/null && chisel_server_active=true
    systemctl is-active --quiet chisel-client.service &> /dev/null && chisel_client_active=true
    command -v certbot &> /dev/null && certbot_installed=true
    command -v nginx &> /dev/null && nginx_installed=true
    systemctl is-active --quiet nginx.service &> /dev/null && nginx_active=true
}

display_status() {
    local ip=$(get_ip); local arch=$(detect_arch); local hostname=$(hostname)
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║ ${YELLOW}${BOLD}SYSTEM INFORMATION${NC}                                           ${GREEN}║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    printf "${GREEN}║${NC} ${CYAN}IP Address:${NC} %-50s${GREEN}║${NC}\n" "$ip"; printf "${GREEN}║${NC} ${CYAN}Architecture:${NC} %-47s${GREEN}║${NC}\n" "$arch"; printf "${GREEN}║${NC} ${CYAN}Hostname:${NC} %-50s${GREEN}║${NC}\n" "$hostname"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║ ${YELLOW}${BOLD}SERVICE STATUS${NC}                                                  ${GREEN}║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    if $frp_installed; then
        if $frps_active; then printf "${GREEN}║${NC} ${CYAN}FRP Server:${NC} [ ${GREEN}✅ ACTIVE${NC} ]%-41s${GREEN}║${NC}\n" ""; fi
        if $frpc_active; then printf "${GREEN}║${NC} ${CYAN}FRP Client:${NC} [ ${GREEN}✅ ACTIVE${NC} ]%-41s${GREEN}║${NC}\n" ""; fi
    else printf "${GREEN}║${NC} ${CYAN}FRP:${NC} [ ${RED}❌ NOT INSTALLED${NC} ]%-40s${GREEN}║${NC}\n" ""; fi
    if $chisel_installed; then
        if $chisel_server_active; then printf "${GREEN}║${NC} ${CYAN}Chisel Server:${NC} [ ${GREEN}✅ ACTIVE${NC} ]%-36s${GREEN}║${NC}\n" ""; fi
        if $chisel_client_active; then printf "${GREEN}║${NC} ${CYAN}Chisel Client:${NC} [ ${GREEN}✅ ACTIVE${NC} ]%-36s${GREEN}║${NC}\n" ""; fi
    else printf "${GREEN}║${NC} ${CYAN}Chisel:${NC} [ ${RED}❌ NOT INSTALLED${NC} ]%-42s${GREEN}║${NC}\n" ""; fi
    if $nginx_installed && $nginx_active; then printf "${GREEN}║${NC} ${CYAN}Nginx Proxy:${NC} [ ${GREEN}✅ ACTIVE${NC} ]%-38s${GREEN}║${NC}\n" ""; fi
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}\n"
}

# ==================================================================================
# SECTION: INSTALLATION
# ==================================================================================

install_frp() {
    print_section "INSTALLING FRP v${FRP_VERSION}"
    mkdir -p ${FRP_INSTALL_DIR}
    local arch_name=$(detect_arch)
    
    if ! wget -q --show-progress -O frp.tar.gz "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${arch_name}.tar.gz"; then
        print_message "$RED" "Download failed."
        return 1
    fi
    
    if ! tar -xzf frp.tar.gz -C ${FRP_INSTALL_DIR} --strip-components=1; then
        print_message "$RED" "Extraction failed."
        rm -f frp.tar.gz
        return 1
    fi
    
    rm -f frp.tar.gz
    chmod +x ${FRP_INSTALL_DIR}/frps ${FRP_INSTALL_DIR}/frpc
    print_message "$GREEN" "✅ FRP installed successfully."
}

install_chisel() {
    print_section "INSTALLING CHISEL v${CHISEL_VERSION}"
    mkdir -p ${CHISEL_INSTALL_DIR}
    local arch_name=$(detect_arch)
    
    if ! wget -q --show-progress -O chisel.gz "https://github.com/jpillora/chisel/releases/download/v${CHISEL_VERSION}/chisel_${CHISEL_VERSION}_linux_${arch_name}.gz"; then
        print_message "$RED" "Download failed."
        return 1
    fi
    
    if ! gunzip chisel.gz; then
        print_message "$RED" "Extraction failed."
        rm -f chisel.gz
        return 1
    fi
    
    mv chisel ${CHISEL_INSTALL_DIR}
    chmod +x ${CHISEL_INSTALL_DIR}/chisel
    print_message "$GREEN" "✅ Chisel installed successfully."
}

install_certbot() {
    print_section "INSTALLING CERTBOT"
    
    if ! command -v snap &> /dev/null; then
        print_message "$YELLOW" "Installing snapd..."
        apt-get update -y >/dev/null 2>&1
        if ! apt-get install -y snapd >/dev/null 2>&1; then
            print_message "$RED" "Snap install failed."
            return 1
        fi
    fi
    
    snap install core >/dev/null 2>&1
    snap refresh core >/dev/null 2>&1
    
    if ! snap install --classic certbot >/dev/null 2>&1; then
        print_message "$RED" "Certbot install failed."
        return 1
    fi
    
    ln -s /snap/bin/certbot /usr/bin/certbot 2>/dev/null
    print_message "$GREEN" "✅ Certbot installed successfully."
}

obtain_ssl_certificate() {
    local domain=$1
    local email=$2
    local cert_dir=$3
    
    print_message "$BLUE" "🔑 Obtaining SSL certificate for $domain..."
    
    local certbot_command
    if systemctl is-active --quiet nginx && grep -qr "well-known/acme-challenge" /etc/nginx/sites-enabled/ /etc/nginx/sites-available/ 2>/dev/null; then
        print_message "$YELLOW" "  -> Nginx is active. Using webroot method."
        mkdir -p /var/www/html
        certbot_command="certbot certonly --webroot -w /var/www/html --non-interactive --agree-tos --email ${email} -d ${domain}"
    else
        print_message "$YELLOW" "  -> Using standalone method."
        systemctl stop nginx 2>/dev/null
        systemctl stop apache2 2>/dev/null
        certbot_command="certbot certonly --standalone --non-interactive --agree-tos --email ${email} -d ${domain}"
    fi
    
    if ! eval $certbot_command; then
        print_message "$RED" "❌ Failed to obtain SSL certificate."
        systemctl start nginx 2>/dev/null
        return 1
    fi
    
    systemctl start nginx 2>/dev/null
    print_message "$GREEN" "✅ SSL certificate obtained successfully."
    
    if [ -n "$cert_dir" ]; then
        mkdir -p "$cert_dir"
        cp "/etc/letsencrypt/live/$domain/fullchain.pem" "$cert_dir/server.crt"
        cp "/etc/letsencrypt/live/$domain/privkey.pem" "$cert_dir/server.key"
        chmod 644 "$cert_dir/server.crt"
        chmod 600 "$cert_dir/server.key"
    fi
    
    return 0
}

# ==================================================================================
# SECTION: CONFIGURATION
# ==================================================================================

configure_frp_server() {
    print_section "CONFIGURING FRP SERVER"
    
    read -p "Enter auth token (press Enter for random): " token
    [ -z "$token" ] && token=$(head -c 16 /dev/urandom | base64)
    
    local use_tcp=false use_kcp=false use_quic=false use_wss=false
    echo
    print_message "$YELLOW" "Which protocols to enable? (e.g., 1,4 or 5 for all)"
    echo "  1) TCP  2) KCP  3) QUIC  4) WSS (via Nginx)  5) All"
    read -p "Choice(s): " p_choice
    
    if [[ "$p_choice" == *"1"* || "$p_choice" == *"5"* ]]; then use_tcp=true; fi
    if [[ "$p_choice" == *"2"* || "$p_choice" == *"5"* ]]; then use_kcp=true; fi
    if [[ "$p_choice" == *"3"* || "$p_choice" == *"5"* ]]; then use_quic=true; fi
    if [[ "$p_choice" == *"4"* || "$p_choice" == *"5"* ]]; then use_wss=true; fi

    if ! command -v nginx &>/dev/null; then
        print_message "$YELLOW" "Nginx not found, attempting to install..."
        apt-get update -y
        if ! apt-get install -y nginx; then
            print_message "$RED" "Nginx installation failed."
            return 1
        fi
    fi
    
    if [ ! -d "/etc/nginx/sites-available" ]; then
        print_message "$RED" "Nginx install failed: config directory not found."
        return 1
    fi
    
    print_message "$YELLOW" "\n--- Application Tunnel Port Range ---"
    print_message "$CYAN" "Enter the range of ports that clients can request on the server."
    read -p "Allowed Port Range (e.g., 20000-21000): " allowed_ports_range
    
    if ! [[ "$allowed_ports_range" =~ ^[0-9]+-[0-9]+$ ]]; then
        print_message "$RED" "Invalid port range format. Use format like 20000-21000."
        return 1
    fi
    
    local domain_name=""
    if $use_wss; then
        if ! command -v certbot &>/dev/null; then
            install_certbot || return 1
        fi
        
        read -p "Enter your domain for WSS (e.g., frp.yourdomain.com): " domain_name
        read -p "Enter your email for SSL: " email_address
        
        if [ -z "$domain_name" ] || [ -z "$email_address" ]; then
            print_message "$RED" "Domain and Email are required for WSS."
            return 1
        fi
        
        cat > /etc/nginx/sites-available/frp-proxy << EOF
server {
    listen 80;
    server_name ${domain_name};
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF
        
        rm -f /etc/nginx/sites-enabled/default
        ln -s -f /etc/nginx/sites-available/frp-proxy /etc/nginx/sites-enabled/frp-proxy
        systemctl restart nginx
        
        obtain_ssl_certificate "$domain_name" "$email_address" "" || return 1
    fi
    
    cat > ${FRP_INSTALL_DIR}/frps.ini << EOF
[common]
token = ${token}
dashboard_addr = 127.0.0.1
dashboard_port = ${DEFAULT_FRP_DASHBOARD_PORT}
dashboard_user = admin
dashboard_pwd = ${token}
bind_addr = 0.0.0.0
bind_port = ${FRP_INTERNAL_TCP_PORT}
kcp_bind_port = ${DEFAULT_FRP_KCP_PORT}
quic_bind_port = ${DEFAULT_FRP_QUIC_PORT}
allow_ports = ${allowed_ports_range}
EOF

    print_message "$BLUE" "\nConfiguring Nginx as the public-facing proxy..."
    local stream_config_file="/etc/nginx/frp_stream.conf"
    
    echo "stream {" > ${stream_config_file}
    if $use_tcp || $use_wss; then
        echo "    server { listen ${FRP_PUBLIC_TCP_PORT}; proxy_pass 127.0.0.1:${FRP_INTERNAL_TCP_PORT}; }" >> ${stream_config_file}
    fi
    if $use_kcp; then
        echo "    server { listen ${DEFAULT_FRP_KCP_PORT} udp; proxy_pass 127.0.0.1:${DEFAULT_FRP_KCP_PORT}; }" >> ${stream_config_file}
    fi
    if $use_quic; then
        echo "    server { listen ${DEFAULT_FRP_QUIC_PORT} udp; proxy_pass 127.0.0.1:${DEFAULT_FRP_QUIC_PORT}; }" >> ${stream_config_file}
    fi
    echo "}" >> ${stream_config_file}
    
    if ! grep -q "include /etc/nginx/frp_stream.conf;" /etc/nginx/nginx.conf; then
        echo -e "\ninclude /etc/nginx/frp_stream.conf;" >> /etc/nginx/nginx.conf
    fi

    if $use_wss; then
        cat >> /etc/nginx/sites-available/frp-proxy << EOF
server {
    listen ${DEFAULT_FRP_WSS_NGINX_PORT} ssl http2;
    server_name ${domain_name};
    
    ssl_certificate /etc/letsencrypt/live/${domain_name}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain_name}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    
    location / {
        proxy_pass http://127.0.0.1:${FRP_INTERNAL_TCP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
        
        if [ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]; then
            curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > /etc/letsencrypt/options-ssl-nginx.conf
        fi
        
        if [ ! -f /etc/letsencrypt/ssl-dhparams.pem ]; then
            openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048 >/dev/null 2>&1
        fi
    fi

    cat > ${SYSTEMD_DIR}/frps.service << EOF
[Unit]
Description=FRP (Fast Reverse Proxy) Server
After=network.target
Requires=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
StartLimitInterval=60
StartLimitBurst=3
ExecStart=/opt/frp/frps -c /opt/frp/frps.ini
LimitNOFILE=4096
KillSignal=SIGQUIT
TimeoutStopSec=5
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable frps.service
    
    if ! nginx -t; then
        print_message "$RED" "Nginx config error."
        return 1
    fi
    
    systemctl restart nginx
    systemctl restart frps.service
    
    if command -v ufw &>/dev/null; then
        local ufw_port_range=$(echo "$allowed_ports_range" | sed 's/-/:/')
        ufw allow ${ufw_port_range}/tcp
        ufw allow ${ufw_port_range}/udp
        ufw allow ${FRP_PUBLIC_TCP_PORT}/tcp
        ufw allow ${DEFAULT_FRP_KCP_PORT}/udp
        ufw allow ${DEFAULT_FRP_QUIC_PORT}/udp
        
        if $use_wss; then
            ufw allow 80/tcp
            ufw allow 443/tcp
        fi
        
        ufw reload
    fi
    
    print_message "$GREEN" "\n✅ FRP Server setup complete."
    print_message "$CYAN" "--- IMPORTANT: CLIENT CONFIGURATION ---"
    print_message "$YELLOW" "On your client, you can use any 'remote_port' within the range: ${YELLOW}${BOLD}${allowed_ports_range}${NC}"
    print_message "$YELLOW" "Auth Token: ${token}"
}

configure_frp_client() {
    print_section "CONFIGURING FRP CLIENT"
    
    read -p "Enter server address (IP or domain): " server_addr
    read -p "Enter auth token: " token
    
    if [ -z "$server_addr" ] || [ -z "$token" ]; then
        print_message "$RED" "Input cannot be empty."
        return 1
    fi
    
    echo
    print_message "$YELLOW" "Select the SINGLE protocol this client should use to connect:"
    echo "  1) TCP  2) KCP  3) QUIC  4) WSS"
    read -p "Choice [1-4]: " p_choice

    print_message "$YELLOW" "\n--- Tunnel Port Configuration ---"
    read -p "Enter the X-UI PANEL port on this server to PREVENT it from being tunneled (optional): " panel_port
    
    cat > ${FRP_INSTALL_DIR}/frpc.ini << EOF
[common]
server_addr = ${server_addr}
token = ${token}
login_fail_exit = false
EOF

    case $p_choice in
        2)
            echo "server_port = ${DEFAULT_FRP_KCP_PORT}" >> ${FRP_INSTALL_DIR}/frpc.ini
            echo "protocol = kcp" >> ${FRP_INSTALL_DIR}/frpc.ini
            ;;
        3)
            echo "server_port = ${DEFAULT_FRP_QUIC_PORT}" >> ${FRP_INSTALL_DIR}/frpc.ini
            echo "protocol = quic" >> ${FRP_INSTALL_DIR}/frpc.ini
            ;;
        4)
            read -p "Please re-enter server DOMAIN for WSS: " wss_domain
            if [ -z "$wss_domain" ]; then
                print_message "$RED" "Domain is required."
                return 1
            fi
            sed -i "s/server_addr = .*/server_addr = ${wss_domain}/" ${FRP_INSTALL_DIR}/frpc.ini
            echo "server_port = ${DEFAULT_FRP_WSS_NGINX_PORT}" >> ${FRP_INSTALL_DIR}/frpc.ini
            echo "protocol = wss" >> ${FRP_INSTALL_DIR}/frpc.ini
            echo "tls_enable = true" >> ${FRP_INSTALL_DIR}/frpc.ini
            echo "server_name = ${wss_domain}" >> ${FRP_INSTALL_DIR}/frpc.ini
            ;;
        *)
            echo "server_port = ${FRP_PUBLIC_TCP_PORT}" >> ${FRP_INSTALL_DIR}/frpc.ini
            echo "protocol = tcp" >> ${FRP_INSTALL_DIR}/frpc.ini
            ;;
    esac

    while true; do
        print_message "$CYAN" "\n--- Adding a New Tunnel ---"
        read -p "Enter LOCAL Port (or press Enter to finish): " local_port

        if [ -z "$local_port" ]; then
            break
        fi

        read -p "Enter REMOTE Port for '${local_port}': " remote_port

        if ! [[ "$local_port" =~ ^[0-9]+$ && "$remote_port" =~ ^[0-9]+$ ]]; then
            print_message "$RED" "Invalid port(s). Please try again."
            continue
        fi
        
        if [[ -n "$panel_port" && ("$local_port" == "$panel_port" || "$remote_port" == "$panel_port") ]]; then
            print_message "$RED" "Error: Tunnel port cannot be the same as the panel port! Please try again."
            continue
        fi

        cat >> ${FRP_INSTALL_DIR}/frpc.ini << EOF

[app_tcp_${local_port}_to_${remote_port}]
type = tcp
local_ip = 127.0.0.1
local_port = ${local_port}
remote_port = ${remote_port}

[app_udp_${local_port}_to_${remote_port}]
type = udp
local_ip = 127.0.0.1
local_port = ${local_port}
remote_port = ${remote_port}
EOF
        print_message "$GREEN" "✅ Tunnel ${local_port} -> ${remote_port} added."
    done
    
    sed -i 's/\r$//' ${FRP_INSTALL_DIR}/frpc.ini
    
    cat > ${SYSTEMD_DIR}/frpc.service << EOF
[Unit]
Description=FRP Client
After=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=/opt/frp/frpc -c /opt/frp/frpc.ini

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable frpc.service
    systemctl restart frpc.service
    
    print_message "$GREEN" "\n✅ FRP Client configured with all tunnels."
}

configure_chisel_server() {
    print_section "CONFIGURING CHISEL SERVER"
    
    read -p "Enter auth user: " auth_user
    read -p "Enter auth pass: " auth_pass
    
    read -p "Enter server port (default ${DEFAULT_CHISEL_PORT}): " server_port
    server_port=${server_port:-${DEFAULT_CHISEL_PORT}}
    
    read -p "Use HTTPS? (y/n): " use_https
    
    local chisel_cmd="/opt/chisel/chisel server --host 0.0.0.0 -p $server_port --auth ${auth_user}:${auth_pass} --reverse --keepalive 25s"
    
    if [[ "$use_https" =~ ^[Yy]$ ]]; then
        read -p "Enter domain for SSL: " domain_name
        read -p "Enter email for SSL: " email_address
        
        if [ -z "$domain_name" ] || [ -z "$email_address" ]; then
            print_message "$RED" "Inputs cannot be empty."
            return 1
        fi
        
        if ! $certbot_installed; then
            install_certbot || return 1
        fi
        
        obtain_ssl_certificate "$domain_name" "$email_address" "${CHISEL_INSTALL_DIR}/certs" || return 1
        
        chisel_cmd="$chisel_cmd --tls-key ${CHISEL_INSTALL_DIR}/certs/server.key --tls-cert ${CHISEL_INSTALL_DIR}/certs/server.crt"
    fi
    
    cat > ${SYSTEMD_DIR}/chisel-server.service << EOF
[Unit]
Description=Chisel Server
After=network.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=10s
ExecStart=$chisel_cmd

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable chisel-server.service
    systemctl restart chisel-server.service
    
    if command -v ufw &>/dev/null; then
        ufw allow ${server_port}/tcp
        ufw reload
    fi
    
    print_message "$GREEN" "✅ Chisel Server configured."
    print_message "$YELLOW" "Auth: ${auth_user}:${auth_pass}"
    print_message "$YELLOW" "Port: ${server_port}"
    if [[ "$use_https" =~ ^[Yy]$ ]]; then
        print_message "$YELLOW" "HTTPS Enabled with domain: ${domain_name}"
    else
        print_message "$YELLOW" "Using HTTP (not secure)"
    fi
}

configure_chisel_client() {
    print_section "CONFIGURING CHISEL CLIENT"
    
    read -p "Enter server address (domain or IP): " server_address
    read -p "Enter server port: " server_port
    read -p "Enter auth user: " auth_user
    read -p "Enter auth pass: " auth_pass
    
    read -p "Use HTTPS? (y/n): " use_https
    
    read -p "Enter REMOTE port to open on server: " remote_port
    read -p "Enter LOCAL port to forward from this machine: " local_port
    
    local schema="http"
    local tls_flags=""
    
    if [[ "$use_https" =~ ^[Yy]$ ]]; then
        schema="https"
        tls_flags="--tls-skip-verify"
    fi
    
    local chisel_cmd="/opt/chisel/chisel client --auth ${auth_user}:${auth_pass} --keepalive 25s ${tls_flags} ${schema}://${server_address}:${server_port} R:${remote_port}:127.0.0.1:${local_port}"
    
    cat > ${SYSTEMD_DIR}/chisel-client.service << EOF
[Unit]
Description=Chisel Client
After=network.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=10s
ExecStart=$chisel_cmd

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable chisel-client.service
    systemctl restart chisel-client.service
    
    print_message "$GREEN" "✅ Chisel Client configured."
    print_message "$YELLOW" "Forwarding: remote:${remote_port} -> local:${local_port}"
}

# ==================================================================================
# SECTION: WRAPPERS & MANAGEMENT
# ==================================================================================

setup_iran_server_frp() {
    if ! $frp_installed; then
        install_frp || return
    fi
    configure_frp_server
}

setup_foreign_server_frp() {
    if ! $frp_installed; then
        install_frp || return
    fi
    configure_frp_client
}

setup_iran_server_chisel() {
    if ! $chisel_installed; then
        install_chisel || return
    fi
    configure_chisel_server
}

setup_foreign_server_chisel() {
    if ! $chisel_installed; then
        install_chisel || return
    fi
    configure_chisel_client
}

uninstall_frp() {
    print_section "UNINSTALLING FRP"
    
    read -p "Are you sure? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    systemctl stop frps.service 2>/dev/null
    systemctl disable frps.service 2>/dev/null
    systemctl stop frpc.service 2>/dev/null
    systemctl disable frpc.service 2>/dev/null
    
    rm -f ${SYSTEMD_DIR}/frps.service
    rm -f ${SYSTEMD_DIR}/frpc.service
    
    read -p "Remove Nginx and its configs for FRP? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl stop nginx 2>/dev/null
        apt-get purge -y nginx nginx-common
        rm -f /etc/nginx/sites-available/frp-proxy
        rm -f /etc/nginx/sites-enabled/frp-proxy
        rm -f /etc/nginx/frp_stream.conf
    fi
    
    systemctl daemon-reload
    rm -rf ${FRP_INSTALL_DIR}
    
    print_message "$GREEN" "✅ FRP Uninstalled."
}

uninstall_chisel() {
    print_section "UNINSTALLING CHISEL"
    
    read -p "Are you sure? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    systemctl stop chisel-server.service 2>/dev/null
    systemctl disable chisel-server.service 2>/dev/null
    systemctl stop chisel-client.service 2>/dev/null
    systemctl disable chisel-client.service 2>/dev/null
    
    rm -f ${SYSTEMD_DIR}/chisel-server.service
    rm -f ${SYSTEMD_DIR}/chisel-client.service
    
    systemctl daemon-reload
    rm -rf ${CHISEL_INSTALL_DIR}
    
    print_message "$GREEN" "✅ Chisel Uninstalled."
}

manage_services() {
    while true; do
        print_header
        print_section "SERVICE MANAGEMENT"
        
        echo "  1) Restart FRP Server     5) Stop FRP Server"
        echo "  2) Restart FRP Client     6) Stop FRP Client"
        echo "  3) Restart Chisel Server  7) Stop Chisel Server"
        echo "  4) Restart Chisel Client  8) Stop Chisel Client"
        echo "  9) Restart Nginx          10) Back to Main Menu"
        
        read -p "Choice [1-10]: " choice
        
        case $choice in
            1) systemctl restart frps.service;;
            2) systemctl restart frpc.service;;
            3) systemctl restart chisel-server.service;;
            4) systemctl restart chisel-client.service;;
            5) systemctl stop frps.service;;
            6) systemctl stop frpc.service;;
            7) systemctl stop chisel-server.service;;
            8) systemctl stop chisel-client.service;;
            9) systemctl restart nginx.service;;
            10) return;;
            *) print_message "$RED" "Invalid.";;
        esac
        
        print_message "$GREEN" "Command executed."
        sleep 1
    done
}

view_logs() {
    while true; do
        print_header
        print_section "LOG VIEWER"
        
        echo "  1) FRP Server   3) Chisel Server   5) Nginx"
        echo "  2) FRP Client   4) Chisel Client   6) Back to Main Menu"
        
        read -p "Choice [1-6]: " choice
        
        clear
        
        case $choice in
            1) journalctl -u frps.service -n 50 --no-pager;;
            2) journalctl -u frpc.service -n 50 --no-pager;;
            3) journalctl -u chisel-server.service -n 50 --no-pager;;
            4) journalctl -u chisel-client.service -n 50 --no-pager;;
            5) journalctl -u nginx.service -n 50 --no-pager;;
            6) return;;
            *) print_message "$RED" "Invalid."; sleep 1; continue;;
        esac
        
        read -p "Press Enter to return..."
    done
}

# ==================================================================================
# SECTION: SERVER UTILITIES
# ==================================================================================

setup_service_restart_cron() {
    print_section "SETUP AUTOMATIC TUNNEL RESTART"

    local restart_commands=""
    if systemctl is-active --quiet frps.service; then
        restart_commands+="systemctl restart frps.service; "
    fi
    if systemctl is-active --quiet frpc.service; then
        restart_commands+="systemctl restart frpc.service; "
    fi
    if systemctl is-active --quiet chisel-server.service; then
        restart_commands+="systemctl restart chisel-server.service; "
    fi
    if systemctl is-active --quiet chisel-client.service; then
        restart_commands+="systemctl restart chisel-client.service; "
    fi

    if [ -z "$restart_commands" ]; then
        print_message "$RED" "No active FRP or Chisel services found to schedule a restart for."
        return
    fi
    
    local systemctl_path=$(command -v systemctl)
    if [ -z "$systemctl_path" ]; then
        print_message "$RED" "Could not find systemctl command. Cannot create cronjob."
        return
    fi
    
    restart_commands=$(echo "$restart_commands" | sed "s|systemctl|$systemctl_path|g")
    
    print_message "$CYAN" "The following services will be scheduled for automatic restart:"
    local services_to_restart=$(echo "$restart_commands" | sed "s|$systemctl_path restart ||g" | sed "s|;||g")
    print_message "$YELLOW" "-> ${services_to_restart}"

    print_message "$YELLOW" "\nSelect a schedule for the automatic restart:"
    echo "  1) Every 1 Hour"
    echo "  2) Every 2 Hours"
    echo "  3) Every 6 Hours"
    echo "  4) Every 12 Hours"
    echo "  5) Remove Existing Schedule"
    echo "  6) Cancel"
    read -p "Enter choice [1-6]: " choice

    local cron_comment="#ManagedByTunnelScript-ServiceRestart"
    (crontab -l 2>/dev/null | grep -v "$cron_comment") | crontab -

    local cron_entry=""
    case $choice in
        1) cron_entry="0 * * * * ${restart_commands} ${cron_comment}";;
        2) cron_entry="0 */2 * * * ${restart_commands} ${cron_comment}";;
        3) cron_entry="0 */6 * * * ${restart_commands} ${cron_comment}";;
        4) cron_entry="0 */12 * * * ${restart_commands} ${cron_comment}";;
        5) print_message "$GREEN" "✅ Automatic service restart schedule removed."; return;;
        6) print_message "$YELLOW" "Operation cancelled."; return;;
        *) print_message "$RED" "Invalid option."; return;;
    esac

    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
    print_message "$GREEN" "✅ Automatic tunnel restart scheduled successfully."
}

add_inbound_port() {
    print_section "OPEN INBOUND FIREWALL PORT"
    read -p "Enter the port number to open: " port
    if ! [[ "$port" =~ ^[0-9]+$ && "$port" -gt 0 && "$port" -lt 65536 ]]; then
        print_message "$RED" "Invalid port number."
        return
    fi

    read -p "Enter the protocol (tcp/udp): " protocol
    protocol=$(echo "$protocol" | tr '[:upper:]' '[:lower:]')
    if [[ "$protocol" != "tcp" && "$protocol" != "udp" ]]; then
        print_message "$RED" "Invalid protocol. Please enter 'tcp' or 'udp'."
        return
    fi

    if command -v ufw &>/dev/null; then
        print_message "$BLUE" "UFW firewall detected. Opening port..."
        ufw allow "${port}/${protocol}"
        ufw reload
        print_message "$GREEN" "✅ Port ${port}/${protocol} opened successfully in UFW."
    elif systemctl is-active --quiet firewalld; then
        print_message "$BLUE" "Firewalld detected. Opening port..."
        firewall-cmd --permanent --add-port="${port}/${protocol}" >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        print_message "$GREEN" "✅ Port ${port}/${protocol} opened successfully in Firewalld."
    else
        print_message "$YELLOW" "⚠️ No supported firewall (UFW or Firewalld) was found."
        print_message "$CYAN" "Please open port ${port}/${protocol} manually."
    fi
}

server_utilities_menu() {
    while true; do
        print_header
        print_section "SERVER UTILITIES"
        echo "  1) Setup Automatic Tunnel Restart (Cronjob)"
        echo "  2) Open New Inbound Port"
        echo "  3) Back to Main Menu"

        read -p "Choice [1-3]: " choice
        
        case $choice in
            1) setup_service_restart_cron; break;;
            2) add_inbound_port; break;;
            3) return;;
            *) print_message "$RED" "Invalid option.";;
        esac
    done
}

# ==================================================================================
# SECTION: MAIN EXECUTION
# ==================================================================================

main() {
    check_root
    
    while true; do
        print_header
        check_installation
        display_status
        
        echo -e "${YELLOW}${BOLD}MAIN MENU:${NC}"
        echo -e "  ${WHITE}${BG_BLUE} 1 ${NC} Setup Iran Server (FRP)"
        echo -e "  ${WHITE}${BG_BLUE} 2 ${NC} Setup Foreign Server (FRP)"
        echo -e "  ${WHITE}${BG_PURPLE} 3 ${NC} Setup Iran Server (Chisel)"
        echo -e "  ${WHITE}${BG_PURPLE} 4 ${NC} Setup Foreign Server (Chisel)"
        echo -e "  ${WHITE}${BG_GREEN} 5 ${NC} Manage Services"
        echo -e "  ${WHITE}${BG_CYAN} 6 ${NC} View Logs"
        echo -e "  ${WHITE}${BG_YELLOW} 7 ${NC} Server Utilities"
        echo -e "  ${WHITE}${BG_RED} 8 ${NC} Uninstall FRP"
        echo -e "  ${WHITE}${BG_RED} 9 ${NC} Uninstall Chisel"
        echo -e "  ${WHITE}${BG_BLACK} 10 ${NC} Exit"
        
        read -p "Enter your choice [1-10]: " choice
        
        case $choice in
            1) setup_iran_server_frp;;
            2) setup_foreign_server_frp;;
            3) setup_iran_server_chisel;;
            4) setup_foreign_server_chisel;;
            5) manage_services;;
            6) view_logs;;
            7) server_utilities_menu;;
            8) uninstall_frp;;
            9) uninstall_chisel;;
            10) print_message "$GREEN" "Goodbye!"; exit 0;;
            *) print_message "$RED" "Invalid option.";;
        esac
        
        read -p "Press Enter to return to menu..."
    done
}

main
