#!/usr/bin/env bash
# -x
# Dependencies: acli, ncli, jq, sshpass, curl, md5sum, pgrep, wc, tr, pkill

function acli() {
  local _cmd

  _cmd=$*
	/usr/local/nutanix/bin/acli ${_cmd}
  # DEBUG=1 && if [[ ${DEBUG} ]]; then log "$@"; fi
}

function authentication_source() {
  local   _attempts
  local      _error=13
  local       _loop
  local _pc_version
  local     _result
  local      _sleep
  local       _test=0
  local         _vm

  args_required 'AUTH_SERVER AUTH_FQDN SLEEP STORAGE_IMAGES PC_VERSION'

  if [[ -z ${AUTH_SERVER} ]]; then
    log "Error ${_error}: please provide a choice for authentication server."
    exit ${_error}
  fi
  # shellcheck disable=2206
  _pc_version=(${PC_VERSION//./ })

  case "${AUTH_SERVER}" in
    'ActiveDirectory')
      log "Manual setup = https://github.com/nutanixworkshops/labs/blob/master/setup/active_directory/active_directory_setup.rst"
      ;;
    'AutoDC')
      local    _autodc_auth
      local   _autodc_index=1
      local _autodc_release=1
      local _autodc_service='samba-ad-dc'
      local _autodc_restart="service ${_autodc_service} restart"
      local  _autodc_status="systemctl show ${_autodc_service} --property=SubState"
      local _autodc_success='SubState=running'

      if (( ${_pc_version[0]} >= 5 && ${_pc_version[1]} >= 9 )); then
        log "PC_VERSION ${PC_VERSION} >= 5.9, setting AutoDC-2.0..."
           _autodc_auth=" --username=${AUTH_ADMIN_USER} --password=${AUTH_ADMIN_PASS}"
          _autodc_index=''
        _autodc_release=2
        _autodc_service=samba
        _autodc_restart="sleep 2 && service ${_autodc_service} stop && sleep 5 && service ${_autodc_service} start"
         _autodc_status="service ${_autodc_service} status"
        _autodc_success=' * status: started'

        # REVIEW: override global.vars
        export AUTODC_REPOS=(\
         'http://10.132.128.50:81/share/saved-images/autodc-2.0.qcow2' \
         'nfs://pocfs.nutanixdc.local/images/CorpSE_Calm/autodc-2.0.qcow2' \
        # 'smb://pocfs.nutanixdc.local/images/CorpSE_Calm/autodc-2.0.qcow2' \
         'https://s3.amazonaws.com/get-ahv-images/AutoDC2.qcow2' \
         'http://10.59.103.143:8000/autodc-2.0.qcow2' \
        )
      fi

      dns_check "dc${_autodc_index}.${AUTH_FQDN}"
      _result=$?

      if (( ${_result} == 0 )); then
        log "${AUTH_SERVER}${_autodc_release}.IDEMPOTENCY: dc${_autodc_index}.${AUTH_FQDN} set, skip. ${_result}"
      else
        log "${AUTH_SERVER}${_autodc_release}.IDEMPOTENCY failed, no DNS record dc${_autodc_index}.${AUTH_FQDN}"

        _error=12
         _loop=0
        _sleep=${SLEEP}

        repo_source AUTODC_REPOS[@]

        if (( $(source /etc/profile.d/nutanix_env.sh && acli image.list | grep ${AUTH_SERVER}${_autodc_release} | wc --lines) == 0 )); then
          log "Import ${AUTH_SERVER}${_autodc_release} image from ${SOURCE_URL}..."
          acli image.create ${AUTH_SERVER}${_autodc_release} \
            image_type=kDiskImage wait=true \
            container=${STORAGE_IMAGES} source_url=${SOURCE_URL}
        else
          log "Image found, assuming ready. Skipping ${AUTH_SERVER}${_autodc_release} import."
        fi

        log "Create ${AUTH_SERVER}${_autodc_release} VM based on ${AUTH_SERVER}${_autodc_release} image"
        acli "vm.create ${AUTH_SERVER}${_autodc_release} num_vcpus=2 num_cores_per_vcpu=1 memory=2G"
        # vmstat --wide --unit M --active # suggests 2G sufficient, was 4G
        #acli "vm.disk_create ${AUTH_SERVER}${_autodc_release} cdrom=true empty=true"
        acli "vm.disk_create ${AUTH_SERVER}${_autodc_release} clone_from_image=${AUTH_SERVER}${_autodc_release}"
        acli "vm.nic_create ${AUTH_SERVER}${_autodc_release} network=${NW1_NAME} ip=${AUTH_HOST}"

        log "Power on ${AUTH_SERVER}${_autodc_release} VM..."
        acli "vm.on ${AUTH_SERVER}${_autodc_release}"

        _attempts=20
            _loop=0
           _sleep=10

        while true ; do
          (( _loop++ ))

          _test=$(remote_exec 'SSH' 'AUTH_SERVER' "${_autodc_status}")
          if [[ "${_test}" == "${_autodc_success}" ]]; then
            log "${AUTH_SERVER}${_autodc_release} is ready."
            sleep ${_sleep}
            break
          elif (( ${_loop} > ${_attempts} )); then
            log "Error ${_error}: ${AUTH_SERVER}${_autodc_release} VM running: giving up after ${_loop} tries."
            _result=$(source /etc/profile.d/nutanix_env.sh \
              && for _vm in $(source /etc/profile.d/nutanix_env.sh && acli vm.list | grep ${AUTH_SERVER}${_autodc_release}) ; do acli -y vm.delete $_vm; done)
            # acli image.delete ${AUTH_SERVER}${_autodc_release}
            log "Remediate by deleting the ${AUTH_SERVER}${_autodc_release} VM from PE (just attempted by this script: ${_result}) and then running acli $_"
            exit ${_error}
          else
            log "_test ${_loop}/${_attempts}=|${_test}|: sleep ${_sleep} seconds..."
            sleep ${_sleep}
          fi
        done

        log "Create Reverse Lookup Zone on ${AUTH_SERVER}${_autodc_release} VM..."
        _attempts=3
            _loop=0

        while true ; do
          (( _loop++ ))
          remote_exec 'SSH' 'AUTH_SERVER' \
            "samba-tool dns zonecreate dc${_autodc_index} ${OCTET[2]}.${OCTET[1]}.${OCTET[0]}.in-addr.arpa ${_autodc_auth} && ${_autodc_restart}" \
            'OPTIONAL'
          sleep ${_sleep}

          dns_check "dc${_autodc_index}.${AUTH_FQDN}"
          _result=$?

          if (( ${_result} == 0 )); then
            log "Success: DNS record dc${_autodc_index}.${AUTH_FQDN} set."
            break
          elif (( ${_loop} > ${_attempts} )); then
            if (( ${_autodc_release} < 2 )); then
              log "Error ${_error}: ${AUTH_SERVER}${_autodc_release}: giving up after ${_loop} tries; deleting VM..."
              acli "-y vm.delete ${AUTH_SERVER}${_autodc_release}"
              exit ${_error}
            fi
          else
            log "dns_check ${_loop}/${_attempts}=|${_result}|: sleep ${_sleep} seconds..."
            sleep ${_sleep}
          fi
        done

      fi
      ;;
    'OpenLDAP')
      log "To be documented, see https://drt-it-github-prod-1.eng.nutanix.com/mark-lavi/openldap"
      ;;
  esac
}

