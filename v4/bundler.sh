#bundler

#1 make a BE/AGENT single package
#2 make a BE package
#3 make a AGENT package
source agents_bundler.sh

function default-prompt() {
  echo "*************************************************************************"
  echo "*              Welcome in Instana offline bundler                       *"
  echo "*                                                                       *"    
  echo "* WARNING: THIS UTILITY IS MEANT TO BE USED WITH CAUTION.               *"
  echo "* IT GENERATES A NON-OFFICIAL INSTALLATION PACKAGE OF INSTANA PRODUCT,  *"
  echo "* DESIGNED TO BE USED UNDER INSTANA SOLUTION ARCHITECT RESPONSABILITY   *"
  echo "*                                                                       *"
  echo "*    For any questions or assistance,                                   *"
  echo "*     please contact alex.mechain@instana.com                           *"
  echo "*************************************************************************"
  echo
  echo
  echo "*************************************************************************"
  echo "* What do you want to do?                                               *"
  echo "* 1 - Create a full offline package (Include BackEnd and Static Agents) *"
  echo "* 2 - Create a BackEnd only offline package                             *"
  echo "* 3 - Create a Static Agent only offline package                        *"
  echo "*************************************************************************"
  echo ""
  echo "Pick a choice (1, 2, or 3)"
  read CHOICE
  
  case "$CHOICE" in
  "1")
      echo "Preparing full Instana bundle"
      full_bundle
      ;;
  "2")
      echo "Preparing BackEnd only bundle"
      BE_bundle
      ;;
  "3")
      echo "Preparing Static Agents bundle"
      agent_bundle
      ;;
  *)
      echo "Wrong choice. Please start over"
      exit 0
      ;;
  esac
}

default-prompt
