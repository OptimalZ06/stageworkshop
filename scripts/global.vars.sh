#!/usr/bin/env bash

# shellcheck disable=SC2034
          RELEASE='release.json'
# Sync the following to lib.common.sh::ntnx_download-Case=PC
# Browse to: https://portal.nutanix.com/#/page/releases/prismDetails
# - Find ${PC_VERSION} in the Additional Releases section on the lower right side
# - Provide the metadata URL for the "PC 1-click deploy from PE" option to PC_*_METAURL
   PC_DEV_VERSION='5.10.1.1'
   PC_DEV_METAURL='http://download.nutanix.com/pc/one-click-pc-deployment/5.10.1.1/pcdeploy-5.10.1.1.json'
PC_STABLE_VERSION='5.8.2'
PC_STABLE_METAURL='http://download.nutanix.com/pc/one-click-pc-deployment/5.8.2/v1/pc_deploy-5.8.2.json'
# Sync the following to lib.common.sh::ntnx_download-Case=FILES
# Browse to: https://portal.nutanix.com/#/page/releases/afsDetails?targetVal=GA
# - Find ${FILES_VERSION} in the Additional Releases section on the lower right side
# - Provide "Upgrade Metadata File" URL to FILES_METAURL
    FILES_VERSION='3.2.0.1'
    FILES_METAURL='http://download.nutanix.com/afs/7.3/nutanix-afs-el7.3-release-afs-3.2.0.1-stable-metadata.json'
    # 2019-02-15: override until metadata URL fixed
        #FILES_URL='https://s3.amazonaws.com/get-ahv-images/nutanix-afs-el7.3-release-afs-3.2.0.1-stable.qcow2'
    FILES_VERSION='3.2.0'
    FILES_METAURL='http://download.nutanix.com/afs/3.2.0/v1/afs-3.2.0.json'

NTNX_INIT_PASSWORD='nutanix/4u'
       PRISM_ADMIN='admin'
        SSH_PUBKEY="${HOME}/.ssh/id_rsa.pub"
      STORAGE_POOL='SP01'
   STORAGE_DEFAULT='Default'
    STORAGE_IMAGES='Images'

 # Conventions for *_REPOS arrays -- the URL must end with either:
 # - trailing slash, which imples _IMAGES argument to function repo_source()
 # - or full package filename.

 # https://stedolan.github.io/jq/download/#checksums_and_signatures
      JQ_REPOS=(\
       'https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64' \
 )
   QCOW2_REPOS=(\
    'http://10.42.8.50/images/' \
    'http://10.21.250.221/images/tech-enablement/' \
    'http://10.21.250.221/images/ahv/techsummit/' \
    'http://10.132.128.50:81/share/saved-images/' \
    'https://s3.amazonaws.com/get-ahv-images/' \
 ) # talk to Nathan.C to populate S3, Sharon.S to populate Daisy File Share
  QCOW2_IMAGES=(\
   CentOS7.qcow2 \
   Windows2016.qcow2 \
   Windows2012R2.qcow2 \
   Windows10-1709.qcow2 \
   CentOS7.iso \
   Windows2016.iso \
   Windows2012R2.iso \
   Windows10.iso \
   Nutanix-VirtIO-1.1.3.iso \
   'https://s3.amazonaws.com/technology-boot-camp/ERA-Server-build-1.0.0-21edfbc990a8f3424fed146d837483cb1a00d56d.qcow2' \
   'http://download.nutanix.com/karbon/0.8/acs-centos7.qcow2' \
 )
 # "XenDesktop-7.15.iso" http://10.21.250.221/images/ahv/techsummit/XD715.iso
 # http://download.nutanix.com/era/1.0.0/ERA-Server-build-1.0.0-bae7ca0d653e1af2bcb9826d1320e88d8c4713cc.qcow2

 # https://pkgs.org/download/sshpass
 # https://sourceforge.net/projects/sshpass/files/sshpass/
   SSHPASS_REPOS=(\
    'http://mirror.centos.org/centos/7/extras/x86_64/Packages/sshpass-1.06-2.el7.x86_64.rpm' \
 )