function files_install() {
  local  _ncli_softwaretype='FILE_SERVER'
  local _ncli_software_type='afs'
  local               _test

  dependencies 'install' 'jq' || exit 13

  log "IDEMPOTENCY: checking for ${_ncli_software_type} completed..."
  _test=$(source /etc/profile.d/nutanix_env.sh \
    && ncli --json=true software list \
    | jq -r \
      '.data[] | select(.softwareType == "'${_ncli_softwaretype}'") | select(.status == "COMPLETED") | .version')

  if [[ ${_test} != "${FILES_VERSION}" ]]; then
    log "Files ${FILES_VERSION} not completed. ${_test}"
    ntnx_download "${_ncli_software_type}"
  else
    log "IDEMPOTENCY: Files ${FILES_VERSION} already completed."
  fi
}

function network_configure() {
  local _network_name="${NW1_NAME}"

  if [[ ! -z "${NW2_NAME}" ]]; then
    #TODO: accommodate for X networks!
    _network_name="${NW2_NAME}"
  fi

  if [[ ! -z $(acli "net.list" | grep ${_network_name}) ]]; then
    log "IDEMPOTENCY: ${_network_name} network set, skip."
  else
    args_required 'AUTH_DOMAIN IPV4_PREFIX AUTH_HOST'

    if [[ ! -z $(acli "net.list" | grep 'Rx-Automation-Network') ]]; then
      log "Remove Rx-Automation-Network..."
      acli "-y net.delete Rx-Automation-Network"
    fi

    log "Create primary network: Name: ${NW1_NAME}, VLAN: ${NW1_VLAN}, Subnet: ${NW1_SUBNET}, Domain: ${AUTH_DOMAIN}, Pool: ${NW1_DHCP_START} to ${NW1_DHCP_END}"
    acli "net.create ${NW1_NAME} vlan=${NW1_VLAN} ip_config=${NW1_SUBNET}"
    acli "net.update_dhcp_dns ${NW1_NAME} servers=${AUTH_HOST},${DNS_SERVERS} domains=${AUTH_DOMAIN}"
    acli "  net.add_dhcp_pool ${NW1_NAME} start=${NW1_DHCP_START} end=${NW1_DHCP_END}"

    if [[ ! -z "${NW2_NAME}" ]]; then
      log "Create secondary network: Name: ${NW2_NAME}, VLAN: ${NW2_VLAN}, Subnet: ${NW2_SUBNET}, Pool: ${NW2_DHCP_START} to ${NW2_DHCP_END}"
      acli "net.create ${NW2_NAME} vlan=${NW2_VLAN} ip_config=${NW2_SUBNET}"
      acli "net.update_dhcp_dns ${NW2_NAME} servers=${AUTH_HOST},${DNS_SERVERS} domains=${AUTH_DOMAIN}"
      acli "  net.add_dhcp_pool ${NW2_NAME} start=${NW2_DHCP_START} end=${NW2_DHCP_END}"
    fi
  fi
}

