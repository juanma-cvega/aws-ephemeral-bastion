#!/bin/bash

unset ENVIRONMENT
AWS_REGION=eu-west-1
TERRAFORM_VERSION=0.13.4

usage() {
  echo ""
  echo "Usage: $0 -u Git username -p Git password -v Terraform version -r region -h help"
  echo -e "\t-u Git username."
  echo -e "\t-p Git password"
  echo -e "\t-v Terraform version"
  echo -e "\t-r AWS region the instance is deployed on. Defaults to eu-west-1"
  echo -e "\t-h Shows this help."
  exit 1 # Exit script after printing help
}

get_instance_id() {
 aws ec2 describe-instances \
    --region "$1" \
    --filters "Name=tag:StackId,Values=$2" \
    --query "Reservations[].Instances[?State.Name == 'running'].InstanceId[]" \
    --output text | tr -d '[:space:]'
}

get_lambda_name() {
  echo "CreateInstanceStack$1"
}

invoke_lambda() {
  payload=$(jq -n \
    --arg username "$USERNAME" \
    --arg password "$PASSWORD" \
    --arg terraform_version "$TERRAFORM_VERSION" \
    '{
      template_name: "install_git_terraform",
      template_vars: {
        USERNAME: $username,
        PASSWORD: $password,
        TERRAFORM_VERSION: $terraform_version
      }
    }')

  aws lambda invoke \
  --function-name "$(get_lambda_name "$1")" \
  --payload "$payload" \
  --region "$AWS_REGION" \
  --cli-binary-format raw-in-base64-out \
  response.json &>/dev/null

  echo "$(cat response.json | jq '.body.stack_id' | tr -d \")"

  rm -rf response.json
}


while getopts ":e:u:p:r:v:h" opt; do
  case "${opt}" in
  e) ENVIRONMENT="$OPTARG" ;;
  u) USERNAME="$OPTARG" ;;
  p) PASSWORD="$OPTARG" ;;
  r) AWS_REGION="$OPTARG" ;;
  v) TERRAFORM_VERSION="$OPTARG" ;;
  h) usage ;;
  ?) usage ;;
  esac
done

if [ -z "${ENVIRONMENT}" ]; then echo "Environment not set. Please, add -e variable when invoking the script"; exit 1; fi
if [ -z "${USERNAME}" ]; then echo "Username not set. Please, add -u variable when invoking the script"; exit 1; fi
if [ -z "${PASSWORD}" ]; then echo "Password not set. Please, add -p variable when invoking the script"; exit 1; fi

echo "Environment selected: $ENVIRONMENT"
echo "AWS region selected: $AWS_REGION"
echo "Username selected: $USERNAME"
echo "Terraform version selected: $TERRAFORM_VERSION"

capitalized_environment="$(tr '[:lower:]' '[:upper:]' <<< ${ENVIRONMENT:0:1})${ENVIRONMENT:1}"
STACK_ID=$(invoke_lambda "$capitalized_environment")

if [ -n "${STACK_ID}" ]; then

  echo "StackId: $STACK_ID"
  echo "Waiting for instance stack to be created..."

  n=20
  sleep $n
  echo "Still waiting... 20 seconds"
  until [ "$n" -ge 120 ]
  do
     INSTANCE_ID=$(get_instance_id "$AWS_REGION" "$STACK_ID")
     if [ -n "${INSTANCE_ID}" ]; then break; fi
     n=$((n+5))
     if ! ((n % 10)); then echo "Still waiting... $n seconds";fi
     sleep 5
  done

  echo "InstanceId: $INSTANCE_ID"

  if [ -n "${INSTANCE_ID}" ]; then
    echo "Waiting for instance to connect to Session Manager..."

    n=10
    sleep $n
    echo "Still waiting... 10 seconds"
    until [ "$n" -ge 120 ]
    do
       aws ssm start-session --region "$AWS_REGION" --target "$INSTANCE_ID" 2> /dev/null && break
       n=$((n+1))
       if ! ((n % 10)); then echo "Still waiting... $n seconds";fi
       sleep 5
    done
    echo "You can reconnect by using the following command"
    echo "aws ssm start-session --region $AWS_REGION --target $INSTANCE_ID"
  else
    echo "Unable to get an instance ID. The creation stack failed."
  fi
else
  echo "Unable to get a stack ID. The lambda invocation failed."
fi
