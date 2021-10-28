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
  echo "cloudflared service metrics"
  echo "127.0.0.1:5432/metrics"
  se
  curl -s 127.0.0.1:5432/metrics | egrep 'cloudflared_tunnel_active_streams|cloudflared_tunnel_concurrent_requests_per_tunnel|cloudflared_tunnel_ha_connections|cloudflared_tunnel_request_errors|cloudflared_tunnel_response_by_code|cloudflared_tunnel_timer_retries|cloudflared_tunnel_total_requests|cloudflared_tunnel_tunnel_register_success|go_gc_duration_seconds|go_goroutines|go_memstats|process_cpu_seconds_total|fds|go_threads|process_resident_|process_virtual_|cloudflared_tunnel_server_locations' | egrep -v '# TYPE' | sed -e 's| HELP ||g' -e 's|#|------------------------------\n|g'

  if [ -f /var/log/cloudflared2.log ]; then
  ss
  echo "cloudflared2 service metrics"
  echo "127.0.0.1:5433/metrics"
  se
  curl -s 127.0.0.1:5433/metrics | egrep 'cloudflared_tunnel_active_streams|cloudflared_tunnel_concurrent_requests_per_tunnel|cloudflared_tunnel_ha_connections|cloudflared_tunnel_request_errors|cloudflared_tunnel_response_by_code|cloudflared_tunnel_timer_retries|cloudflared_tunnel_total_requests|cloudflared_tunnel_tunnel_register_success|go_gc_duration_seconds|go_goroutines|go_memstats|process_cpu_seconds_total|fds|go_threads|process_resident_|process_virtual_|cloudflared_tunnel_server_locations' | egrep -v '# TYPE' | sed -e 's| HELP ||g' -e 's|#|------------------------------\n|g'
  fi
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
  echo
  ss
  echo "Receive buffer sizes"
  se
  echo "sysctl net.core.rmem_max"
  sysctl net.core.rmem_max
  echo "sysctl net.core.rmem_default"
  sysctl net.core.rmem_default
  echo "sysctl net.core.wmem_max"
  sysctl net.core.wmem_max
  echo "sysctl net.core.wmem_default"
  sysctl net.core.wmem_default
  echo
  echo "netstat -sut"
  netstat -sut
  echo
  echo "netstat -su6"
  netstat -su6
  echo
  echo "netstat -plantu | egrep 'cloudflared|nginx|php'"
  netstat -plantu | egrep 'cloudflared|nginx|php'
}

tunnel_debug() {
    tunnel_name=$1
    ss
    echo "Debug Report for $(date)"

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

    if [ -f /etc/systemd/system/cloudflared2.service ]; then
      ss
      echo "cloudflared2 service"
      se
      echo "systemctl status cloudflared2"
      systemctl status cloudflared2 | sed -e "s|$(hostname)|hostname|g"
      if [ -f /etc/systemd/system/cloudflared2.service.d/openfileslimit.conf ]; then
        # systemd-delta --type=extended --no-pager | awk '/cloudflared2/ {print $4}'
        echo
        echo "cat /etc/systemd/system/cloudflared2.service.d/openfileslimit.conf"
        cat /etc/systemd/system/cloudflared2.service.d/openfileslimit.conf
      fi
    fi

    ss
    echo "Check cloudflared.service file"
    echo "/etc/systemd/system/cloudflared.service"
    se
    cat /etc/systemd/system/cloudflared.service

    if [ -f /etc/systemd/system/cloudflared2.service ]; then
      ss
      echo "Check cloudflared2.service file"
      echo "/etc/systemd/system/cloudflared2.service"
      se
      cat /etc/systemd/system/cloudflared2.service
    fi

    ss
    echo "Tunnel Info"
    echo "cloudflared tunnel info $tunnel_name"
    se
    cloudflared tunnel list -o json | jq -r --arg h $tunnel_name '.[] | select(.name == $h)'

    if [ "$tunnel_name2" ]; then
      ss
      echo "Tunnel Info"
      echo "cloudflared tunnel info $tunnel_name2"
      se
      cloudflared tunnel list -o json | jq -r --arg h $tunnel_name2 '.[] | select(.name == $h)'
    fi

    if [ -f "$TUNNEL_CONFIGFILE" ]; then
      ss
      echo "Tunnel $TUNNEL_CONFIGFILE"
      echo "cat $TUNNEL_CONFIGFILE"
      se
      cat "$TUNNEL_CONFIGFILE"
    fi

    if [ -f "$TUNNEL_CONFIGFILE2" ]; then
      ss
      echo "Tunnel $TUNNEL_CONFIGFILE2"
      echo "cat $TUNNEL_CONFIGFILE2"
      se
      cat "$TUNNEL_CONFIGFILE2"
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
    cfpids=$(pidof cloudflared)
    for n in $cfpids; do
      echo "ls -l /proc/$n/fd | wc -l"
      ls -l /proc/$n/fd | wc -l
    done

    ss
    echo "Current limits for cloudflared"
    echo "inspect /proc/\$(pidof cloudflared)/limits"
    se
    cfpids=$(pidof cloudflared)
    for n in $cfpids; do
      echo "cat /proc/$n/limits"
      cat /proc/$n/limits
    done

    ss
    echo "Open files for root"
    echo "lsof -u root | wc -l"
    se
    lsof -u root | wc -l

    ss
    echo "journalctl cloudflared-update.timer"
    echo "journalctl -u cloudflared-update.timer --no-pager | sed -e \"s|\$(hostname)|hostname|g\" | tail -${TAIL_LINES}"
    se
    journalctl -u cloudflared-update.timer --no-pager | sed -e "s|$(hostname)|hostname|g" | tail -${TAIL_LINES}

    ss
    echo "journalctl cloudflared logs"
    echo "journalctl -u cloudflared --no-pager | sed -e \"s|\$(hostname)|hostname|g\" | tail -${TAIL_LINES}"
    se
    journalctl -u cloudflared --no-pager | sed -e "s|$(hostname)|hostname|g" | tail -${TAIL_LINES}

    if [ -f /var/log/cloudflared2.log ]; then
      ss
      echo "journalctl cloudflared2 logs"
      echo "journalctl -u cloudflared2 --no-pager | sed -e \"s|\$(hostname)|hostname|g\" | tail -${TAIL_LINES}"
      se
      journalctl -u cloudflared2 --no-pager | sed -e "s|$(hostname)|hostname|g" | tail -${TAIL_LINES}
    fi

    ss
    echo "cloudflared log tail"
    echo "tail -100 /var/log/cloudflared.log | tail -${TAIL_LINES} | jq"
    se
    tail -100 /var/log/cloudflared.log | tail -${TAIL_LINES} | jq

    if [ -f /var/log/cloudflared2.log ]; then
      ss
      echo "cloudflared log tail"
      echo "tail -100 /var/log/cloudflared2.log | tail -${TAIL_LINES} | jq"
      se
      tail -100 /var/log/cloudflared2.log | tail -${TAIL_LINES} | jq
    fi

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