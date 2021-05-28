#!/bin/bash

AWS_REGION=eu-west-1

usage() {
  echo ""
  echo "The script can read the variables AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_SESSION_TOKEN from the "
  echo "environment. If these are available their values are copied to the EC2 instance created."
  echo "Usage: $0 -e env -r region -h help"
  echo -e "\t-e Environment to connect to. Valid options are test, sandbox, staging or production."
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
  aws lambda invoke \
  --function-name "$(get_lambda_name "$1")" \
  --region "$AWS_REGION" \
  --cli-binary-format raw-in-base64-out \
  response.json &> result.txt

  if test -f "response.json"; then
    echo "$(cat response.json | jq '.body.stack_id' | tr -d \")"
    rm -rf response.json
  else
    echo  "ERROR: Unable to invoke lambda function. $(cat result.txt)"
  fi
  rm -rf result.txt
}

while getopts ":e:r:h" opt; do
  case "${opt}" in
  r) AWS_REGION="$OPTARG" ;;
  e) ENVIRONMENT="$OPTARG" ;;
  h) usage ;;
  ?) usage ;;
  esac
done

if [ -z "${ENVIRONMENT}" ]; then echo "Environment not set. Please, add -e variable when invoking the script"; exit 1; fi

echo "Environment selected: $ENVIRONMENT"
echo "AWS region selected: $AWS_REGION"

capitalized_environment="$(tr '[:lower:]' '[:upper:]' <<< ${ENVIRONMENT:0:1})${ENVIRONMENT:1}"
STACK_ID=$(invoke_lambda "$capitalized_environment")

if [[ "${STACK_ID}" == ERROR:* ]]; then
  echo "$STACK_ID"
else
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
fi