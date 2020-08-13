#!/bin/sh

[ -L /sbin/udhcpc ] || exit 0

. /lib/functions.sh
. ../netifd-proto.sh
init_proto "$@"

proto_dns_init_config() {
	renew_handler=1

	proto_config_add_string 'ipaddr:ipaddr'
	proto_config_add_string 'hostname:hostname'
	proto_config_add_string clientid
	proto_config_add_string vendorid
	proto_config_add_boolean 'broadcast:bool'
	proto_config_add_boolean 'release:bool'
	proto_config_add_string 'reqopts:list(string)'
	proto_config_add_boolean 'defaultreqopts:bool'
	proto_config_add_string iface6rd
	proto_config_add_array 'sendopts:list(string)'
	proto_config_add_boolean delegate
	proto_config_add_string zone6rd
	proto_config_add_string zone
	proto_config_add_string mtu6rd
	proto_config_add_string customroutes
	proto_config_add_boolean classlessroute
}

proto_dns_add_sendopts() {
	[ -n "$1" ] && append "$3" "-x $1"
}

proto_dns_setup() {
	local config="$1"
	local iface="$2"

	local ipaddr hostname clientid vendorid broadcast release reqopts defaultreqopts iface6rd sendopts delegate zone6rd zone mtu6rd customroutes classlessroute
	json_get_vars ipaddr hostname clientid vendorid broadcast release reqopts defaultreqopts iface6rd delegate zone6rd zone mtu6rd customroutes classlessroute

	local opt dhcpopts
	for opt in $reqopts; do
		append dhcpopts "-O $opt"
	done

	json_for_each_item proto_dns_add_sendopts sendopts dhcpopts

	[ -z "$hostname" ] && hostname="$(cat /proc/sys/kernel/hostname)"
	[ "$hostname" = "*" ] && hostname=

	[ "$defaultreqopts" = 0 ] && defaultreqopts="-o" || defaultreqopts=
	[ "$broadcast" = 1 ] && broadcast="-B" || broadcast=
	[ "$release" = 1 ] && release="-R" || release=
	[ -n "$clientid" ] && clientid="-x 0x3d:${clientid//:/}" || clientid="-C"
	[ -n "$zone" ] && proto_export "ZONE=$zone"
	# Request classless route option (see RFC 3442) by default
	#[ "$classlessroute" = "0" ] || append dhcpopts "-O 121"

	proto_export "INTERFACE=$config"

	sleep 1

	proto_run_command "$config" udhcpc \
		-p /var/run/udhcpc-$iface.pid \
		-s /lib/netifd/dns.script \
		-f -t 0 -T 4 -i "$iface" \
		${ipaddr:+-r $ipaddr} \
		${hostname:+-x "hostname:$hostname"} \
		${vendorid:+-V "$vendorid"} \
		$clientid $defaultreqopts $broadcast $release $dhcpopts
}

proto_dns_renew() {
	local interface="$1"
	# SIGUSR1 forces udhcpc to renew its lease
	local sigusr1="$(kill -l SIGUSR1)"
	[ -n "$sigusr1" ] && proto_kill_command "$interface" $sigusr1
}

proto_dns_teardown() {
	local interface="$1"
	proto_kill_command "$interface"
}

add_protocol dns
