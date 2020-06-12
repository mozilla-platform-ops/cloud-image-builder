#!/bin/bash


resource_groups=$(az group list --query [].name --output tsv)
for resource_group in ${resource_groups}; do
  #image_names=$(az image list -g ${resource_group} --query "[?contains(tags.diskImageTask].name" --output tsv)
  image_names=$(az image list -g ${resource_group} --query [].name --output tsv)
  for image_name in ${image_names}; do
    image_tags_should_be_updated=false
    echo "- image: ${image_name}"
    if [[ ${image_name} =~ ^([a-z0-9-]*-us)-(gecko-.|relops)-(win[a-z0-9-]*)-([a-f0-9]{7})-([a-f0-9]{7})$ ]]; then
      #echo "  - disk sha: '${BASH_REMATCH[4]}'"
      #echo "  - machine sha: '${BASH_REMATCH[5]}'"
      image_region=${BASH_REMATCH[1]}
      image_domain=${BASH_REMATCH[2]}
      image_key=${BASH_REMATCH[3]}
    fi
    existing_image_tags_as_json=$(az image show -n ${image_name} -g ${resource_group} --query tags) || true
    modified_image_tags_as_json=${existing_image_tags_as_json}

    # disk image
    disk_image_commit_sha=$(echo ${existing_image_tags_as_json} | jq -r '.diskImageCommitSha')
    echo "  - disk image commit: ${disk_image_commit_sha}"
    disk_image_task=$(echo ${existing_image_tags_as_json} | jq -r '.diskImageTask //empty')
    if [ -z "${disk_image_task}" ]; then
      disk_image_task_group_url=$(curl -s http://localhost:8010/proxy/repos/mozilla-platform-ops/cloud-image-builder/commits/${disk_image_commit_sha}/statuses | jq -r '[.[] | select(.context == "Stage-TC (push)" and .state != "pending")][0].target_url')
      disk_image_task_group_id=${disk_image_task_group_url##*/}
      echo "  - disk task group: ${disk_image_task_group_id}"
      disk_image_task_root_url=https://$(echo ${disk_image_task_group_url} | cut -d'/' -f3)
      disk_image_task=$(curl -s ${disk_image_task_root_url}/api/queue/v1/task-group/${disk_image_task_group_id}/list | jq -r --arg image_key ${image_key} '[.tasks[] | select(.task.metadata.name | startswith("01 :: build azure \($image_key) disk image"))][0] | "\(.status.taskId)/\(.status.runs[-1].runId)"')
      if [[ ${disk_image_task} != *"null"* ]]; then
        image_tags_should_be_updated=true
        modified_image_tags_as_json=$(echo ${modified_image_tags_as_json} | jq --arg disk_image_task ${disk_image_task} '. + {diskImageTask: $disk_image_task}')
      fi
      
    fi
    echo "  - disk task: ${disk_image_task}"

    # machine image
    machine_image_commit_sha=$(echo ${existing_image_tags_as_json} | jq -r '.machineImageCommitSha')
    echo "  - machine image commit: ${machine_image_commit_sha}"
    machine_image_task=$(echo ${existing_image_tags_as_json} | jq -r '.machineImageTask //empty')
    if [ -z "${machine_image_task}" ]; then
      machine_image_task_group_url=$(curl -s http://localhost:8010/proxy/repos/mozilla-platform-ops/cloud-image-builder/commits/${machine_image_commit_sha}/statuses | jq -r '[.[] | select(.context == "Stage-TC (push)" and .state != "pending")][0].target_url')
      machine_image_task_group_id=${machine_image_task_group_url##*/}
      echo "  - machine task group: ${machine_image_task_group_id}"
      machine_image_task_root_url=https://$(echo ${machine_image_task_group_url} | cut -d'/' -f3)
      machine_image_task=$(curl -s ${machine_image_task_root_url}/api/queue/v1/task-group/${machine_image_task_group_id}/list | jq -r --arg image_domain ${image_domain} --arg image_key ${image_key} --arg image_region ${image_region} '[.tasks[] | select((.task.metadata.name | startswith("02 :: build azure \($image_domain)/\($image_key)-azure machine image")) and (.task.metadata.name | endswith("azure rg-\($image_region)-\($image_domain)")))][0] | "\(.status.taskId)/\(.status.runs[-1].runId)"')
      if [[ ${machine_image_task} != *"null"* ]]; then
        image_tags_should_be_updated=true
        modified_image_tags_as_json=$(echo ${modified_image_tags_as_json} | jq --arg machine_image_task ${machine_image_task} '. + {machineImageTask: $machine_image_task}')
      fi
    fi
    echo "  - machine task: ${machine_image_task}"

    if [[ ${image_tags_should_be_updated} == "true" ]]; then
      echo "  $(tput setaf 3)tags require update$(tput sgr0)"
      # todo: find a way to handle spaces (in the os tag values) that doesn't involve underscores
      modified_image_tags_as_args=$(echo ${modified_image_tags_as_json} | tr -d '"{},' | sed 's/: /=/g' | sed 's/Windows Server 2012 R2/Windows_Server_2012_R2/g' | sed 's/Windows Server 2019/Windows_Server_2019/g' | sed 's/Windows 10/Windows_10/g' | sed 's/Windows 7/Windows_7/g')
      #echo ${modified_image_tags_as_args[@]}
      az image update -n ${image_name} -g ${resource_group} --tags ${modified_image_tags_as_args[@]}
      echo "  $(tput setaf 2)tags updated$(tput sgr0)"
    elif [[ ${machine_image_task} == *"null"* ]] || [[ ${machine_image_task} == *"null"* ]]; then
      echo "  $(tput setaf 1)tags update impossible$(tput sgr0)"
    else
      echo "  $(tput setaf 6)tags are up to date$(tput sgr0)"
    fi
  done
done