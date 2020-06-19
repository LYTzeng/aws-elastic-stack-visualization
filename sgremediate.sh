#!/bin/bash
#
#
# sgremediate.sh

# Copyright 2015-2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Written By: Eric Pullen, AWS Professional Services
#
# Will scan the given vpcID for SG's and detect if they have any associated services
# Services scaned: EC2, ELB, RDS, RedShift, ElastiCache
# If EC2 is detected, it will build a ElasticSearch URL that has the VPC FlowLogs ingested
#

# usage: ./sgremediate.sh KIBANA_URL PROFILE VPC_ID

if [ -z "$1" ]; then
  echo "No KIBANA_URL specified."
  exit 0
else
  KibanaURL=$1
  DashboardID=($(curl -s -k -X GET "${KibanaURL}/api/saved_objects/_find?fields=id&fields=title&type=dashboard&per_page=1000" | jq -r '.saved_objects[] | select(.attributes.title | contains("Accepted VPC Flow")) | .id'))
fi

if [ -z "$2" ]; then
  profile="default"
else
  profile=$2
fi

if [ -z "$3" ]; then
  echo "No VPC_ID specified."
  exit 0
else
  vpcID=$3
fi

# ElasticSearch URL
# KibanaURL="ec2-54-201-255-186.us-west-2.compute.amazonaws.com:5601"

# ---------------------------------------------------
# Start of check, no other variables below this line
# ---------------------------------------------------

# Start the process by getting a list of all the SG's in the defined VPC

sgList=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$vpcID --profile "$profile" | jq -r '.SecurityGroups[].GroupId')
if [ -z "$sgList" ]; then
  echo "VPC-ID $vpcID is invalid or returning no security groups"
  exit 0
fi

echo "<!DOCTYPE html>"
echo "<html>"
echo "<body>"

for securityGroup in $sgList; do

  #We need to get a list of ENI’s based on the security group in this loop
  eniList=($(aws ec2 describe-instances --filters "Name=instance.group-id,Values=$securityGroup" --profile "$profile" | jq -r '.Reservations[].Instances[].NetworkInterfaces[].NetworkInterfaceId'))

  if [ -z "$eniList" ]; then
    echo -n "$securityGroup - "

    # Check to see if they are associated with any RDS instances
    rdsVpcList=$(aws rds describe-db-instances --profile "$profile" | grep $securityGroup)
    if [ -z "$rdsVpcList" ]; then
      echo -n ""
    else
      echo -n "RDS instance is associated "
      other="yes"
    fi

    # Check to see if they are associated with any ELB instances
    elbList=($(aws elb describe-load-balancers --profile "$profile" | grep $securityGroup))
    if [ -z "$elbList" ]; then
      echo -n ""
    else
      echo -n "ELB instance is associated "
      other="yes"
    fi

    # Check to see if they are associated with any Redshift instances
    rsList=($(aws redshift describe-clusters --profile "$profile" | grep $securityGroup))
    if [ -z "$rsList" ]; then
      echo -n ""
    else
      echo -n "Redshift cluster is associated "
      other="yes"
    fi

    # Check to see if they are associated with any ElastiCache instances
    ecList=($(aws elasticache describe-cache-clusters --profile "$profile" | grep $securityGroup))
    if [ -z "$ecList" ]; then
      echo -n ""
    else
      echo -n "ElastiCache cluster is associated "
      other="yes"
    fi

    if [ -z "$other" ]; then
      echo "No services related to this SG <BR>"
    else
      echo "<BR>"
    fi

  else

    # Start the URL string to present back to the user
    echo -n "<a href=\"http://$KibanaURL/app/kibana#/dashboard/$DashboardID?_a=(\
query:(language:kuery,query:'(aws.vpcflow.action:%20%22ACCEPT%22)%20AND%20("

    # Interate over all of the ENI's to generate the URL properly
    count=0
    for eniName in "${eniList[@]}"; do
      count=$((count + 1))

      # For each ENI, let's get its private IP address
      privateIPList=($(aws ec2 describe-network-interfaces --network-interface-ids $eniName --profile "$profile" | jq -r '.NetworkInterfaces[].PrivateIpAddress'))
      sizeOfPrivateIPList=${#privateIPList[@]}
      # This is the string we need to add to the search URL
      if [ "$count" -eq "${#eniList[@]}" ]; then
        # If we are on the last array item, don't add the OR at the end
        buildString="(aws.vpcflow.interface_id: %22$eniName%22 and NOT source.address: ("
        if [ $(($sizeOfPrivateIPList - 1)) -ne 0 ]; then
          for i in $(#"${privateIPList[@]}"
            eval echo {0..$((${sizeOfPrivateIPList} - 1))}
          ); do
            privateIP=${privateIPList[i]}
            buildString="${buildString}${privateIP} OR "
          done
        fi
        lastPrivateIP=${privateIPList[$sizeOfPrivateIPList - 1]}
        buildString="${buildString}${lastPrivateIP}))"

      else
        # If we are still in the loop, then add the OR at the end
        buildString="(aws.vpcflow.interface_id: %22$eniName%22 and NOT source.address: ("
        if [ $(($sizeOfPrivateIPList - 1)) -ne 0 ]; then
          for i in $(#"${privateIPList[@]}"
            eval echo {0..$((${sizeOfPrivateIPList} - 1))}
          ); do
            privateIP=${privateIPList[i]}
            buildString="${buildString}${privateIP} OR "
          done
        fi
        buildString="${buildString}${privateIPList[$sizeOfPrivateIPList - 1]})) OR "
      fi

      # Finally we have to convert the spaces to %20
      buildString=${buildString// /%20}

      # echo out the string
      echo -n "$buildString"
    done

    # close out the string we built
    echo ")'),timeRestore:!t,title:'Accepted%20VPC%20Flow',viewMode:view)\">$securityGroup</a><br>"

  fi

done

echo "</body>"
echo "</html>"
