#!/bin/bash

for region in eu-central-1 us-east-1 us-east-2 us-west-1 us-west-2; do
  for instance_id in $(aws ec2 --region ${region} describe-instances --filter Name=tag:Name,Values=relops/win2019 Name=instance-state-name,Values=running --query Reservations[*].Instances[*].InstanceId --output text); do
    aws ec2 associate-iam-instance-profile --instance-id ${instance_id} --iam-instance-profile Name=windows-ami-builder
  done
done
