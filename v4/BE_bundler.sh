######################################################################################
# Bundler for offline Instana installation 
#   by Alexandre MECHAIN - Instana
#
# This script will generate a self extractable file with all required packages to
# install Instana AP fully offline I
#
# You must run this script on Centos/RHEL to create a bundle for that environment
# You must run this script on Debian/Ubuntu to create a bundle for that environment
# You must have an internet connection to run that script
# You must have a valid agent key to create the bundle (doesn't need to be the final 
#  one form your customer license
#  
# As root run ./bundler_v2.sh -a <agent-key>
# This will generate an approx. 3Gb file called instana_setup.sh
# 
# For any questions please send an email to : alex.mechain@instana.com
######################################################################################

set -o pipefail
export LC_ALL=C

PLATFORM="unknown"
DISTRO="unknown"
FAMILY="unknown"
#v3.2
INSTANA_VER="unknown"


function detectOS() {
  if test -f /etc/issue; then
    PLATFORM=`cat /etc/issue | head -n 1`
    DISTRO=`echo $PLATFORM | awk '{print $1}'`
  fi

  if test -f /etc/redhat-release; then
    PLATFORM=`cat /etc/redhat-release`
    DISTRO=`echo $PLATFORM | awk '{print $1}'`
  fi

  if test -f /usr/bin/lsb_release; then
    VERSION=`lsb_release -r | awk '{print $2}'`
  else
    if [ "$DISTRO" = "CentOS" ]; then
      if [ "`echo $PLATFORM | awk '{print $2}'`" = "Linux" ]; then
        VERSION=`echo $PLATFORM | awk '{print $4}'`
      else
        VERSION=`echo $PLATFORM | awk '{print $3}'`
      fi
    fi
  fi

  if [ "$DISTRO" = "Red" ]; then
    DISTRO="RHEL"
    VERSION=`echo $PLATFORM | awk '{print $7}'`
  fi
}

function set_family() {
  local distro=$1
  if [ "$distro" = "CentOS" ] || [ "$distro" = "RHEL" ]; then
    FAMILY=yum
  fi

  if [ "$distro" = "Ubuntu" ] || [ "$distro" = "Debian" ]; then
    FAMILY=apt
  fi
  echo "Distrib is $DISTRO"
  echo "Version is $VERSION"
}
detectOS
set_family $DISTRO

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

CLEAN=1

while getopts "a:n" opt; do
  case $opt in
    a)
      ACCESS_KEY="$OPTARG"
      ;;
    n)
      CLEAN=0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

echo "detected Linux Distribution: $DISTRO"
echo "setting family to $FAMILY"


if [ ! "$ACCESS_KEY" ]; then
  echo "-a ACCES_KEY required!"
  exit 1
fi

PKG_URI=packages.instana.io
DEB_URI="${PKG_URI}/release"
YUM_URI="${PKG_URI}/release"
MACHINE=x86_64
gpg_uri="https://${PKG_URI}/Instana.gpg"
CUR_DIR=`pwd`

