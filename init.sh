#!/bin/bash

# init.sh -t NODETYPE -i LOCALIP -s STARTADDRESS -c DATASTORENODECOUNT -a LOCATOR1HOSTNAME -b LOCATOR2HOSTNAME -u BASEURL
# sh init.sh -d standard -t locator -i 10.0.1.4 -s 10.0.1.4 -c 2 -a av-locator1 -b av-locator2 -u https://raw.githubusercontent.com/arsenvlad/snappydata-azure/master

log()
{
    echo "$1"
    logger "$1"
}

# Initialize local variables
# Get today's date into YYYYMMDD format
NOW=$(date +"%Y%m%d")

# Get command line parameters
while getopts "t:i:s:c:l:u:a:n:k:" opt; do
    log "Option $opt set with value (${OPTARG})"
    case "$opt" in
        t) NODETYPE=$OPTARG
        ;;
        i) LOCALIP=$OPTARG
        ;;
        s) STARTADDRESS=$OPTARG
        ;;
        c) DATASTORENODECOUNT=$OPTARG
        ;;
        l) LOCATORHOSTNAME=$OPTARG
        ;;
        u) BASEURL=$OPTARG
        ;;
        a) ADMINUSER=$OPTARG
        ;;
        n) LOCATORNODECOUNT=$OPTARG
        ;;
        k) CLUSTERNAME=$OPTARG
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
    fatal "No datastore count -c specified, can't proceed."
fi

if [[ -z ${LOCATORHOSTNAME} ]]; then
    fatal "No locator hostname -l specified, can't proceed."
fi

if [[ -z ${BASEURL} ]]; then
    fatal "No base URL -u specified, can't proceed."
fi

if [[ -z ${ADMINUSER} ]]; then
    fatal "No admin username -a specified, can't proceed."
fi

if [[ -z ${LOCATORNODECOUNT} ]]; then
    fatal "No locator count -n specified, can't proceed."
fi


log "init.sh NOW=$NOW NODETYPE=$NODETYPE LOCALIP=$LOCALIP STARTADDRESS=$STARTADDRESS DATASTORENODECOUNT=$DATASTORENODECOUNT BASEURL=$BASEURL LOCATORNODECOUNT=$LOCATORNODECOUNT"

# Just a helper method example in case it is convenient to get all IPs into a file by doing some math on the starting IP and the count of data store nodes
create_internal_ip_file()
{
    # Generate IP addresses of the nodes based on the convention of locator1, leader1, data stores
    IFS='.' read -r -a startaddress_parts <<< "$STARTADDRESS"
    for (( c=0; c<4+$DATASTORENODECOUNT; c++ ))
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

yum install -y java-1.8.0-openjdk

export DIR=/opt/snappydata
mkdir -p ${DIR}

wget --tries 10 --retry-connrefused --waitretry 15 https://github.com/SnappyDataInc/snappydata/releases/download/v1.0.2.1/snappydata-1.0.2.1-bin.tar.gz

# Extract the contents of the archive to /opt/snappydata directory without the top folder
tar -zxf snappydata-1.0.2.1-bin.tar.gz --directory ${DIR} --strip 1

cd ${DIR}

# Uncomment if you want to download test tools and data sets
# wget --tries 10 --retry-connrefused --waitretry 15 https://sdtests.blob.core.windows.net/testdata/scripts.tgz
# wget --tries 10 --retry-connrefused --waitretry 15 https://sdtests.blob.core.windows.net/testdata/snappy-cluster_2.10-0.5-tests.jar
# wget --tries 10 --retry-connrefused --waitretry 15 https://sdtests.blob.core.windows.net/testdata/TPCH-1GB.zip
# wget --tries 10 --retry-connrefused --waitretry 15 https://sdtests.blob.core.windows.net/testdata/zeppelin.tgz

# The start of services in proper order takes place based on dependsOn within the template: locators, data stores, leaders
LOCATOR2HOSTNAME="$CLUSTERNAME-locator2"

if [ "$NODETYPE" == "locator" ]; then
    chown -R ${ADMINUSER}:${ADMINUSER} /opt/snappydata
    mkdir -p /opt/snappydata/work/locator
    ${DIR}/bin/snappy locator start -peer-discovery-address=`hostname` -dir=/opt/snappydata/work/locator
fi

if [ "$NODETYPE" == "locator" && "$LOCATORNODECOUNT" == "2" ]; then
    chown -R ${ADMINUSER}:${ADMINUSER} /opt/snappydata
    mkdir -p /opt/snappydata/work/locator
    ${DIR}/bin/snappy locator start -peer-discovery-address=`hostname` -locators=${LOCATORHOSTNAME}:10334,${LOCATOR2HOSTNAME}:10334 -dir=/opt/snappydata/work/locator
fi


if [ "$NODETYPE" == "datastore" ]; then
    chown -R ${ADMINUSER}:${ADMINUSER} /opt/snappydata
    mkdir -p /opt/snappydata/work/datastore
    ${DIR}/bin/snappy server start -locators=${LOCATORHOSTNAME}:10334 -dir=/opt/snappydata/work/datastore
fi

if [ "$NODETYPE" == "datastore" && "$LOCATORNODECOUNT" == "2" ]; then
    chown -R ${ADMINUSER}:${ADMINUSER} /opt/snappydata
    mkdir -p /opt/snappydata/work/datastore
    ${DIR}/bin/snappy server start -locators=${LOCATORHOSTNAME}:10334,${LOCATOR2HOSTNAME}:10334 -dir=/opt/snappydata/work/datastore
fi

if [ "$NODETYPE" == "lead" ]; then
    chown -R ${ADMINUSER}:${ADMINUSER} /opt/snappydata
    mkdir -p /opt/snappydata/work/lead
    ${DIR}/bin/snappy leader start -locators=${LOCATORHOSTNAME}:10334 -dir=/opt/snappydata/work/lead
fi

if [ "$NODETYPE" == "lead" && "$LOCATORNODECOUNT" == "2" ]; then
    chown -R ${ADMINUSER}:${ADMINUSER} /opt/snappydata
    mkdir -p /opt/snappydata/work/lead
    ${DIR}/bin/snappy leader start -locators=${LOCATORHOSTNAME}:10334,${LOCATOR2HOSTNAME}:10334 -dir=/opt/snappydata/work/lead
fi
# ---------------------------------------------------------------------------------------------

