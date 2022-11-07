#!/usr/bin/env bash
# shellcheck disable=SC2029
# set -xe

echo_msg() {
    color_off='\033[0m' # Text Reset
    case "$1" in
    red | error | erro) color_on='\033[0;31m' ;;       # Red
    green | info) color_on='\033[0;32m' ;;             # Green
    yellow | warning | warn) color_on='\033[0;33m' ;;  # Yellow
    blue) color_on='\033[0;34m' ;;                     # Blue
    purple | question | ques) color_on='\033[0;35m' ;; # Purple
    cyan) color_on='\033[0;36m' ;;                     # Cyan
    time) color_on="[$(date +%Y%m%d-%T)], " color_off='' ;;
    step | timestep)
        color_on="\033[0;33m[$(date +%Y%m%d-%T)] step-$((STEP + 1)), \033[0m"
        color_off=
        STEP=$((STEP + 1))
        ;;
    *) color_on='' color_off='' ;;
    esac
    shift
    echo -e "${color_on}$*${color_off}"
}

peer_to_peer() {
    if [[ "$new_key_flag" -ne 1 ]]; then
        echo_msg green "\n### Please select << client >> side conf...\n"
        select c_conf in $me_data/wg*.conf quit; do
            [[ "$c_conf" == 'quit' ]] && exit 1
            break
        done
        c_key_pub="$(awk '/^### pubkey:/ {print $3}' "$c_conf" | head -n 1)"
        c_key_pre="$(awk '/PresharedKey/ {print $4}' "$c_conf" | head -n 1)"
        c_ip_pub="$(awk '/^### pubip:/ {print $3}' "$c_conf" | head -n 1)"
        c_ip_pri="$(awk '/^Address/ {print $3}' "$c_conf" | head -n 1)"
        c_ip_pri="${c_ip_pri%/24}"
        c_port="$(awk '/^ListenPort/ {print $3}' "$c_conf" | head -n 1)"
    fi
    ## select server
    echo_msg red "\n### Please select ====< server >==== side conf...\n"
    select s_conf in $me_data/wg*.conf quit; do
        [[ "$s_conf" == 'quit' ]] && break
        echo_msg red "selected file is $s_conf"
        s_key_pub="$(awk '/^### pubkey:/ {print $3}' "$s_conf" | head -n 1)"
        s_ip_pub="$(awk '/^### pubip:/ {print $3}' "$s_conf" | head -n 1)"
        s_ip_pri="$(awk '/^Address/ {print $3}' "$s_conf" | head -n 1)"
        s_ip_pri=${s_ip_pri%/24}
        s_port="$(awk '/^ListenPort/ {print $3}' "$s_conf" | head -n 1)"
        echo "from $s_conf to $c_conf..."
        if ! grep -q "### ${s_conf##*/} begin" "$c_conf"; then
            (
                echo ""
                echo "### ${s_conf##*/} begin"
                echo "[Peer]"
                echo "PublicKey = $s_key_pub"
                echo "# PresharedKey = $c_key_pre"
                echo "endpoint = $s_ip_pub:$s_port"
                if [[ "${s_ip_pri}" == '10.9.0.27' ]]; then
                    echo "AllowedIPs = ${s_ip_pri}/32, 192.168.1.0/24"
                else
                    echo "AllowedIPs = ${s_ip_pri}/32"
                fi
                echo "PersistentKeepalive = 60"
                echo "### ${s_conf##*/} end"
                echo ""
            ) >>"$c_conf"
        fi
        echo "from $c_conf to $s_conf..."
        if ! grep -q "### ${c_conf##*/} begin" "$s_conf"; then
            (
                echo ""
                echo "### ${c_conf##*/} begin  $c_comment"
                echo "[Peer]"
                echo "PublicKey = $c_key_pub"
                echo "# PresharedKey = $c_key_pre"
                echo "AllowedIPs = ${c_ip_pri}/32"
                echo "### ${c_conf##*/} end"
                echo ""
            ) >>"$s_conf"
        fi
    done
}

