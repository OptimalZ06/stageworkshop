#!/usr/bin/env bash
# -x

#__main()__________

# Source Nutanix environment (PATH + aliases), then common routines + global variables
. /etc/profile.d/nutanix_env.sh
. lib.common.sh
. global.vars.sh
begin

args_required 'EMAIL PE_PASSWORD PC_VERSION'

#dependencies 'install' 'jq' && ntnx_download 'PC' & #attempt at parallelization
# Some parallelization possible to critical path; not much: would require pre-requestite checks to work!

case ${1} in
  PE | pe )
    . lib.pe.sh

    export PC_DEV_VERSION='5.10.1.1'
    export PC_DEV_METAURL='http://10.42.8.50/images/pcdeploy-5.10.1.1.json'
    export         PC_URL='http://10.42.8.50/images/x.tar.gz'
    export  FILES_VERSION='3.2.0'
    export  FILES_METAURL='http://10.42.8.50/images/afs-3.2.0.json'
    export      FILES_URL='http://10.42.8.50/images/x.tar.qcow2'

    args_required 'PE_HOST PC_LAUNCH'
    ssh_pubkey & # non-blocking, parallel suitable

    dependencies 'install' 'sshpass' && dependencies 'install' 'jq' \
    && pe_license \
    && pe_init \
    && network_configure \
    && authentication_source \
    && pe_auth

    if (( $? == 0 )) ; then
      pc_install "${NW1_NAME}" \
      && prism_check 'PC' \
      && pc_configure \
      && dependencies 'remove' 'sshpass' && dependencies 'remove' 'jq'

      log "PC Configuration complete: Waiting for PC deployment to complete, API is up!"
      log "PE = https://${PE_HOST}:9440"
      log "PC = https://${PC_HOST}:9440"

      files_install & # parallel, optional. Versus: $0 'files' &

      finish
    else
      finish
      _error=18
      log "Error ${_error}: in main functional chain, exit!"
      exit ${_error}
    fi
  ;;
  PC | pc )
    . lib.pc.sh

    export QCOW2_REPOS=(\
     'http://10.42.8.50/images/' \
     'https://s3.amazonaws.com/get-ahv-images/' \
    ) # talk to Nathan.C to populate S3, Sharon.S to populate Daisy File Share
    export QCOW2_IMAGES=(\
      CentOS7.qcow2 \
      Windows2016.qcow2 \
      Windows2012R2.qcow2 \
      Windows10-1709.qcow2 \
      ToolsVM.qcow2 \
      CentOS7.iso \
      Windows2012R2.iso \
      SQLServer2014SP3.iso \
      Nutanix-VirtIO-1.1.3.iso \
      acs-centos7.qcow2 \
      acs-ubuntu1604.qcow2 \
      xtract-vm-2.0.3.qcow2 \
      ERA-Server-build-1.0.1.qcow2 \
      sherlock-k8s-base-image_320.qcow2 \
      hycu-3.5.0-6138.qcow2 \
      VeeamAvailability_1.0.457.vmdk \
      VeeamBR_9.5.4.2615.Update4.iso \
    )

    dependencies 'install' 'jq' || exit 13

    ssh_pubkey & # non-blocking, parallel suitable

    pc_passwd
    ntnx_cmd # check cli services available?

    export   NUCLEI_SERVER='localhost'
    export NUCLEI_USERNAME="${PRISM_ADMIN}"
    export NUCLEI_PASSWORD="${PE_PASSWORD}"
    # nuclei -debug -username admin -server localhost -password x vm.list

    if [[ -z "${PE_HOST}" ]]; then # -z ${CLUSTER_NAME} || #TOFIX
      log "CLUSTER_NAME=|${CLUSTER_NAME}|, PE_HOST=|${PE_HOST}|"
      pe_determine ${1}
      . global.vars.sh # re-populate PE_HOST dependencies
    fi

    if [[ ! -z "${2}" ]]; then # hidden bonus
      log "Don't forget: $0 first.last@nutanixdc.local%password"
      calm_update && exit 0
    fi

    export ATTEMPTS=2
    export    SLEEP=10

    pc_init \
    && pc_dns_add \
    && pc_ui \
    && pc_auth \
    && pc_smtp

    ssp_auth \
    && calm_enable \
    && lcm \
    && images \
    && pc_cluster_img_import \
    && prism_check 'PC'

    log "Non-blocking functions (in development) follow."
    pc_project
    flow_enable
    pc_admin
    # ntnx_download 'AOS' # function in lib.common.sh

    unset NUCLEI_SERVER NUCLEI_USERNAME NUCLEI_PASSWORD

    if (( $? == 0 )); then
      #dependencies 'remove' 'sshpass' && dependencies 'remove' 'jq' \
      #&&
      log "PC = https://${PC_HOST}:9440"
      finish
    else
      _error=19
      log "Error ${_error}: failed to reach PC!"
      exit ${_error}
    fi
  ;;
  FILES | files | afs )
    files_install
  ;;
esac
