#!/bin/bash

IN_IF=wlan0
OUT_IF=ppp0
IN_ADDR="10.0.0.1"
HOSTAPD_CONF="./hostapd.conf"
DNSMASQ_CONF="./dnsmasq.conf"

# First of all, some little checks
ID=$(id -u)
if [ $ID -ne 0 ] ; then echo -e "\nERROR: you must be root to run this script!\n" ; exit 1 ; fi
which dnsmasq > /dev/null ; if [ $? -ne 0 ] ; then echo -e "\nERROR: dnsmasq is needed to run this script!\n" ; exit 1 ; fi
which hostapd > /dev/null ; if [ $? -ne 0 ] ; then echo -e "\nERROR: hostapd is needed to run this script!\n" ; exit 1 ; fi

# Let's roll
start() {

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
		echo
		echo "- Starting dnsmasq with the following setup:"
		echo
		grep -v "^#" $DNSMASQ_CONF
		echo
		dnsmasq -C $DNSMASQ_CONF
	else
		echo
		echo "- ERROR: dnsmasq is already running!"
	fi

	# Start hostapd
	if [ -z "$(ps -e | grep hostapd)" ]
	then
		echo
		echo "- Starting hostapd with the following setup:"
		echo
		grep -v "^#" $HOSTAPD_CONF
		echo
		# memo
		# nmcli nm wifi off
		# rfkill unblock wlan
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
	echo
	echo "- killing hostapd"
	killall -9 hostapd
	echo
	echo "- bringing down interface $IN_IF"
	ifconfig $IN_IF down
	ifconfig mon.$IN_IF down
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
		echo "- OK: dnsmasq is running. Pid: $DNSMASQ_PID"
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