function get-instana-packages() {
#This creates the Instana repo file based on access key used to download all required rpm file for back end installation
#This function downloads all necessary rpm files for back end installation. All rpm packages will be stored in folder /localrepo/
#It also createslocal repo file that will be used for creating local repo.
#This file is used during the local repo creation (where bundler get executed) and during the back end installation

# Step 1: add instana repo file to repo list and create local.repo file
# Step 2: prepare env and set list of necessary packages
# Step 3: Download of all rpm package (this is a point of failure since there is no guarantee this package list will last forever.
#       With any new major version, new package can appear and therefore list have to be updated

REPO_FOLDER=/localrepo/
if [ ! -d "$REPO_FOLDER" ]; then 
  mkdir $REPO_FOLDER
fi

local family=$1
if [ "$family" = "yum" ]; then
  #Pre-req to bundle
  yum install -y createrepo
  ########## STEP 1 ##########
  echo " * create instana repo file"
  printf "[instana-product]\nname=Instana-Product\nbaseurl=https://_:"$ACCESS_KEY"@"$YUM_URI"/product/rpm/generic/"$MACHINE"\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey="$gpg_uri"\nsslverify=1" >/etc/yum.repos.d/Instana-Product.repo
  echo " * create local repo file"
  printf "[rhel7]\nname=rhel7\nbaseurl=file:///localrepo/\nenabled=1\ngpgcheck=0" >$CUR_DIR/local.repo
  curl -s -o $CUR_DIR/instana.gpg $gpg_uri
  rpm --import $CUR_DIR/instana.gpg
# This doesn't work with build 145. Some items are "void" when displaying list of instana packages
yum --disablerepo="*" --enablerepo="instana-product" list available | awk '(NR>=3) {print $1}' > $CUR_DIR/list_package
#  echo "nginx">>list_package

# Workaround: feeding list_package with arbitrary list of required packages
# this list might nor work for further releases.
#Array=( "cassandra.noarch" "cassandra-migrator.noarch" "cassandra-tools.noarch" "chef-cascade.x86_64" "clickhouse.x86_64" "elastic-migrator.x86_64" "elasticsearch.noarch" "instana-acceptor.noarch" "instana-appdata-legacy-converter.noarch" "instana-appdata-processor.noarch" "instana-appdata-reader.noarch" "instana-appdata-writer.noarch" "instana-butler.noarch" "instana-cashier.noarch" "instana-common.x86_64" "instana-commonap.x86_64" "instana-eum-acceptor.noarch" "instana-eum-processor.norarch" "instana-filler.noarch" "instana-groundskeeper.noarch" "instana-issue-tracker.noarch" "instana-jre.x86_64" "instana-processor.noarch" "instana-ruby.x86_64" "instana-ui-backend.noarch" "instana-ui-client.noarch" "kafka.noarch" "mason.noarch" "mongodb.x86_64" "nginx.x86_64" "nodejs.x86_64" "onprem-cookbooks.noarch" "postgres-migrator.x86_64" "postgresql.x86_64" "postgresql-libs.x86_64" "postgresql-static.x86_64" "redis.x86_64" "zookeeper.noarch")
#  for item in "${Array[@]}"; do
#    echo "$item" >>$CUR_DIR/list_package
#  done
# End of Workaround

  ########## STEP 3 ##########
  echo " * download list of necessary repos"
  #V2 change
  while read -r line; do
       echo "downloading $line"
       yumdownloader -q "$line" --destdir=/localrepo/
  done < $CUR_DIR/list_package
  #v3.2
  INSTANA_VER=`yum list | grep instana-commonap | awk '{print $2}' | awk -F'.' '{print $2}'`

else
  wget -qO - "https://${PKG_URI}/Instana.gpg" | apt-key add

  echo " * create instana repo file"
  printf "deb [arch=amd64] https://_:"$ACCESS_KEY"@"$DEB_URI"/product/deb generic main" >/etc/apt/sources.list.d/Instana-Product.list
  echo " * update repo list"
  apt-get update>>/dev/null

  #package required to prepare local repo
  apt install dpkg-dev apt-rdepends
  chown -R _apt:root $REPO_FOLDER
  grep ^Package: /var/lib/apt/lists/packages.instana.io_release_product_deb_dists_generic_main_binary-amd64_Packages | awk '{print $2}' > $CUR_DIR/list_package
  echo "nginx" >> $CUR_DIR/list_package
  echo "nginx-extras" >> $CUR_DIR/list_package
  ########## STEP 3 ##########
    #create dependencies list
    echo " * buidling dependency list"
    while read -r line; do
      echo "ligne="$line
      apt-rdepends "$line"|grep -v "^ ">>$REPO_FOLDER/dep.list
    done < $CUR_DIR/list_package

    sort -u $REPO_FOLDER/dep.list > $REPO_FOLDER/dep_sorted.list
    rm $REPO_FOLDER/dep.list
    #download dependency packages
    while read -r line
    do
      cd $REPO_FOLDER
      apt download "$line"
    done < "$REPO_FOLDER/dep_sorted.list"

    #restoring legitimate user
    chown -R root:root $REPO_FOLDER
    INSTANA_VER=`apt-cache policy instana-appdata-processor | grep Candidate | awk -F'.' '{print $2}'`
fi

  echo " * download complete "

}

function create-offline-setup-file() {

  cp full_setup.sh $CUR_DIR/offline.sh
}

function package-offline() {
#This package everything into a single tar ball
#Step 1: Env preparation/backup of existing repo file and replacement by local repo file. Create local repo DB
#Step 2: Restoring repo to original
#Step 3: create a tar file containing all packages + local repo file references created during step1
#Step 4: repackage everything into a single file
local family=$1

  echo " * backup existing repo and prepare local repo"
  if [ "$family" = "yum" ]; then
    ########## STEP1 ##########
    mkdir $CUR_DIR/backup && mv -f /etc/yum.repos.d/* $CUR_DIR/backup
    cp $CUR_DIR/local.repo /etc/yum.repos.d/
    createrepo /localrepo/
    ########## STEP2 ##########
    rm -f /etc/yum.repos.d/local.repo
    cp $CUR_DIR/backup/* /etc/yum.repos.d/
  else
    ########## STEP1 ##########
    #create package repo
    cd $REPO_FOLDER
    dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
    dpkg-scansources . /dev/null | gzip -9c > Sources.gz
  fi

########## STEP3 ##########
  tar -czf $CUR_DIR/instana_backend_repo.tar.gz $CUR_DIR/local.repo /localrepo/


########## STEP5 ##########
  
#  echo " * package everything"
#  cd $CUR_DIR

#v3.2
#replace VERSION_TAG by the current INSTANA version in newly create instana_setup.sh before packaging 
  sed -i 's/VERSION_TAG/INSTANA_VER='$INSTANA_VER'/' offline.sh


#tar -czf instana_offline.tar.gz instana_backend_repo.tar.gz instana_agent_repo.tar.gz local.repo
#v3.2: package name now contains both Instana version and creation date  
  #cat offline.sh instana_offline.tar.gz >instana_setup.sh
  cat offline.sh instana_backend_repo.tar.gz >instana_setup_ver"$INSTANA_VER"_`date +%y%m%d`.sh
}

#function final-cleanup() {
#General cleanup

#  echo " * cleaning up"
  #Removal of local repo files and restore original repo files
# rm -Rf /localrepo/

  #Removal of intermediate files
#  rm -f $CUR_DIR/instana_backend_repo.tar.gz $CUR_DIR/instana_agent_repo.tar.gz $CUR_DIR/offline.sh $CUR_DIR/local.repo
#  rm -Rf $CUR_DIR/agents
#}

# Download and prepar agents pack
#get-agents

# Prepapre Instana repo and download packages
get-instana-packages $FAMILY

# create setup file
create-offline-setup-file

#package everything
package-offline $FAMILY

#deactivable cleanup
#if [ "$CLEAN" == 1 ]; then
#  final-cleanup
#fi

exit 0