function pc_configure() {
  args_required 'PC_LAUNCH RELEASE'
  local      _command
  local    _container
  local _dependencies="global.vars.sh lib.common.sh lib.pc.sh ${PC_LAUNCH}"
  local   _pc_version
  local         _test

  # shellcheck disable=2206
  _pc_version=(${PC_VERSION//./ })
  if (( ${_pc_version[0]} >= 5 && ${_pc_version[1]} >= 10 )); then
     _test=$(ncli multicluster add-to-multicluster \
       external-ip-address-or-svm-ips=${PC_HOST} \
       username=${PRISM_ADMIN} password=${PE_PASSWORD})
     log "PC>=5.10, manual join PE to PC = |${_test}|"
  fi

  if [[ -e ${RELEASE} ]]; then
    _dependencies+=" ${RELEASE}"
  else
    log 'Warning: did NOT find '${RELEASE}
  fi
  log "Send configuration scripts to PC and remove: ${_dependencies}"
  remote_exec 'scp' 'PC' "${_dependencies}" && rm -f ${_dependencies} lib.pe.sh

  _dependencies="bin/${JQ_REPOS[0]##*/} ${SSHPASS_REPOS[0]##*/} id_rsa.pub"

  log "OPTIONAL: Send binary dependencies to PC: ${_dependencies}"
  remote_exec 'scp' 'PC' "${_dependencies}" 'OPTIONAL'

  for _container in epsilon nucalm ; do
    if [[ -e ${_container}.tar ]]; then
      log "Uploading Calm container updates in background..."
      remote_exec 'SCP' 'PC' ${_container}.tar 'OPTIONAL' &
    fi
  done

  _command="EMAIL=${EMAIL} \
    PC_HOST=${PC_HOST} PE_HOST=${PE_HOST} PE_PASSWORD=${PE_PASSWORD} \
    PC_VERSION=${PC_VERSION} nohup bash ${HOME}/${PC_LAUNCH} PC"
  log "Remote asynchroneous launch PC configuration script... ${_command}"
  remote_exec 'ssh' 'PC' "${_command} >> ${HOME}/${PC_LAUNCH%%.sh}.log 2>&1 &"
  log "PC Configuration complete: try Validate Staged Clusters now."
}

function pc_install() {
  local    _ncli_softwaretype='PRISM_CENTRAL_DEPLOY'
  local              _nw_name="${1}"
  local              _nw_uuid
  local           _pc_version
  local _should_auto_register
  local _storage_default_uuid
  local                 _test

  log "IDEMPOTENCY: Checking PC API responds, curl failures are acceptable..."
  prism_check 'PC' 2 0

  if (( $? == 0 )) ; then
    log "IDEMPOTENCY: PC API responds, skip."
  else
    log "Get cluster network and storage container UUIDs..."
    _nw_uuid=$(acli "net.get ${_nw_name}" \
      | grep "uuid" | cut -f 2 -d ':' | xargs)
    _storage_default_uuid=$(ncli container ls name=${STORAGE_DEFAULT} \
      | grep Uuid | grep -v Pool | cut -f 2 -d ':' | xargs)
    log "${_nw_name} network UUID: ${_nw_uuid}"
    log "${STORAGE_DEFAULT} storage container UUID: ${_storage_default_uuid}"

    _test=$(source /etc/profile.d/nutanix_env.sh \
      && ncli --json=true software list \
      | jq -r \
        '.data[] | select(.softwareType == "'${_ncli_softwaretype}'") | select(.status == "COMPLETED") | .version')

    if [[ ${_test} != "${PC_VERSION}" ]]; then
      log "PC-${PC_VERSION} not completed. ${_test}"
      ntnx_download "${_ncli_softwaretype}"
    else
      log "IDEMPOTENCY: PC-${PC_VERSION} upload already completed."
    fi

    # shellcheck disable=2206
    _pc_version=(${PC_VERSION//./ })
    if (( ${_pc_version[0]} = 5 && ${_pc_version[1]} <= 6 )); then
      _should_auto_register='"should_auto_register":true,'
    fi

    log "Deploy Prism Central (typically takes 17+ minutes)..."
    # TODO:160 make scale-out & dynamic, was: 4vCPU/16GB = 17179869184, 8vCPU/40GB = 42949672960
    # Sizing suggestions, certified configurations:
    # https://portal.nutanix.com/#/page/docs/details?targetId=Release-Notes-Prism-Central-v591:sha-pc-scalability-r.html

    # TODO:10 network_configuration.{subnet_mask|default_gateway}
    HTTP_BODY=$(cat <<EOF
{
  "resources": {
    ${_should_auto_register}
    "version":"${PC_VERSION}",
    "pc_vm_list":[{
      "data_disk_size_bytes":536870912000,
      "nic_list":[{
        "network_configuration":{
          "subnet_mask":"255.255.255.128",
          "network_uuid":"${_nw_uuid}",
          "default_gateway":"${IPV4_PREFIX}.1"
        },
        "ip_list":["${PC_HOST}"]
      }],
      "dns_server_ip_list":["${AUTH_HOST}"],
      "container_uuid":"${_storage_default_uuid}",
      "num_sockets":8,
      "memory_size_bytes":42949672960,
      "vm_name":"Prism Central ${PC_VERSION}"
    }]
  }
}
EOF
    )
    local _test
    _test=$(curl ${CURL_POST_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} \
      -X POST --data "${HTTP_BODY}" \
      https://localhost:9440/api/nutanix/v3/prism_central)
    #log "_test=|${_test}|"
  fi
}

function pe_auth() {
  local           _aos
  local   _aos_version
  local _directory_url="ldaps://${AUTH_HOST}/"
  local         _error=45

  args_required 'AUTH_DOMAIN AUTH_FQDN AUTH_HOST AUTH_ADMIN_USER AUTH_ADMIN_PASS AUTH_ADMIN_GROUP'

  if [[ -z $(ncli authconfig list-directory name=${AUTH_DOMAIN} | grep Error) ]]; then
    log "IDEMPOTENCY: ${AUTH_DOMAIN} directory set, skip."
  else
    # https://portal.nutanix.com/kb/1005
    _aos=$(ncli --json=true cluster info | jq -r .data.version)

    if [[ ! -z ${_aos} ]]; then
      # shellcheck disable=2206
      _aos_version=(${_aos//./ })
      if (( ${_aos_version[0]} >= 5 && ${_aos_version[1]} >= 9 )); then
        _directory_url="ldap://${AUTH_HOST}:${LDAP_PORT}"
        log "Adjusted directory-url=${_directory_url} because AOS-${_aos} >= 5.9"
      fi
    else
      log "Error ${_error}: couldn't determine AOS version=${_aos}"
      exit ${_error}
    fi

    log "Configure PE external authentication"
    ncli authconfig add-directory \
      directory-type=ACTIVE_DIRECTORY \
      connection-type=LDAP directory-url="${_directory_url}" \
      domain="${AUTH_FQDN}" \
      name="${AUTH_DOMAIN}" \
      service-account-username="${AUTH_ADMIN_USER}" \
      service-account-password="${AUTH_ADMIN_PASS}"

    log "Configure PE role map"
    ncli authconfig add-role-mapping \
      role=ROLE_CLUSTER_ADMIN \
      entity-type=group name="${AUTH_DOMAIN}" \
      entity-values="${AUTH_ADMIN_GROUP}"
  fi
}

function pe_init() {
  args_required 'DATA_SERVICE_IP EMAIL \
    SMTP_SERVER_ADDRESS SMTP_SERVER_FROM SMTP_SERVER_PORT \
    STORAGE_DEFAULT STORAGE_POOL STORAGE_IMAGES \
    SLEEP ATTEMPTS'

  if [[ `ncli cluster get-params | grep 'External Data' | \
         awk -F: '{print $2}' | tr -d '[:space:]'` == "${DATA_SERVICE_IP}" ]]; then
    log "IDEMPOTENCY: Data Services IP set, skip."
  else
    log "Configure SMTP"
    ncli cluster set-smtp-server port=${SMTP_SERVER_PORT} \
      from-email-address=${SMTP_SERVER_FROM} address=${SMTP_SERVER_ADDRESS}
    ${HOME}/serviceability/bin/email-alerts --to_addresses="${EMAIL}" \
      --subject="[pe_init:Config SMTP:alert test] $(ncli cluster get-params)" \
      && ${HOME}/serviceability/bin/send-email

    log "Configure NTP"
    ncli cluster add-to-ntp-servers servers=${NTP_SERVERS}

    log "Rename default container to ${STORAGE_DEFAULT}"
    default_container=$(ncli container ls | grep -P '^(?!.*VStore Name).*Name' \
      | cut -d ':' -f 2 | sed s/' '//g | grep '^default-container-')
    ncli container edit name="${default_container}" new-name="${STORAGE_DEFAULT}"

    log "Rename default storage pool to ${STORAGE_POOL}"
    default_sp=$(ncli storagepool ls | grep 'Name' | cut -d ':' -f 2 | sed s/' '//g)
    ncli sp edit name="${default_sp}" new-name="${STORAGE_POOL}"

    log "Check if there is a container named ${STORAGE_IMAGES}, if not create one"
    (ncli container ls | grep -P '^(?!.*VStore Name).*Name' \
      | cut -d ':' -f 2 | sed s/' '//g | grep "^${STORAGE_IMAGES}" > /dev/null 2>&1) \
      && log "Container ${STORAGE_IMAGES} exists" \
      || ncli container create name="${STORAGE_IMAGES}" sp-name="${STORAGE_POOL}"

    # Set external IP address:
    #ncli cluster edit-params external-ip-address=${PE_HOST}

    log "Set Data Services IP address to ${DATA_SERVICE_IP}"
    ncli cluster edit-params external-data-services-ip-address=${DATA_SERVICE_IP}
  fi
}

function pe_license() {
  local _test
  args_required 'CURL_POST_OPTS PE_PASSWORD'

  log "IDEMPOTENCY: Checking PC API responds, curl failures are acceptable..."
  prism_check 'PC' 2 0

  if (( $? == 0 )) ; then
    log "IDEMPOTENCY: PC API responds, skip"
  else
    _test=$(curl ${CURL_POST_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data '{
      "username": "SE with $(basename ${0})",
      "companyName": "Nutanix",
      "jobTitle": "SE"
    }' https://localhost:9440/PrismGateway/services/rest/v1/eulas/accept)
    log "Validate EULA on PE: _test=|${_test}|"

    _test=$(curl ${CURL_POST_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X PUT --data '{
      "defaultNutanixEmail": null,
      "emailContactList": null,
      "enable": false,
      "enableDefaultNutanixEmail": false,
      "isPulsePromptNeeded": false,
      "nosVersion": null,
      "remindLater": null,
      "verbosityType": null
    }' https://localhost:9440/PrismGateway/services/rest/v1/pulse)
    log "Disable Pulse in PE: _test=|${_test}|"

    #echo; log "Create PE Banner Login" # TODO: for PC, login banner
    # https://portal.nutanix.com/#/page/docs/details?targetId=Prism-Central-Guide-Prism-v56:mul-welcome-banner-configure-pc-t.html
    # curl ${CURL_POST_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data \
    #  '{type: "welcome_banner", key: "welcome_banner_status", value: true}' \
    #  https://localhost:9440/PrismGateway/services/rest/v1/application/system_data
    #curl ${CURL_POST_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data
    #  '{type: "welcome_banner", key: "welcome_banner_content", value: "HPoC '${OCTET[2]}' password = '${PE_PASSWORD}'"}' \
    #  https://localhost:9440/PrismGateway/services/rest/v1/application/system_data
  fi
}

function pc_unregister {
  local _cluster_uuid
  local      _pc_uuid
  # https://portal.nutanix.com/kb/4944

  # PE:
  cluster status # check
  ncli -h true multicluster remove-from-multicluster \
    external-ip-address-or-svm-ips=${PC_HOST} \
    username=${PRISM_ADMIN} password=${PE_PASSWORD} force=true
    # Error: This cluster was never added to Prism Central
  ncli multicluster get-cluster-state # check for none
  _cluster_uuid=$(ncli cluster info | grep -i uuid | awk -F: '{print $2}' | tr -d '[:space:]')

  exit 0
  # PC: remote_exec 'PC'
  chmod u+x /home/nutanix/bin/unregistration_cleanup.py \
  && python /home/nutanix/bin/unregistration_cleanup.py ${_cluster_uuid}
  # Uuid of current cluster cannot be passed to cleanup
  _pc_uuid=$(cluster info) # no such command!
  # PE:
  chmod u+x /home/nutanix/bin/unregistration_cleanup.py \
  && python /home/nutanix/bin/unregistration_cleanup.py ${_pc_uuid}

  # Troubleshooting
  cat ~/data/logs/unregistration_cleanup.log

  pc_destroy
}

function pc_destroy() {
  local _vm

  dependencies 'install' 'jq' || exit 13

  for _vm in $(acli -o json vm.list | jq -r '.data[] | select(.name | contains("Prism Central")) | .uuid'); do
    log "PC vm.uuid=${_vm}"
    acli vm.off ${_vm} && acli -y vm.delete ${_vm}
  done
}
