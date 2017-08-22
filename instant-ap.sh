#!/bin/bash

# interfaces setup
IN_IF=wlan0
OUT_IF=ppp0
IN_ADDR="10.0.0.1"

# hostapd setup
SSID="INSTANT-AP"
CHANNEL="1"
WPA2_PASSPHRASE="yourverysecurepassphrase" # leave blank for open ap
HOSTAPD_CONF="./hostapd.conf"

# dnsmasq setup
DHCP_RANGE_START="10.0.0.101"
DHCP_RANGE_STOP="10.0.0.150"
LEASE_TIME="12h"
NAMESERVER_A=8.8.8.8 # nameservers to send to the clients
NAMESERVER_B=8.8.4.4 # nameservers to send to the clients
DNSMASQ_CONF="./dnsmasq.conf"

# ----------------------------------------------------------------------

# First of all, some little checks
ID=$(id -u)
if [ $ID -ne 0 ] ; then echo -e "\nERROR: you must be root to run this script!\n" ; exit 1 ; fi
which dnsmasq > /dev/null ; if [ $? -ne 0 ] ; then echo -e "\nERROR: dnsmasq is needed to run this script!\n" ; exit 1 ; fi
which hostapd > /dev/null ; if [ $? -ne 0 ] ; then echo -e "\nERROR: hostapd is needed to run this script!\n" ; exit 1 ; fi

# Let's roll
start() {

    # disable handling of wireless interface by NetworkManager
    if [ -z "$(ps -e | grep networkmanager)" ]
    then
        nmcli nm wifi off &> /dev/null || nmcli radio wifi off &> /dev/null
        CMD1_EX=$?
        rfkill unblock wlan
        CMD2_EX=$?
        if [ $(( $CMD1_EX + $CMD2_EX )) -eq 0 ]
        then
            echo "- Interface $IN_IF is no longer managed by NetworkManager"
        else
            echo "ERROR: Unable to unlock interface $IN_IF (still managed by NetworkManager)"
        fi
    fi

	# Initial wifi interface configuration
	echo
	echo "- Interface $IN_IF setup as $IN_ADDR"
	ifconfig $IN_IF up $IN_ADDR netmask 255.255.255.0
	sleep 2

	# Enable ipv4 forwarding
	echo
	echo "- Enabling ipv4 forwarding in kernel."
	sysctl -w net.ipv4.ip_forward=1

	# Enable NAT
	echo
	echo "- Starting iptables (MASQUERADE all / in: $IN_IF / out: $OUT_IF)."
	iptables --flush
	iptables --table nat --flush
	iptables --delete-chain
	iptables --table nat --delete-chain
	iptables --table nat --append POSTROUTING --out-interface $OUT_IF -j MASQUERADE
	iptables --append FORWARD --in-interface $IN_IF -j ACCEPT

	# Uncomment the line below if facing problems while sharing PPPoE
	#iptables -I FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

	# Start dnsmasq
	if [ -z "$(ps -e | grep dnsmasq)" ]
	then

        # write conf file for dnsmasq
        echo "interface=$IN_IF" > $DNSMASQ_CONF
        echo "no-resolv" >> $DNSMASQ_CONF
        echo "dhcp-range=$DHCP_RANGE_START,$DHCP_RANGE_STOP,$LEASE_TIME" >> $DNSMASQ_CONF
        echo "server=$NAMESERVER_A" >> $DNSMASQ_CONF
        echo "server=$NAMESERVER_B" >> $DNSMASQ_CONF
        
		echo
		echo "- Starting dnsmasq with the following setup:"
		echo
		grep -v "^#" $DNSMASQ_CONF
		echo
		
        dnsmasq -C $DNSMASQ_CONF

	else
		echo
		echo "- ERROR: dnsmasq is already running!"

        if [ ! -z "$(ps -e | grep dnsmasq | grep -i networkmanager)" ]
        then
            echo "INFO: dnsmasq is being summoned by NetworkManager, please comment out the line 'dns=dnsmasq' in NetworkManager conf file and restart it"
        fi
	fi

	# Start hostapd
	if [ -z "$(ps -e | grep hostapd)" ]
	then
    
        # write conf file for hostapd
        echo "interface=$IN_IF" > $HOSTAPD_CONF
        echo "ssid=$SSID" >> $HOSTAPD_CONF
        echo "channel=$CHANNEL" >> $HOSTAPD_CONF
        if [ ! -z $WPA2_PASSPHRASE ]
        then
            echo "auth_algs=1" >> $HOSTAPD_CONF
            echo "wpa=2" >> $HOSTAPD_CONF
            echo "wpa_key_mgmt=WPA-PSK" >> $HOSTAPD_CONF  
            echo "rsn_pairwise=CCMP" >> $HOSTAPD_CONF
            echo "wpa_passphrase=$WPA2_PASSPHRASE" >> $HOSTAPD_CONF
        fi
    
		echo
		echo "- Starting hostapd with the following setup:"
		echo
		grep -v "^#" $HOSTAPD_CONF
		echo
        
		hostapd -B $HOSTAPD_CONF
        
	else
		echo
		echo "ERROR: hostapd is already running!"
		echo
	fi
}

