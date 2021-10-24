#!/bin/bash
####################################################
# cloudflared open file debugging
####################################################
DT=$(date +"%d%m%y-%H%M%S")
TUNNEL_CONFIGFILE='/etc/cloudflared/config.yml'
TAIL_LINES='150'

SCRIPTDIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"
####################################################

if [ -f "$SCRIPTDIR/cloudflared-debug.ini" ]; then
  . "$SCRIPTDIR/cloudflared-debug.ini"
fi

ss() { echo -e "\n-------------------------------------------------"; }
se() { echo -e "-------------------------------------------------\n"; }
cfmetrics() {
  ss
  echo "cloudflared metrics"
  echo "127.0.0.1:5432/metrics"
  se
  curl -s 127.0.0.1:5432/metrics | egrep 'cloudflared_tunnel_active_streams|cloudflared_tunnel_concurrent_requests_per_tunnel|cloudflared_tunnel_ha_connections|cloudflared_tunnel_request_errors|cloudflared_tunnel_response_by_code|cloudflared_tunnel_timer_retries|cloudflared_tunnel_total_requests|cloudflared_tunnel_tunnel_register_success|go_gc_duration_seconds|go_goroutines|go_memstats|process_cpu_seconds_total|fds|go_threads|process_resident_|process_virtual_|cloudflared_tunnel_server_locations' | egrep -v '# TYPE' | sed -e 's| HELP ||g' -e 's|#|------------------------------\n|g'
}

netstat_info() {
  sshclient=$(echo $SSH_CLIENT | awk '{print $1}')
  nic=$(ifconfig -s 2>&1 | egrep -v '^Iface|^lo|^gre' | awk '{print $1}')
  bandwidth_avg=$(sar -n DEV 1 1)
  bandwidth_inout=$(echo "$nic" | while read i; do echo "$bandwidth_avg" | grep 'Average:' | awk -v tnic="$i" '$0~tnic{print tnic, "In: ",$5,"Out:",$6}'; done | column -t)
  packets_inout=$(echo "$nic" | while read i; do echo "$bandwidth_avg" | grep 'Average:' | awk -v tnic="$i" '$0~tnic{print tnic, "In: ",$3,"Out:",$3}'; done | column -t)
  netstat_http=$(netstat -anu | fgrep ':80 ')
  netstat_https=$(netstat -anu | fgrep ':443 ')
  netstat_outbound=$(netstat -plantu | egrep -v 'and|servers|Address' | awk '{print $5,$6,$7}' | grep -v ':\*' | grep -v '127.0.0.1' | sed -e "s|$sshclient|ssh-client-ip|g" | sort | uniq -c | sort -rn | head -n40 | column -t)
  netstat_ips=$(netstat -tnu)
  netstat_ipstop=$(echo "$netstat_ips" | egrep -v 'servers|Address' | awk '{print $5}' | rev | cut -d: -f2- | rev | sort | uniq -c | sort -rn | head -n40)
  netstat_ipstopf=$(echo "$netstat_ipstop" | awk '{"getent hosts " $2 | getline getent_hosts_str; split(getent_hosts_str, getent_hosts_arr, " "); print $1, $2, getent_hosts_arr[2], $3}' | sed -e "s|$sshclient|ssh-client-ip|g" | column -t)
  tt_states_http=$(echo "$netstat_http" | awk '{print $6}' | sort | uniq -c | sort -n)
  tt_states_https=$(echo "$netstat_https" | awk '{print $6}' | sort | uniq -c | sort -n)
  uniq_states_http=$(echo "$netstat_http" | fgrep -v "0.0.0.0" | awk '{print $6}' | sort | uniq -c | sort -n)
  uniq_states_https=$(echo "$netstat_https" | fgrep -v "0.0.0.0" | awk '{print $6}' | sort | uniq -c | sort -n)
  ttconn_http=$(echo "$tt_states_http" | awk '{sum += $1} END {print sum;}')
  ttconn_https=$(echo "$tt_states_https" | awk '{sum += $1} END {print sum;}')
  uniqconn_http=$(echo "$uniq_states_http" | awk '{sum += $1} END {print sum;}')
  uniqconn_https=$(echo "$uniq_states_https" | awk '{sum += $1} END {print sum;}')
  econn_http=$(echo "$tt_states_http" | awk '/ESTABLISHED/ {print $1}')
  econn_https=$(echo "$tt_states_https" | awk '/ESTABLISHED/ {print $1}')
  wconn_http=$(echo "$tt_states_http" | awk '/TIME_WAIT/ {print $1}')
  wconn_https=$(echo "$tt_states_https" | awk '/TIME_WAIT/ {print $1}')
  echo
  ss
  echo "Netstat Info:"
  echo -e "\nNetwork Bandwidth In/Out (KB/s):"
  echo "$bandwidth_inout"
  echo -e "\nNetwork Packets   In/Out (pps):"
  echo "$packets_inout"
  echo -e "\nTotal Connections For:"
  echo "Port 80:   $ttconn_http"
  echo "Port 443:  $ttconn_http"
  echo -e "\nUnique IP Connections For:"
  echo "Port 80:   $uniqconn_http"
  echo "Port 443:  $uniqconn_http"
  echo -e "\nEstablished Connections For:"
  echo "Port 80:   ${econn_http:-0}"
  echo "Port 443:  ${econn_https:-0}"
  echo -e "\nTIME_WAIT Connections For:"
  echo "Port 80:   ${wconn_http:-0}"
  echo "Port 443:  ${wconn_https:-0}"
  echo -e "\nTop IP Address Connections:"
  echo "$netstat_ipstopf"
  echo -e "\nTop Outbound Connections:"
  echo "$netstat_outbound"
}

