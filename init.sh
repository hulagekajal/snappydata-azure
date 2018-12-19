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
while getopts "t:i:s:c:l:u:a:n:f:z" opt; do
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
        z) LAUNCHZEPPELIN=$OPTARG
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

launch_zeppelin()
{
    ZEP_VERSION="0.7.3"
    ZEP_DIR="zeppelin-${ZEP_VERSION}-bin-netinst"
    ZEP_URL_MIRROR="http://archive.apache.org/dist/zeppelin/zeppelin-${ZEP_VERSION}/${ZEP_DIR}.tgz"
    #ZEP_NOTEBOOKS_URL="https://github.com/SnappyDataInc/zeppelin-interpreter/raw/notes/examples/notebook"
    #ZEP_NOTEBOOKS_DIR="notebook"
    PUBLIC_HOSTNAME=`wget -q -O - http://169.254.169.254/latest/meta-data/public-hostname`
    export Z_DIR=/opt/zeppelin
    mkdir -p ${Z_DIR}

    # download zeppelin 0.7.3 distribution, extract as /opt/zeppelin
    wget -q "${ZEP_URL_MIRROR}"
    tar -xf "${ZEP_DIR}.tgz" --directory ${Z_DIR} --strip 1 

    # download pre-created sample notebooks for snappydata
    #wget -q "${ZEP_NOTEBOOKS_URL}/${ZEP_NOTEBOOKS_DIR}.tar.gz"
    #tar -xzf "${ZEP_NOTEBOOKS_DIR}.tar.gz"
    #find ${ZEP_NOTEBOOKS_DIR} -type f -print0 | xargs -0 sed -i "s/localhost/${PUBLIC_HOSTNAME}/g"

    #echo "Copying sample notebooks..."
    #cp -ar "${ZEP_NOTEBOOKS_DIR}/." "${ZEP_DIR}/${ZEP_NOTEBOOKS_DIR}/"
 
    # download zeppelin interpreter 0.7.3.4 for snappydata
    ZEP_INTP_JAR="snappydata-zeppelin_2.11-0.7.3.4.jar"
    INTERPRETER_URL="https://github.com/SnappyDataInc/zeppelin-interpreter/releases/download/v0.7.3.4/${ZEP_INTP_JAR}"
    INTERPRETER_DIR="${ZEP_DIR}/interpreter/snappydata"
    mkdir -p "${INTERPRETER_DIR}"
    wget -q "${INTERPRETER_URL}"
    mv "${ZEP_INTP_JAR}" "${INTERPRETER_DIR}"
    jar -xf "${INTERPRETER_DIR}/${ZEP_INTP_JAR}" interpreter-setting.json
    mv interpreter-setting.json interpreter-setting.json.orig

    # Place interpreter dependencies into the directory
    cp -a "${DIR}/jars/." "${INTERPRETER_DIR}"
    cp interpreter-setting.json.orig "${INTERPRETER_DIR}"/interpreter-setting.json

   
    # edit conf/zeppelin-site.xml (add our two interpreter classnames under 'interpreters' attribute.
    # optional: generate interpreter.json by restarting the zeppelin server and point zeppelin to remote interpreter process at localhost:3768
    # start zeppelin server
}
# ============================================================================================================
# MAIN
# ============================================================================================================

yum install -y java-1.8.0-openjdk

export DIR=/opt/snappydata
mkdir -p ${DIR}

# TODO Get the latest snappydata distribution
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
LOCAL_IP=`hostname -I`
PUBLIC_IP=`curl ifconfig.co`

# Setup passwordless ssh
ssh-keygen -t rsa -f ~/.ssh/id_rsa -N ''
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

# Below if block derives name of other locator from this locator. Assumes there are only two locators.

chown -R ${ADMINUSER}:${ADMINUSER} /opt/snappydata
mkdir -p "/opt/snappydata/work/${NODETYPE}"
OTHER_LOCATOR=""
if [ "${LOCATORNODECOUNT}" == "2" ]; then
  echo ${LOCATORHOSTNAME} | grep '1$'
  if [ $? == 0 ]; then
    OTHER_LOCATOR=`echo ${LOCATORHOSTNAME} | sed 's/1$/2/g'`
  fi
fi
if [ "$NODETYPE" == "locator" ]; then
  if [ ${OTHER_LOCATOR} != "" ]; then
    OTHER_LOCATOR="-locators=${OTHER_LOCATOR}:10334"
  fi
  echo "${LOCAL_IP} -peer-discovery-address=${LOCAL_IP} -hostname-for-clients=${PUBLIC_IP} -dir=/opt/snappydata/work/locator ${OTHER_LOCATOR} ${CONFPARAMETERS}" > ${DIR}/conf/locators
  ${DIR}/sbin/snappy-locators.sh start
fi

if [ ${OTHER_LOCATOR} != "" ]; then
  OTHER_LOCATOR=",${OTHER_LOCATOR}:10334"
fi

if [ "$NODETYPE" == "datastore" ]; then
  echo "${LOCAL_IP} -hostname-for-clients=${PUBLIC_IP} -dir=/opt/snappydata/work/datastore -locators=${LOCATORHOSTNAME}:10334${OTHER_LOCATOR} ${CONFPARAMETERS}" > ${DIR}/conf/servers
  ${DIR}/sbin/snappy-servers.sh start
elif [ "$NODETYPE" == "lead" ]; then
   if ("LAUNCHZEPPELIN" == "Yes"); then
      echo "${LOCAL_IP} -dir=/opt/snappydata/work/lead -locators=${LOCATORHOSTNAME}:10334${OTHER_LOCATOR} -zeppelin-interpreter-enable=true -classpath=${DIR}/${ZEP_INTP_JAR} ${CONFPARAMETERS}" > ${DIR}/conf/leads
      launch_zeppelin()
   else
      echo "${LOCAL_IP} -dir=/opt/snappydata/work/lead -locators=${LOCATORHOSTNAME}:10334${OTHER_LOCATOR} ${CONFPARAMETERS}" > ${DIR}/conf/leads
   fi
  ${DIR}/sbin/snappy-leads.sh start
fi

# ---------------------------------------------------------------------------------------------