new_key() {
    c_num="${1:-31}"
    c_conf="$me_data/wg${c_num}.conf"
    until [[ "${c_num}" -lt 254 ]]; do
        read -rp "Error! enter ip again [1-254]: " c_num
        c_conf="$me_data/wg${c_num}.conf"
    done
    while [ -f "$c_conf" ]; do
        c_num=$((c_num + 1))
        c_conf="$me_data/wg${c_num}.conf"
    done
    echo_msg green "IP: 10.9.0.$c_num, filename: $c_conf"
    read -rp "Who use this file? (username or hostname): " -e -i "client$c_num" c_comment
    read -rp 'Enter public ip (empty for client behind NAT): ' -e -i "wg${c_num}.vpn.com" c_ip_pub
    c_ip_pri="10.9.0.${c_num}"
    c_port="$((c_num + 39000))"
    c_key_pri="$(wg genkey)"
    c_key_pub="$(echo "$c_key_pri" | wg pubkey)"
    c_key_pre="$(wg genpsk)"
    (
        echo ""
        echo "### ${c_conf##*/} $c_comment"
        echo "[Interface]"
        echo "PrivateKey = $c_key_pri"
        echo "### PresharedKey = $c_key_pre"
        echo "### pubkey: $c_key_pub"
        echo "### pubip: $c_ip_pub"
        echo "Address = $c_ip_pri/24"
        echo "ListenPort = $c_port"
        echo "## DNS = 192.168.1.1, 8.8.8.8, 8.8.4.4, 114.114.114.114"
        echo "## MTU = 1420"
        echo "## PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
        echo "## PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE"
        echo ""
    ) >"$c_conf"
    new_key_flag=1
    peer_to_peer
}

gen_qrcode() {
    if ! command -v qrencode; then
        if uname -s | grep -q Linux; then
            sudo apt install qrencode
        elif uname -s | grep -q Darwin; then
            brew install qrencode
        else
            echo "qrencode not exists"
        fi
    fi
    select conf in $me_data/wg*.conf quit; do
        [[ "${conf}" == 'quit' ]] && break
        [[ -f "${conf}" ]] || break
        echo_msg green "${conf}.png"
        qrencode -o "${conf}.png" -t PNG <"$conf"
    done
}

revoke_client() {
    echo_msg green "Please select client conf (revoke it)."
    select conf in $me_data/wg*.conf quit; do
        [[ "$conf" == 'quit' ]] && break
        echo_msg green "selected $conf"
        sed -i "/^### ${conf##*/} begin/,/^### ${conf##*/} end/d" $me_data/wg*.conf
        rm -f "$conf"
        echo_msg red "revoke $conf done."
        break
    done
}

restart_wg_server() {
    echo_msg red "Please select sever conf."
    select conf in $me_data/wg*.conf quit; do
        [[ "${conf}" == 'quit' ]] && break
        echo_msg red "selected $conf"
        select svr in $(awk 'NR>1' "$HOME/.ssh/config"* | awk '/^Host/ {print $2}') quit; do
            [[ "${svr}" == 'quit' ]] && break
            echo "scp $conf"
            scp "${conf}" root@"$svr":/etc/wireguard/wg0.conf
            # echo "systemctl restart wg-quick@wg0"
            # ssh root@"$svr" "systemctl restart wg-quick@wg0"
            echo "systemctl reload wg-quick@wg0"
            ssh root@"$svr" "wg syncconf wg0 <(wg-quick strip wg0)"
            break
        done
        break
    done
}

restart_wg_client() {
    select conf in $me_data/wg*.conf quit; do
        [[ "${conf}" == 'quit' ]] && break
        read -rp "Enter client ip: " ip_client
        scp "${conf}" root@"$ip_client":/etc/wireguard/wg0.conf
        echo "systemctl reload wg-quick@wg0"
        ssh root@"$ip_client" "wg syncconf wg0 <(wg-quick strip wg0)"
    done
}

# wg genkey | tee privatekey | wg pubkey > publickey; cat privatekey publickey; rm privatekey publickey

main() {
    me_path="$(dirname "$(readlink -f "$0")")"
    me_name="$(basename "$0")"
    me_data="${me_path}/data"
    me_log="${me_data}/${me_name}.log"
    [ -d "$me_data" ] || mkdir -p "$me_data"
    exec &> >(tee -a "$me_log")

    echo "
What do you want to do?
    1) New key (client or server)
    2) Exist client to server
    3) Revoke client conf
    4) Copy conf to server and reload it
    5) Generate qrcode
    6) Exit
    "
    until [[ ${MENU_OPTION} =~ ^[1-6]$ ]]; do
        read -rp "Select an option [1-5]: " MENU_OPTION
    done
    case "${MENU_OPTION}" in
    1)
        new_key "$@"
        ;;
    2)
        peer_to_peer
        ;;
    3)
        revoke_client
        ;;
    4)
        restart_wg_server
        ;;
    5)
        gen_qrcode
        ;;
    *)
        exit 0
        ;;
    esac
}

main "$@"