tunnel_debug() {
    tunnel_name=$1
    ss
    echo "cloudflared service"
    se
    echo "systemctl status cloudflared"
    systemctl status cloudflared | sed -e "s|$(hostname)|hostname|g"
    if [ -f /etc/systemd/system/cloudflared.service.d/openfileslimit.conf ]; then
      # systemd-delta --type=extended --no-pager | awk '/cloudflared/ {print $4}'
      echo
      echo "cat /etc/systemd/system/cloudflared.service.d/openfileslimit.conf"
      cat /etc/systemd/system/cloudflared.service.d/openfileslimit.conf
    fi

    ss
    echo "Check cloudflared.service file"
    echo "/etc/systemd/system/cloudflared.service"
    se
    cat /etc/systemd/system/cloudflared.service

    ss
    echo "Tunnel Info"
    echo "cloudflared tunnel info $tunnel_name"
    se
    cloudflared tunnel info $tunnel_name

    if [ -f "$TUNNEL_CONFIGFILE" ]; then
      ss
      echo "Tunnel $TUNNEL_CONFIGFILE"
      echo "cat $TUNNEL_CONFIGFILE"
      se
      cat "$TUNNEL_CONFIGFILE"
    fi

    ss
    echo "nginx.conf client_* settings"
    echo "grep 'client_' /usr/local/nginx/conf/nginx.conf"
    se
    grep 'client_' /usr/local/nginx/conf/nginx.conf

    ss
    echo "nginx.conf timeout* settings"
    echo "grep 'timeout' /usr/local/nginx/conf/nginx.conf"
    se
    grep 'timeout' /usr/local/nginx/conf/nginx.conf

    ss
    echo "Open file descriptors for cloudflared"
    echo "ls -l /proc/\$(pidof cloudflared)/fd | wc -l"
    se
    ls -l /proc/$(pidof cloudflared)/fd | wc -l

    ss
    echo "Current limits for cloudflared"
    echo "cat /proc/\$(pidof cloudflared)/limits"
    se
    cat /proc/$(pidof cloudflared)/limits

    ss
    echo "Open files for root"
    echo "lsof -u root | wc -l"
    se
    lsof -u root | wc -l

    ss
    echo "journamctl cloudflared logs"
    echo "journalctl -u cloudflared --no-pager | sed -e \"s|\$(hostname)|hostname|g\" | tail -${TAIL_LINES}"
    se
    journalctl -u cloudflared --no-pager | sed -e "s|$(hostname)|hostname|g" | tail -${TAIL_LINES}

    ss
    echo "cloudflared log tail"
    echo "tail -100 /var/log/cloudflared.log | tail -${TAIL_LINES} | jq"
    se
    tail -100 /var/log/cloudflared.log | tail -${TAIL_LINES} | jq

    cfmetrics
    netstat_info
}

help() {
  echo
  echo "Usage:"
  echo
  echo "$0 debug tunnel_name"
}

case "$1" in
  debug )
    if [[ "$tunnel_name" ]]; then
      tunnel_debug "$tunnel_name"
    elif [[ ! -z "$2" ]]; then
      tunnel_debug "$2"
    else
      help
    fi
    ;;
  * )
    help
    ;;
esac