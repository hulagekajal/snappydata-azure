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
while getopts "t:i:s:c:l:u:a:n:f:" opt; do
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
        f) CONFPARAMETERS=$OPTARG
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

# The start of services in proper order takes place based on dependsOn within the template: locators, data stores, leaders
LOCAL_IP=`hostname -I`

# Setup passwordless ssh
ssh-keygen -t rsa -f ~/.ssh/id_rsa -N ''
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 644 ~/.ssh/authorized_keys

# Below if block derives name of other locator from this locator. Assumes there are only two locators.
OTHER_LOCATOR=""
if [ "$LOCATORNODECOUNT" == "2" ]; then
  echo ${LOCATORHOSTNAME} | grep '1$'
  if [ $? == 0 ]; then
    OTHER_LOCATOR=`echo ${LOCATORHOSTNAME} | sed 's/1$/2/g'`
  else
    OTHER_LOCATOR=`echo ${LOCATORHOSTNAME} | sed 's/2$/1/g'`
  fi
fi

chown -R ${ADMINUSER}:${ADMINUSER} /opt/snappydata
mkdir -p "/opt/snappydata/work/${NODETYPE}"

if [ "$NODETYPE" == "locator" ]; then
    if [ ${OTHER_LOCATOR} != "" ]; then
      OTHER_LOCATOR="-locators=${OTHER_LOCATOR}:10334"
    fi
    echo "${LOCAL_IP} -peer-discovery-address=${LOCAL_IP} ${OTHER_LOCATOR} -dir=/opt/snappydata/work/locator ${CONFPARAMETERS}" > ${DIR}/conf/locators 
    ${DIR}/sbin/snappy-locators.sh start
fi

if [ ${OTHER_LOCATOR} != "" ]; then
    OTHER_LOCATOR=",${OTHER_LOCATOR}:10334"
fi

if [ "$NODETYPE" == "datastore" ]; then
    echo "${LOCAL_IP} -locators=${LOCATORHOSTNAME}:10334${OTHER_LOCATOR} -dir=/opt/snappydata/work/datastore ${CONFPARAMETERS}" > ${DIR}/conf/servers
    ${DIR}/sbin/snappy-servers.sh start
elif [ "$NODETYPE" == "lead" ]; then
    echo "${LOCAL_IP} -locators=${LOCATORHOSTNAME}:10334${OTHER_LOCATOR} -dir=/opt/snappydata/work/lead ${CONFPARAMETERS}" > ${DIR}/conf/leads
    ${DIR}/sbin/snappy-leads.sh start
fi
# ---------------------------------------------------------------------------------------------