# shellcheck disable=2206
          OCTET=(${PE_HOST//./ }) # zero index
    IPV4_PREFIX=${OCTET[0]}.${OCTET[1]}.${OCTET[2]}
DATA_SERVICE_IP=${IPV4_PREFIX}.$((${OCTET[3]} + 1))
        PC_HOST=${IPV4_PREFIX}.$((${OCTET[3]} + 2))
    DNS_SERVERS='8.8.8.8'
    NTP_SERVERS='0.us.pool.ntp.org,1.us.pool.ntp.org,2.us.pool.ntp.org,3.us.pool.ntp.org'
       NW1_NAME='Primary'
       NW1_VLAN=0
# Assuming HPOC defaults
     NW1_SUBNET="${IPV4_PREFIX}.1/25"
 NW1_DHCP_START="${IPV4_PREFIX}.50"
   NW1_DHCP_END="${IPV4_PREFIX}.125"
# https://sewiki.nutanix.com/index.php/Hosted_POC_FAQ#I.27d_like_to_test_email_alert_functionality.2C_what_SMTP_server_can_I_use_on_Hosted_POC_clusters.3F
SMTP_SERVER_ADDRESS='nutanix-com.mail.protection.outlook.com'
   SMTP_SERVER_FROM='NutanixHostedPOC@nutanix.com'
   SMTP_SERVER_PORT=25

    AUTH_SERVER='AutoDC' # default; TODO:180 refactor AUTH_SERVER choice to input file
      AUTH_HOST="${IPV4_PREFIX}.$((${OCTET[3]} + 3))"
      LDAP_PORT=389
      AUTH_FQDN='ntnxlab.local'
    AUTH_DOMAIN='NTNXLAB'
AUTH_ADMIN_USER='administrator@'${AUTH_FQDN}
AUTH_ADMIN_PASS='nutanix/4u'
AUTH_ADMIN_GROUP='SSP Admins'
   AUTODC_REPOS=(\
  'http://10.21.250.221/images/ahv/techsummit/AutoDC.qcow2' \
  'https://s3.amazonaws.com/get-ahv-images/AutoDC-04282018.qcow2' \
  'nfs://pocfs.nutanixdc.local/images/CorpSE_Calm/autodc-2.0.qcow2' \
 # 'smb://pocfs.nutanixdc.local/images/CorpSE_Calm/autodc-2.0.qcow2' \
  'http://10.59.103.143:8000/autodc-2.0.qcow2' \
)

# For Nutanix HPOC/Marketing clusters (10.20, 10.21, 10.55, 10.42)
# https://sewiki.nutanix.com/index.php/HPOC_IP_Schema
case "${OCTET[0]}.${OCTET[1]}" in
  10.20 ) #Marketing: us-west = SV
    DNS_SERVERS='10.21.253.10'
    ;;
  10.21 ) #HPOC: us-west = SV
    if (( ${OCTET[2]} == 60 )) || (( ${OCTET[2]} == 77 )); then
      log 'GPU cluster, aborting! See https://sewiki.nutanix.com/index.php/Hosted_Proof_of_Concept_(HPOC)#GPU_Clusters'
      exit 0
    fi

    # backup cluster; override relative IP addressing
    if (( ${OCTET[2]} == 249 )); then
      AUTH_HOST="${IPV4_PREFIX}.118"
        PC_HOST="${IPV4_PREFIX}.119"
    fi

       DNS_SERVERS='10.21.253.10,10.21.253.11'
          NW2_NAME='Secondary'
          NW2_VLAN=$(( ${OCTET[2]} * 10 + 1 ))
        NW2_SUBNET="${IPV4_PREFIX}.129/25"
    NW2_DHCP_START="${IPV4_PREFIX}.132"
      NW2_DHCP_END="${IPV4_PREFIX}.253"
    ;;
  10.55 ) # HPOC us-east = DUR
       DNS_SERVERS='10.21.253.11'
          NW2_NAME='Secondary'
          NW2_VLAN=$(( ${OCTET[2]} * 10 + 1 ))
        NW2_SUBNET="${IPV4_PREFIX}.129/25"
    NW2_DHCP_START="${IPV4_PREFIX}.132"
      NW2_DHCP_END="${IPV4_PREFIX}.253"
    ;;
  10.42 ) # HPOC us-west = PHX
       DNS_SERVERS='10.42.196.10'
          NW2_NAME='Secondary'
          NW2_VLAN=$(( ${OCTET[2]} * 10 + 1 ))
        NW2_SUBNET="${IPV4_PREFIX}.129/25"
    NW2_DHCP_START="${IPV4_PREFIX}.132"
      NW2_DHCP_END="${IPV4_PREFIX}.253"
    ;;
  10.132 ) # https://sewiki.nutanix.com/index.php/SH-COLO-IP-ADDR
       DNS_SERVERS='10.132.71.40'
        NW1_SUBNET="${IPV4_PREFIX%.*}.128.4/17"
    NW1_DHCP_START="${IPV4_PREFIX}.100"
      NW1_DHCP_END="${IPV4_PREFIX}.250"
      # PC deploy file local override, TODO:30 make an PC_URL array and eliminate
               PC_URL=http://10.132.128.50/E%3A/share/Nutanix/PrismCentral/pc-${PC_VERSION}-deploy.tar
       PC_DEV_METAURL=http://10.132.128.50/E%3A/share/Nutanix/PrismCentral/pc-${PC_VERSION}-deploy-metadata.json
    PC_STABLE_METAURL=${PC_DEV_METAURL}

    QCOW2_IMAGES=(\
      Centos7-Base.qcow2 \
      Centos7-Update.qcow2 \
      Windows2012R2.qcow2 \
      panlm-img-52.qcow2 \
      kx_k8s_01.qcow2 \
      kx_k8s_02.qcow2 \
      kx_k8s_03.qcow2 \
    )
    ;;
esac

HTTP_CACHE_HOST='localhost'
HTTP_CACHE_PORT=8181

   ATTEMPTS=40
      SLEEP=60 # pause (in seconds) between ATTEMPTS

     CURL_OPTS='--insecure --silent --show-error' # --verbose'
CURL_POST_OPTS="${CURL_OPTS} --max-time 5 --header Content-Type:application/json --header Accept:application/json --output /dev/null"
CURL_HTTP_OPTS="${CURL_POST_OPTS} --write-out %{http_code}"
      SSH_OPTS='-o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null'
     SSH_OPTS+=' -q' # -v'

# Find operating system and set dependencies
if [[ -e /etc/lsb-release ]]; then
  # Linux Standards Base
  OS_NAME="$(grep DISTRIB_ID /etc/lsb-release | awk -F= '{print $2}')"
elif [[ -e /etc/os-release ]]; then
  # CPE = https://www.freedesktop.org/software/systemd/man/os-release.html
  OS_NAME="$(grep '^ID=' /etc/os-release | awk -F= '{print $2}')"
elif [[ $(uname -s) == 'Darwin' ]]; then
  OS_NAME='Darwin'
fi

WC_ARG='--lines'
if [[ ${OS_NAME} == 'Darwin' ]]; then
  WC_ARG='-l'
fi
