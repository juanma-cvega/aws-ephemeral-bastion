# AWS Ephemeral bastions

## Description
The following module creates the required infrastructure to provision 
EC2 instances that self-terminate after a Systems Manager Session Manager
session is terminated/expires. 

## Features

-  Reduces the cost of maintaining EC2 instances running 24x7.
-  Removes the need to apply patches to the hosts or to replace them 
with more up to date images. New hosts are created from the latest version of an AMI.
-  Removes the need to keep individual users inside the host or share the 
same one for every connected user. 
-  Every session starts clean. Files or applications installed by users 
during a session are removed at the end. 
-  Possibility to create bootstrap actions. These would automatically 
install the required software for a session. Another option would be to create different AMIs for each use case but it is more difficult to maintain.

## Requirements

- Terraform >= 0.13
- Centralised account were the infrastructure is deployed.
- S3 bucket with the name 'terraform-bastion-backend'. This value is 
hardcoded in the deployment/backend.tf file as Terraform doesn't allow 
backend configuration to be parameterised. 
- Network infrastructure inside the centralised account:
    - VPC.
    - VPC peering to environment/s the bastion host/s require/s connection to.
    - Subnet per environment to connect to. Its name needs to be prefixed
     with "Access" (i.e. "AccessTest"). Having multiple subnets is optional as 
     it's meant to further increase security, a single subnet as a central 
     hub to access all peered environments would work as well.
    - Route table per subnet with a route to the peered environment CIDR 
    block. This is optional as it's meant to further increase security, 
    a single route table with routes to every peered environment would
     also work.

## Usage

To simplify usage of this infrastructure, 3 scripts are provided under the 
'scripts' folder. 
- create-bastion.sh. It creates a bastion host and connects to it. 
- git-terraform-bastion.sh. It creates a bastion host with Git and Terraform 
already installed.
- tunnel-bastion.sh. It creates a bastion host with the socat service installed.
It then creates a tunnel from the host to the database URL provided in the 
script. Once created, it connects to the host with a port forwarding document
to redirect calls to the specified port to the database. 
