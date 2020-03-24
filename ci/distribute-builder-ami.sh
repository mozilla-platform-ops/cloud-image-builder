#!/bin/bash

worker_type=relops-image-builder
source_region=us-west-2
local_repo_path=${HOME}/git/mozilla-platform-ops/cloud-image-builder

# latest ami
source_ami_id=$(aws ec2 describe-images --region ${source_region} --owners self --filters "Name=name,Values=${worker_type} *" --query 'Images[*].{A:CreationDate,B:ImageId}' --output text | sort -u | tail -1 | cut -f2)
source_ami_name=$(aws ec2 describe-images --region ${source_region} --image-ids ${source_ami_id} --query 'Images[*].{A:Name}' --output text)
source_ami_description=$(aws ec2 describe-images --region ${source_region} --image-ids ${source_ami_id} --query 'Images[*].{A:Description}' --output text)

for target_region in us-east-1 us-east-2 us-west-1 eu-central-1; do
  target_ami_id=`aws ec2 copy-image --region ${target_region} --source-region ${source_region} --source-image-id ${source_ami_id} --name "${source_ami_name}" --description "${source_ami_description}" | sed -n 's/^ *"ImageId": *"\(.*\)" *$/\1/p'`
  echo copied ${source_ami_id} from ${source_region} to ${target_ami_id} in ${target_region}
  old_target_ami_id=$(yq -r --arg target_region ${target_region} '[.config.launchConfigs[] | select(.region == $target_region) | .launchConfig.ImageId][0]' ${local_repo_path}/ci/config/worker-pool/relops/win2019.yaml)
  sed -i -e "s/${old_target_ami_id}/${target_ami_id}/g" ${local_repo_path}/ci/config/worker-pool/relops/win2019.yaml
done
git --git-dir=${local_repo_path}/.git --work-tree=${local_repo_path} diff -w
