#!/bin/bash

# init.sh -t NODETYPE -c DATASTORENODECOUNT -l LOCATORHOSTNAME -u BASEURL -a ADMINUSER -n LOCATORNODECOUNT -z LAUNCHZEPPELIN -f CONFPARAMETERS
# sh init.sh -t locator -c 3 -l sd-locator1 -u https://raw.githubusercontent.com/hulagekajal/snappydata-azure/master -a azureuser -n 1 -z yes -f -heap-size=4g

log()
{
    echo "$1"
    logger "[SNAPPYDATA] $1"
}

# Initialize local variables
# Get today's date into YYYYMMDD format
NOW=$(date +"%Y%m%d")

# Get command line parameters
while getopts "t:s:c:l:u:a:n:z:f:" opt; do
    log "Option $opt set with value (${OPTARG})"
    case "$opt" in
        t) NODETYPE=$OPTARG
        ;;
        s) PUBLICIP=$OPTARG
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
        z) LAUNCHZEPPELIN=$OPTARG
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

if [[ -z ${PUBLICIP} ]]; then
    fatal "IP NOT GENERATED"
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


log "init.sh NOW=$NOW NODETYPE=$NODETYPE DATASTORENODECOUNT=$DATASTORENODECOUNT BASEURL=$BASEURL LOCATORNODECOUNT=$LOCATORNODECOUNT"

launch_zeppelin()
{
    ZEP_URL_MIRROR="http://archive.apache.org/dist/zeppelin/zeppelin-0.7.3/zeppelin-0.7.3-bin-netinst.tgz"
    ZEP_NOTEBOOKS_URL="https://github.com/SnappyDataInc/zeppelin-interpreter/raw/notes/examples/notebook"
    ZEP_NOTEBOOKS_DIR="notebook"
    PUBLIC_HOSTNAME="${PUBLICIP}" 
    export Z_DIR=/opt/zeppelin
    mkdir -p ${Z_DIR}
    chown -R ${ADMINUSER}:${ADMINUSER} /opt/zeppelin
   
   
    # download zeppelin 0.7.3 distribution, extract as /opt/zeppelin
    log "Downloading Zeppelin distribution from ${ZEP_URL_MIRROR} ..."
    wget -q "${ZEP_URL_MIRROR}"
    tar -xf "zeppelin-0.7.3-bin-netinst.tgz" --directory ${Z_DIR} --strip 1
    
    # download pre-created sample notebooks for snappydata
    log "Downloading Zeppelin notebooks from ${ZEP_NOTEBOOKS_URL}/${ZEP_NOTEBOOKS_DIR}.tar.gz ..."
    wget -q "${ZEP_NOTEBOOKS_URL}/${ZEP_NOTEBOOKS_DIR}.tar.gz"
    tar -xzf "${ZEP_NOTEBOOKS_DIR}.tar.gz"
    find ${ZEP_NOTEBOOKS_DIR} -type f -print0 | xargs -0 sed -i "s/localhost/${PUBLIC_HOSTNAME}/g"

    log "Copying sample notebooks ..."
    cp -ar "${ZEP_NOTEBOOKS_DIR}/." "${Z_DIR}/${ZEP_NOTEBOOKS_DIR}/"

    # download zeppelin interpreter 0.7.3.4 for snappydata
    ZEP_INTP_JAR="snappydata-zeppelin_2.11-0.7.3.4.jar"
    INTERPRETER_URL="https://github.com/SnappyDataInc/zeppelin-interpreter/releases/download/v0.7.3.4/${ZEP_INTP_JAR}"
    wget -q "${INTERPRETER_URL}"
    mv "${ZEP_INTP_JAR}" "${DIR}/"

    ${Z_DIR}/bin/install-interpreter.sh --name snappydata --artifact io.snappydata:snappydata-zeppelin:0.7.3.4

    # Modify conf/zeppelin-site.xml to include classnames of snappydata interpreters.
    cp "${Z_DIR}/conf/zeppelin-site.xml.template" "${Z_DIR}/conf/zeppelin-site.xml"
    SEARCH_STRING="<name>zeppelin.interpreters<\/name>"
    INSERT_STRING="org.apache.zeppelin.interpreter.SnappyDataZeppelinInterpreter,org.apache.zeppelin.interpreter.SnappyDataSqlZeppelinInterpreter,"
    sed -i "/${SEARCH_STRING}/{n;s/<value>/<value>${INSERT_STRING}/}" "${Z_DIR}/conf/zeppelin-site.xml"

    # optional: generate interpreter.json by restarting the zeppelin server and point zeppelin to remote interpreter process at localhost:3768
    log "Configuring Snappydata Interpreter..."
    ${Z_DIR}/bin/zeppelin-daemon.sh start
    while ! test -f  "${Z_DIR}/conf/interpreter.json" ; do
      sleep 3
    done
    sh "${Z_DIR}/bin/zeppelin-daemon.sh" stop
    if [[ ! -e "${Z_DIR}/conf/interpreter.json" ]]; then
      log "The file interpreter.json was not generated."
    fi

    # Modify conf/interpreter.json to include lead host and port and set isExistingProcess to true.
    if [[ -e "${Z_DIR}/conf/interpreter.json" ]]; then
      LEAD_HOST="localhost"
      LEAD_PORT="3768"
      sed -i "/group\": \"snappydata\"/,/isExistingProcess\": false/{s/isExistingProcess\": false/isExistingProcess\": snappydatainc_marker/}" "${Z_DIR}/conf/interpreter.json"
      sed -i "/snappydatainc_marker/a \"host\": \"${LEAD_HOST}\",\n \"port\": \"${LEAD_PORT}\"," "${Z_DIR}/conf/interpreter.json"
      sed -i "s/snappydatainc_marker/true/" "${Z_DIR}/conf/interpreter.json"
    fi

    # Start zeppelin server
    ${Z_DIR}/bin/zeppelin-daemon.sh start
}