# Bring the whole thing down
stop() {

	echo
	
    echo "- flushing iptables rules"
	iptables --flush && iptables --table nat --flush
	echo
	
    echo "- disabling ipv4 forwarding"
	sysctl -w net.ipv4.ip_forward=0 > /dev/null
	echo
	
    echo "- killing dnsmasq"
	killall -9 dnsmasq
    rm -f $DNSMASQ_CONF
	echo
	
    echo "- killing hostapd"
	killall -9 hostapd
    rm -f $HOSTAPD_CONF
	echo
	
    echo "- bringing down interface $IN_IF"
	ifconfig $IN_IF down
	ifconfig mon.$IN_IF down
    echo
    
    if [ -z "$(ps -e | grep networkmanager)" ]
    then
        nmcli nm wifi on &> /dev/null || nmcli radio wifi on &> /dev/null
        echo "- giving back Networmanager control over interface $IN_IF"
    fi
	echo

}

# WTF?
status() {

	echo

	ifconfig | grep $OUT_IF > /dev/null

	if [ $? -eq 0 ]
	then
		OUT_IF_SETUP=$(ifconfig $OUT_IF |  grep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sed -e 's/^ *//g')

		if [ -z "$OUT_IF_SETUP" ]
		then
			echo "- KO: $OUT_IF is up, but *NOT* configured!"
			echo
		else
			echo "- OK: $OUT_IF is up. Setup: $OUT_IF_SETUP"
			echo
		fi
	else
		echo "- KO: $OUT_IF is *NOT* up!"
		echo
	fi

	ifconfig | grep $IN_IF > /dev/null

	if [ $? -eq 0 ]
	then
		IN_IF_SETUP=$(ifconfig $IN_IF |  grep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sed -e 's/^ *//g')

		if [ -z "$IN_IF_SETUP" ]
		then
			echo "- KO: $IN_IF is up, but *NOT* configured!"
			echo
		else
			echo "- OK: $IN_IF is up. Setup: $IN_IF_SETUP"
			echo
		fi
	else
		echo "- KO: $IN_IF is *NOT* up!"
		echo
	fi

	if [ -z "$(ps -e | grep dnsmasq)" ]
	then
		echo "- KO: dnsmasq is *NOT* running!"
		echo
	else
		DNSMASQ_PID=$(pidof dnsmasq)
		N_CLIENTS=$(iw dev $IN_IF station dump | grep -i station | wc -l)
		echo "- OK: dnsmasq is running. Pid: $DNSMASQ_PID  ($N_CLIENTS client(s) connected)"
		echo
	fi

	if [ -z "$(ps -e | grep hostapd)" ]
	then
		echo "- KO: hostapd is *NOT* running!"
		echo

	else
		HOSTAPD_PID=$(pidof hostapd)
		echo "- OK: hostapd is running.  Pid: $HOSTAPD_PID"
		echo

	fi

	FWD_SETUP=$(sysctl net.ipv4.ip_forward | cut -d '=' -f 2 | tr -d ' ' )

	if [ $FWD_SETUP -eq "1" ]
	then
		echo "- OK: kernel ipv4 forwarding is active." 
		echo
	else
		echo "- KO: kernel ipv4 forwarding is *NOT* active!"
		echo
	fi


	echo "- iptables (nat / POSTROUTING) setup:"
	echo
	iptables -t nat -n -L POSTROUTING -v | tail --lines=+2

	echo

}

case "$1" in

	start)

		start
		;;

	stop)

		stop
		;;

	status)

		status
		;;

	*)
		echo "Usage: $0 {start|stop|status}"
		exit 1
		;;

esac
