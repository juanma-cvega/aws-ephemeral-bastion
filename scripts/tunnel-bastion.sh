#!/bin/bash

unset ENVIRONMENT
AWS_REGION=eu-west-1
INSTANCE_PORT="9999"
LOCAL_PORT="8888"

usage() {
  echo ""
  echo "Usage: $0 -p targetPort -l localPort -r region -h help"
  echo -e "\t-p Port the instance is listening on. Defaults to 9999."
  echo -e "\t-l Local port the tunnel is started on. Defaults to 8888."
  echo -e "\t-r AWS region the instance is deployed on. Defaults to eu-west-1"
  echo -e "\t-h Shows this help."
  exit 1 # Exit script after printing help
}

get_database_url() {
  echo "rds.$1.dreev.net:5432"
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
  database_url=$(get_database_url "$ENVIRONMENT")

  payload=$(jq -n \
    --arg forward_port "$INSTANCE_PORT" \
    --arg database_url "$database_url" \
    '{
      template_name: "database_tunnel",
      template_vars: {
        FORWARD_PORT: $forward_port,
        DATABASE_URL: $database_url
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


while getopts ":e:l:p:r:h" opt; do
  case "${opt}" in
  e) ENVIRONMENT="$OPTARG" ;;
  l) LOCAL_PORT="$OPTARG" ;;
  p) INSTANCE_PORT="$OPTARG" ;;
  r) AWS_REGION="$OPTARG" ;;
  h) usage ;;
  ?) usage ;;
  esac
done

if [ -z "${ENVIRONMENT}" ]; then echo "Environment not set. Please, add -e variable when invoking the script"; exit 1; fi

echo "Environment selected: $ENVIRONMENT"
echo "AWS region selected: $AWS_REGION"
echo "Instance port selected: $INSTANCE_PORT"
echo "Local port selected: $LOCAL_PORT"

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

    n=30
    sleep $n
    echo "Still waiting... 30 seconds"
    until [ "$n" -ge 120 ]
    do
       aws ssm start-session --region "$AWS_REGION" --target "$INSTANCE_ID" \
          --document-name AWS-StartPortForwardingSession \
          --parameters "{\"portNumber\":[\"$INSTANCE_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}" 2> /dev/null && break
       n=$((n+5))
       if ! ((n % 10)); then echo "Still waiting... $n seconds";fi
       sleep 5
    done
    echo "You can reconnect by using the following command"
    echo "aws ssm start-session --region $AWS_REGION --target $INSTANCE_ID \\"
    echo "--document-name AWS-StartPortForwardingSession \\"
    echo "--parameters \"{\\\"portNumber\\\":[\\\"$INSTANCE_PORT\\\"],\\\"localPortNumber\\\":[\\\"$LOCAL_PORT\\\"]}\""
  else
    echo "Unable to get an instance ID. The creation stack failed."
  fi
else
  echo "Unable to get a stack ID. The lambda invocation failed."
fi