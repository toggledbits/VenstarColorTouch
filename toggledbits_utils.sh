#!/bin/sh
# togglebits_utils.sh
# (c) 2018 Patrick H. Rigney, All Rights Reserved.
# This script is used on openLuup to abstract platform-specific behaviors out
# the plugin(s) for which it operates. It implements several operations, which
# may different implementations on different distributions/OSs.

# Version of this script, or more correctly, its capability and output. The
# number should only change when commands are added or the format of existing
# commands is changed meaningfully. Adding an additional supported platform is
# NOT cause change change this value.
SCRIPTREVISION=2

# These values are to help make exceptions for the platform.
OS=`awk '/^ID=/' /etc/os-release | sed 's/ID=//' | sed 's/"//g' | tr '[:upper:]' '[:lower:]'`
VERSION=`awk '/^VERSION_ID=/' /etc/os-release | sed 's/VERSION_ID=//' | sed 's/"//g'`
ARCH=`uname -m | sed 's/x86_// ; s/i[3-6]86/32/'`
if [ -z "$OS" ]; then
    OS=`awk '{print $1}' /etc/*-release | head -1 | tr '[:upper:]' '[:lower:]'`
fi

# Let's get to work...
OP=${1:-help}
case $OP in
    "arplist" )
        # ARP list. The expected output is IP address <tab> HWType <tab> flags <tab> MAC <tab--and remainder ignored>
        # 192.168.0.162            ether   00:0c:29:1a:52:49   C                     eth0
        # For most platforms that have it, the standard "arp" command is fine. On same, you may need to just cat /proc/net/arp
        arp | awk '{ print $1,$2,$2,$3 }'
	echo "192.168.0.162\t0x01\t0x02\t00:0c:29:1a:52:49\tX\teth0.local"
        ;;
    "ip4info" )
        # Return IP4 network info for the default/primary interface. 
        # Required format (comma-separated): address,mask,gateway,interface-device (e.g. 192.168.0.162/24,192.168.0.255,192.168.0.1,ens160)
        # The mask may be empty/blank if the address is CIDR format.
        # Typical implementation, use "ip" command to get default gateway IP and interface
        GW=`ip -4 route | awk '/^default/ {print $3}'`
        IF=`ip -4 route | awk '/^default/ {print $5}'`
        IP=`ip -o -4 address | fgrep "$IF" | awk 'OFS="," {print $4,$6}'`
        echo "$IP,$GW,$IF"
        ;;
    "ping4" )
        addr=${2:?address required}
        if [ "x$OS" = "xcentos" ]; then
            /bin/ping -b -q -c 3 -w 1 $addr
        else
            /bin/ping -q -c 3 -w 1 $addr
        fi
        ;;
    "pingb" )
        # Do broadcast ping. Some can ping addr without options, some need -b
        addr=${2:?address required}
        if [ "$OS" = "centos" ]; then
            /bin/ping -b -q -c 3 -w 1 $addr >/dev/null
        elif [ "$OS" = "ubuntu" ]; then
            /bin/ping -b -q -c 3 -w 1 $addr >/dev/null
        else
            /bin/ping -4 -b -q -c 3 -w 1 $addr >/dev/null
        fi
        ;;
    "getuuid" )
        # Return a UUID (default version 4, which is time and host MAC based). Format is UUID alone on its own line.
        VER=${2:-4}
        uuid -v $VER
        ;;
    "platform" )
        # Return information about the underlying OS.
        echo "$OS,$VERSION,$ARCH"
        ;;
    "cwd" )
        # Return the path of the current working directory
        pwd
        ;;
    "scriptpath" )
        # Return the path in which this script lives
        dirname `readlink -f $0`
        ;;
    "version" )
        # Return the version number of this script and path to shell
        echo "$SCRIPTREVISION,$SHELL"
        ;;
    "help" )
        echo "Usage: $0 <operation> [argument [ ... ] ]"
        echo "Operation should be one of:"
        echo "    arplist - Show current ARP table, with IP addresses and MAC addresses"
        echo "    cwd - Return current working directory (may not be script directory, see scriptpath"
        echo "    getuuid - Return a uuid unique for all time on the host"
        echo "    help - Print this help"
        echo "    ip4info - Return IPv4 address information for the primary interface"
        echo "    ping4 - Ping IP4 address, including possible broadcast ping"
        echo "    scriptpath - Return path to directory containing this script"
        echo "    version - Return version number for this script and path of shell"
        exit 255
        ;;
    "test" )
        echo "Script version info: `$0 version`"
        echo "This script lives in: `$0 scriptpath`"
        echo "Working directory is `$0 cwd`"
        echo "A new UUID is `$0 getuuid`"
        echo "The primary IP4 info is: `$0 ip4info`"
        echo "ARP is `$0 arplist`"
        ;;
    *)
        echo "Unrecognized operation: '$OP'. Try '$0 help'"
        exit 255
esac
