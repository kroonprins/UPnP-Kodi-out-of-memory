#!/bin/bash

function start_rygel {
  echo "Starting rygel..."
  rygel_pid=$(pidof rygel)
  if [[ $rygel_pid -gt 0 ]]; then
    echo "   Rygel is already running (pid: ${rygel_pid})"
  else
    rygel >/dev/null 2>&1 &
    rygel_pid=$!
    sleep 5
    echo  "   Rygel started (pid: ${rygel_pid})"
  fi
  RYGEL_PID=$rygel_pid
}

function stop_rygel {
  kill -TERM $RYGEL_PID;
}

function get_kodi_ip {
  echo  "Searching for Kodi..."
  while [[ -z $kodi_ip ]]; do

     # ip ping local network
     nmap -sn 192.168.1.100-109 >/dev/null

     # use arp to get mac address of everything pinged by nmap and filter Raspberry Pi IP
     kodi_mac_address_file=$here/raspberry_mac
     if [[ ! -f $kodi_mac_address_file ]]; then
       echo
       echo "ERROR: make sure there is a file called raspberry_mac in directory ${here} containing the mac address of the device running Kodi" 1>&2
       exit 4
     fi
     kodi_mac_address=$(cat $here/raspberry_mac)
     if [[ -z $kodi_mac_address ]]; then
       echo
       echo "ERROR: make sure there that the file ${kodi_mac_address_file} contains the mac address of the device on which Kodi is running" 1>&2
       exit 5
     fi
     kodi_ip=$(arp -an | grep -i $kodi_mac_address | sed 's/.*\(192.168.1.10[0-9]\).*/\1/')
     if [[ -n $kodi_ip ]]; then
        break;
     fi

     sleep 2
     echo "   Trying again..."
  done
  echo "   Kodi found (ip: ${kodi_ip})"
  KODI_IP=$kodi_ip
}

function kodi_rpc_output {
  local output_file=$1
  local request=$2
  wget -O "$output_file" -q ''"${KODI_RPC_URL}${request}"''
}

function kodi_rpc_no_output {
  local request=$1
  kodi_rpc_output "/dev/null" "$request"
}

function connect_kodi_to_rygel {
  echo "Connecting Kodi to Rygel..."
  kodi_rpc_no_output '{"jsonrpc":"2.0","id":1,"method":"Player.Open","params":{"item":{"file":"upnp://cc33bae4-2480-42cc-a48b-bcd1817efa96/mypulseaudiosink/"}}}'
  echo "   Connection established"
}

function kodi_monitor_free_memory {
  while true; do
    kodi_rpc_output $TMP_WGET_FILE '{"jsonrpc":"2.0","id":1,"method":"XBMC.GetInfoLabels","params":{ "labels" : [ "System.Memory(free.percent)" ] }}'
    typeset -i percentage;
    percentage=$(cat $TMP_WGET_FILE | sed 's/.*"result":{"System.Memory(free.percent)":"\([0-9]\{1,3\}\)%"}.*/\1/g')
    if [[ -z $limit ]]; then
      let limit=$percentage/2
      echo "   Memory percentage lower limit set to ${limit}%"
    fi
    echo -ne "   Current percentage memory usage: $(printf "%3s" "$percentage")%\r"
    if [[ $percentage -lt $limit ]]; then
      echo "   Restarting Rygel to free memory"
      set +e
      stop_rygel
      start_rygel
      set -e
      connect_kodi_to_rygel
    fi
    sleep 30
  done
}

function exit_program {
  stop_rygel
  if [[ -n "$TMP_WGET_FILE" ]]; then
    rm -f $TMP_WGET_FILE
  fi
}


### MAIN ###
here=$(dirname $0)

# Start rygel
start_rygel

# Clean up in case of failure
set -e
trap 'exit_program' ERR INT TERM EXIT

# Find Kodi IP
get_kodi_ip
KODI_RPC_URL='http://'${KODI_IP}'/jsonrpc?request='

# (re)connect to "rygel / gst launch" upnp source
connect_kodi_to_rygel

echo "Start monitoring Kodi memory usage"
TMP_WGET_FILE=$(mktemp)
kodi_monitor_free_memory

trap - ERR INT TERM EXIT
set +e
exit

exit_program
