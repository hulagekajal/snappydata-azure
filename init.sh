#!/bin/bash

# init.sh -t NODETYPE -i LOCALIP -s STARTADDRESS -c DATASTORENODECOUNT -u BASEURL
# sh init.sh -d standard -t locator -i 10.0.1.4 -s 10.0.1.4 -c 2 -u https://github.com/test

log()
{
	echo "$1"
	logger "$1"
}

# Initialize local variables
# Get today's date into YYYYMMDD format
NOW=$(date +"%Y%m%d")

# Get command line parameters
while getopts "t:i:s:c:u:" opt; do
	log "Option $opt set with value (${OPTARG})"
	case "$opt" in
		t)	NODETYPE=$OPTARG
		;;
		i)	LOCALIP=$OPTARG
		;;
		s)	STARTADDRESS=$OPTARG
		;;
		c)	DATASTORENODECOUNT=$OPTARG
		;;
		u)	BASEURL=$OPTARG
		;;
	esac
done

fatal() {
    msg=${1:-"Unknown Error"}
    log "FATAL ERROR: $msg"
    exit 1
}

# Retries a command on failure.
# $1 - the max number of attempts
# $2... - the command to run
retry() {
    local -r -i max_attempts="$1"; shift
    local -r cmd="$@"
    local -i attempt_num=1
 
    until $cmd
    do
        if (( attempt_num == max_attempts ))
        then
            log "Command $cmd attempt $attempt_num failed and there are no more attempts left!"
			return 1
        else
            log "Command $cmd attempt $attempt_num failed. Trying again in 5 + $attempt_num seconds..."
            sleep $(( 5 + attempt_num++ ))
        fi
    done
}

# You must be root to run this script
if [ "${UID}" -ne 0 ]; then
    fatal "You must be root to run this script."
fi

if [[ -z ${NODETYPE} ]]; then
    fatal "No node type -t specified, can't proceed."
fi

if [[ -z ${LOCALIP} ]]; then
    fatal "No local IP -i specified, can't proceed."
fi

if [[ -z ${STARTADDRESS} ]]; then
    fatal "No start address -s specified, can't proceed."
fi

if [[ -z ${DATASTORENODECOUNT} ]]; then
    fatal "No segments count -c specified, can't proceed."
fi

if [[ -z ${BASEURL} ]]; then
    fatal "No base URL -u specified, can't proceed."
fi

log "init.sh NOW=$NOW NODETYPE=$NODETYPE LOCALIP=$LOCALIP STARTADDRESS=$STARTADDRESS DATASTORENODECOUNT=$DATASTORENODECOUNT BASEURL=$BASEURL"

download()
{	
	# Clear download directory
	rm -rf *.*
	
	# Download scripts
	curl -O ${BASEURL}/init.sh
	
	# Download binaries
	# curl -O ${BASEURL}/
}

create_internal_ip_file()
{
	# Generate IP addresses of the nodes based on the convention of locator1, locator2, leader1, leader2, data stores
	IFS='.' read -r -a startaddress_parts <<< "$STARTADDRESS"
	for (( c=0; c<2+$SEGMENTHOSTSCOUNT; c++ ))
	do
		octet1=${startaddress_parts[0]}
		octet2=${startaddress_parts[1]}
		octet3=$(( ${startaddress_parts[2]} + $(( $((${startaddress_parts[3]} + c)) / 256 )) ))
		octet4=$(( $(( ${startaddress_parts[3]} + c )) % 256 ))
		ip=$octet1"."$octet2"."$octet3"."$octet4
		echo $ip
	done > ${INTERNAL_IP_FILE}
}

# ============================================================================================================
# MAIN
# ============================================================================================================

# ---------------------------------------------------------------------------------------------