# ============================================================================================================
# MAIN
# ============================================================================================================

yum install -y java-1.8.0-openjdk

export DIR=/opt/snappydata
mkdir -p ${DIR}

# TODO Get the latest snappydata distribution
wget -q --tries 10 --retry-connrefused --waitretry 15 https://github.com/SnappyDataInc/snappydata/releases/download/v1.0.2.1/snappydata-1.0.2.1-bin.tar.gz

# Extract the contents of the archive to /opt/snappydata directory without the top folder
tar -zxf snappydata-1.0.2.1-bin.tar.gz --directory ${DIR} --strip 1

cd ${DIR}

LOCAL_IP=`hostname -I`
HOST_NAME=`hostname`


# Setup passwordless ssh
ssh-keygen -t rsa -f ~/.ssh/id_rsa -N ''
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

# Below if block derives name of other locator from this locator. Assumes there are only two locators.

chown -R ${ADMINUSER}:${ADMINUSER} /opt/snappydata
mkdir -p "/opt/snappydata/work/${NODETYPE}"
OTHER_LOCATOR=""
NEW_LEAD=`echo ${LOCATORHOSTNAME} | sed 's/locator1/lead2/g'`

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
  echo "${LOCAL_IP} -peer-discovery-address=${LOCAL_IP} -hostname-for-clients=${PUBLICIP} -dir=/opt/snappydata/work/locator ${OTHER_LOCATOR} ${CONFPARAMETERS}" > ${DIR}/conf/locators
  ${DIR}/sbin/snappy-locators.sh start
fi

if [ ${OTHER_LOCATOR} != "" ]; then
  OTHER_LOCATOR=",${OTHER_LOCATOR}:10334"
fi

if [ "$NODETYPE" == "datastore" ]; then
  echo "${LOCAL_IP} -hostname-for-clients=${PUBLICIP} -dir=/opt/snappydata/work/datastore -locators=${LOCATORHOSTNAME}:10334${OTHER_LOCATOR} ${CONFPARAMETERS}" > ${DIR}/conf/servers
  ${DIR}/sbin/snappy-servers.sh start
elif [ "$NODETYPE" == "lead" ]; then
   if [ ${HOST_NAME} == ${NEW_LEAD}];then
   sleep 5
   fi
    if [ ( "$LAUNCHZEPPELIN" == "yes" ) -a ( ${HOST_NAME} != ${NEW_LEAD} ) ]; then
      echo "${LOCAL_IP} -dir=/opt/snappydata/work/lead -locators=${LOCATORHOSTNAME}:10334${OTHER_LOCATOR} -zeppelin.interpreter.enable=true -classpath=${DIR}/snappydata-zeppelin_2.11-0.7.3.4.jar ${CONFPARAMETERS}" > ${DIR}/conf/leads
      launch_zeppelin
    else
      echo "${LOCAL_IP} -dir=/opt/snappydata/work/lead -locators=${LOCATORHOSTNAME}:10334${OTHER_LOCATOR} ${CONFPARAMETERS}" > ${DIR}/conf/leads
    fi
    ${DIR}/sbin/snappy-leads.sh start
fi

# ---------------------------------------------------------------------------------------------

