CUR_DIR=`pwd`
#set -x 

AGENT_URI="https://_:$ACCESS_KEY@packages.instana.io"
ARTIFACTORY_URI="https://_:$ACCESS_KEY@artifact-public.instana.io/artifactory/shared/com/instana/agent-assembly-offline/1.0.0-SNAPSHOT/"
DEB_AGENT_PATH="agent/deb/dists/generic/main/binary-amd64"
RPM_AGENT_PATH="agent/rpm/generic/x86_64"

function get-agents() {

  ACCESS_KEY=$1
#Retreive latest versions of static agents for debian, centos, rhel6 and rhel7
# Step 1: prepare env (this is a point of failure if URL change, some env variables might not be correct)
# Step 2: curl the agent page download using access-key provided to retreive files names (.rpm and .deb)
#         (this is another point of failure if URL change since grep is made using a formal path)
# Step 3: Download the packages and place them into base folder of agents directory
# Step 4: Place agent in their respective directory
# Step 5: create tar package file

########## STEP 1 ##########
  
  PKG_PREFIX="instana-agent-static"
  AGENT_DIR="$CUR_DIR/repo_agent"
  mkdir $AGENT_DIR
  AGENT_NAME=""
########## STEP 2 ##########
  #rpm packages
  curl -s "$AGENT_URI/agent/download" | grep -oP '<a href="\/\Kagent\/rpm\/generic\/[achrs346890x_]+\/instana-agent-static[a-z0-9-_.]+.rpm' > $AGENT_DIR/agentlist
  #debian packages (appending to agentlist file)
  curl -s "$AGENT_URI/agent/download" | grep -oP '<a href=\"\/\Kagent\/deb\/dists\/generic\/main\/binary-[admrsx34690x]+\/instana-agent-static[a-z0-9-_.]+.deb' >> $AGENT_DIR/agentlist
  #windows offline
  curl -s "$ARTIFACTORY_URI" |grep -oP 'agent-assembly-offline-1.0.0-\K[0-9.-]+-windows-64bit-offline.exe' | tail -n1 >> $AGENT_DIR/agentlist
  echo "$PKG_PREFIX"

########## STEP 3 ##########
  #download agents
  while read -r line; do
    echo "Downloading -> "
    if [[ $line == *"rpm"* ]]; then
      #echo "Downloading $line"
      AGENT_NAME=`echo $line | grep -oP 'instana-agent-static[a-z0-9-_.]+.rpm'`
      echo $AGENT_NAME
      curl -s -o "$AGENT_DIR/$AGENT_NAME" "$AGENT_URI/$line"
    elif [[ $line == *"deb"* ]]; then
      AGENT_NAME=`echo $line | grep -oP 'instana-agent-static[a-z0-9-_.]+.deb'`
      echo $AGENT_NAME
      curl -s -o "$AGENT_DIR/$AGENT_NAME" "$AGENT_URI/$line"
    else
      AGENT_NAME=$line
      echo $AGENT_NAME
      curl -s -o "$AGENT_DIR/$line" "$ARTIFACTORY_URI/agent-assembly-offline-1.0.0-$line"
    fi

  done < $AGENT_DIR/agentlist

########## STEP 4 ##########

  mkdir $AGENT_DIR/{centos_x86_64,rhel6,rhel7,s390_rpm,s390_deb,aarch64_rpm,arm_deb,debian_amd64,windows_x86_64}
  mv $AGENT_DIR/*el6*.rpm $AGENT_DIR/rhel6
  mv $AGENT_DIR/*el7*.rpm $AGENT_DIR/rhel7
  mv $AGENT_DIR/*s390*.rpm $AGENT_DIR/s390_rpm
  mv $AGENT_DIR/*s390*.deb $AGENT_DIR/s390_deb
  mv $AGENT_DIR/*aarch*.rpm $AGENT_DIR/aarch64_rpm
  mv $AGENT_DIR/*arm*.deb $AGENT_DIR/arm_deb
  mv $AGENT_DIR/*.deb $AGENT_DIR/debian_amd64
  mv $AGENT_DIR/*.rpm $AGENT_DIR/centos_x86_64
  mv $AGENT_DIR/*.exe $AGENT_DIR/windows_x86_64

}

function isAgentKeyValid() {
  
  echo "Verifying Agent Key..."
  local ret=`curl -I -s -X GET $ARTIFACTORY_URI | head -n 1 | cut -d$' ' -f2`
  if [[ $ret != "200" ]]; then
    echo "Invalid Agent Key"
    exit 0
  fi

}


function get-agents-inputs() {

VALID=false

while [ $VALID != true ]
  do
    echo "enter your agent key (field AgentKey from the license email you received)"
    read FINAL_ACCESS_KEY
    echo "enter your Instana server name (full DNS) or IP adress"
    read SERVER_NAME

    echo "Access Key : $FINAL_ACCESS_KEY"
    echo "Server Name : $SERVER_NAME"
    read -p "are these values correct (y/n)?" ANSWER
    if [[ $ANSWER =~ ^[Yy] ]]; then
      VALID=true
    else
      VALID=false
    fi
  done

  isAgentKeyValid
}

function prepare-agents() {


########## STEP 3 ##########
  printf "#!/bin/bash\n\nif [ \"\$EUID\" -ne 0 ]\n  then echo \"Please run as root\"\n  exit\nfi\n\nwhile getopts \"z:\" opt; do\n  case \$opt in\n    z)\n      ZONE="\$OPTARG"\n      ;;\n    \?)\n      echo \"Invalid option: -\$OPTARG\" >&2\n      exit 1\n      ;;\n  esac\ndone\n\nif [ ! \"\$ZONE\" ]; then\n  echo \"please provide a zone using -z option\"\n  echo \"syntax: instana_static_agent_<DISTRO>.sh -z <zone-name>\"\n  exit 1\nfi\nSERVER_NAME=$SERVER_NAME\nACCESS_KEY=$FINAL_ACCESS_KEY\n_self=\"\${0##*/}\"\n\n#set file marker and create tmp dir\nCUR_DIR=\`pwd\`\nFILE_MARKER=\`awk '/^RPM FILE:/ { print NR + 1; exit 0; }' \$CUR_DIR/\$_self\`\nTMP_DIR=\`mktemp -d /tmp/instana-self-extract.XXXXXX\`\n\n# Extract the file using pipe\ntail -n+\$FILE_MARKER \$CUR_DIR/\$_self  > \$TMP_DIR/setup.rpm\n\n#Install the agent\necho \" *** installing agent ***\"\nrpm --quiet -i \$TMP_DIR/setup.rpm\n\n# configure agent\necho \" *** configure agent ***\"\n# create a fresh copy of Backend.cfg file\ncp /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg.template /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\n# set appropriate values\nsed -i -e 's/host=\${env:INSTANA_HOST}/host='\$SERVER_NAME'/' /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\nsed -i -e 's/port=\${env:INSTANA_PORT}/port=1444/' /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\nsed -i -e 's/key=\${env:INSTANA_KEY}/key='\$FINAL_ACCESS_KEY'/' /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\nsed -i 's/#com.instana.plugin.generic.hardware:/com.instana.plugin.generic.hardware:/' /opt/instana/agent/etc/instana/configuration.yaml\nsed -i '0,/#  enabled: true/{s/#  enabled: true/  enabled: true/}' /opt/instana/agent/etc/instana/configuration.yaml\nsed -i \"s@#  availability-zone: 'Datacenter A / Rack 42'@  availability-zone: '\$ZONE'@\" /opt/instana/agent/etc/instana/configuration.yaml\n\n#restart agent\nsystemctl restart instana-agent\n\nexit 0\n\nRPM FILE:\n">$AGENT_DIR/setup_RPM.sh

  #Too lazy to make a distro control so creating 2nd file for debian distro
  printf "#!/bin/bash\n\nif [ \"\$EUID\" -ne 0 ]\n  then echo \"Please run as root\"\n  exit\nfi\n\nwhile getopts \"z:\" opt; do\n  case \$opt in\n    z)\n      ZONE="\$OPTARG"\n      ;;\n    \?)\n      echo \"Invalid option: -\$OPTARG\" >&2\n      exit 1\n      ;;\n  esac\ndone\n\nif [ ! \"\$ZONE\" ]; then\n  echo \"please provide a zone using -z option\"\n  echo \"syntax: instana_static_agent_<DISTRO>.sh -z <zone-name>\"\n  exit 1\nfi\nSERVER_NAME=$SERVER_NAME\nACCESS_KEY=$FINAL_ACCESS_KEY\n_self=\"\${0##*/}\"\n\n#set file marker and create tmp dir\nCUR_DIR=\`pwd\`\nFILE_MARKER=\`awk '/^RPM FILE:/ { print NR + 1; exit 0; }' \$CUR_DIR/\$_self\`\nTMP_DIR=\`mktemp -d /tmp/instana-self-extract.XXXXXX\`\n\n# Extract the file using pipe\ntail -n+\$FILE_MARKER \$CUR_DIR/\$_self  > \$TMP_DIR/setup.deb\n\n#Install the agent\necho \" *** installing agent ***\"\napt install -q \$TMP_DIR/setup.deb\n\n# configure agent\necho \" *** configure agent ***\"\n# create a fresh copy of Backend.cfg file\ncp /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg.template /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\n# set appropriate values\nsed -i -e 's/host=\${env:INSTANA_HOST}/host='\$SERVER_NAME'/' /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\nsed -i -e 's/port=\${env:INSTANA_PORT}/port=1444/' /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\nsed -i -e 's/key=\${env:INSTANA_KEY}/key='\$FINAL_ACCESS_KEY'/' /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\nsed -i 's/#com.instana.plugin.generic.hardware:/com.instana.plugin.generic.hardware:/' /opt/instana/agent/etc/instana/configuration.yaml\nsed -i '0,/#  enabled: true/{s/#  enabled: true/  enabled: true/}' /opt/instana/agent/etc/instana/configuration.yaml\nsed -i \"s@#  availability-zone: 'Datacenter A / Rack 42'@  availability-zone: '\$ZONE'@\" /opt/instana/agent/etc/instana/configuration.yaml\n\n#restart agent\nsystemctl restart instana-agent\n\nexit 0\n\nRPM FILE:\n">$AGENT_DIR/setup_DEB.sh

  ########## STEP 4 ##########

    cat $AGENT_DIR/setup_RPM.sh $AGENT_DIR/rhel6/*.rpm > $AGENT_DIR/rhel6/instana_static_agent_rhel6.sh
    chmod +x $AGENT_DIR/rhel6/instana_static_agent_rhel6.sh
    cat $AGENT_DIR/setup_RPM.sh $AGENT_DIR/rhel7/*.rpm > $AGENT_DIR/rhel7/instana_static_agent_rhel7.sh
    chmod +x $AGENT_DIR/rhel7/instana_static_agent_rhel7.sh
    cat $AGENT_DIR/setup_DEB.sh $AGENT_DIR/debian_amd64/*.deb > $AGENT_DIR/debian_amd64/instana_static_agent_debian.sh
    chmod +x $AGENT_DIR/debian_amd64/instana_static_agent_debian.sh
    cat $AGENT_DIR/setup_RPM.sh $AGENT_DIR/centos_x86_64/*.rpm > $AGENT_DIR/centos_x86_64/instana_static_agent_centos.sh
    chmod +x $AGENT_DIR/centos_x86_64/instana_static_agent_centos.sh
    cat $AGENT_DIR/setup_RPM.sh $AGENT_DIR/aarch64_rpm/*.rpm > $AGENT_DIR/aarch64_rpm/instana_static_agent_aarch64.sh
    chmod +x $AGENT_DIR/aarch64_rpm/instana_static_agent_aarch64.sh
    cat $AGENT_DIR/setup_RPM.sh $AGENT_DIR/s390_rpm/*.rpm > $AGENT_DIR/s390_rpm/instana_static_agent_s390_rpm.sh
    chmod +x $AGENT_DIR/s390_rpm/instana_static_agent_s390_rpm.sh
    cat $AGENT_DIR/setup_DEB.sh $AGENT_DIR/s390_deb/*.deb > $AGENT_DIR/s390_deb/instana_static_agent_s390_deb.sh
    chmod +x $AGENT_DIR/s390_deb/instana_static_agent_s390_deb.sh
    cat $AGENT_DIR/setup_DEB.sh $AGENT_DIR/arm_deb/*.deb > $AGENT_DIR/arm_deb/instana_static_agent_arm_deb.sh
    chmod +x $AGENT_DIR/arm_deb/instana_static_agent_arm_deb.sh

    rm -f $AGENT_DIR/rhel7/*.rpm $AGENT_DIR/rhel6/*.rpm $AGENT_DIR/debian_amd64/*.deb $AGENT_DIR/centos_x86_64/*.rpm $AGENT_DIR/aarch64_rpm/*.rpm $AGENT_DIR/s390_rpm/*.rpm $AGENT_DIR/s390_deb/*.deb $AGENT_DIR/arm_deb/*.deb
    rm -f $AGENT_DIR/*.sh $AGENT_DIR/agentlist
}

function create_agent_tar(){
  echo "packaging agents repo"
  cd $AGENT_DIR
  tar -czf $CUR_DIR/instana_agent_repo.tar.gz *
}

function agent_bundle() {

  get-agents-inputs
  get-agents $FINAL_ACCESS_KEY
  prepare-agents
  create_agent_tar
}

