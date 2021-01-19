import os
import boto3
import json
import uuid

CODEBUILD_JOB = os.environ['CODEBUILD_JOB']
CODEBUILD = boto3.client('codebuild')
ENVIRONMENT = os.environ['ENVIRONMENT']


def parse_event(event):
    template_name = ""
    template_vars = "{}"
    if "template_name" in event:
        template_name = "{}.tpl".format(event["template_name"])
    if "template_vars" in event:
        template_vars = json.dumps(event["template_vars"])
    return {
        "environment": ENVIRONMENT,
        "template_name": template_name,
        "template_vars": template_vars
    }


def create_stack_id():
    return uuid.uuid4().hex


def start_build(stack_id, create_instance_info):
    build_id = None
    response = CODEBUILD.start_build(
        environmentVariablesOverride=[
            {
                'name': 'STACK_ID',
                'value': stack_id,
                'type': 'PLAINTEXT'
            },
            {
                'name': 'ENVIRONMENT',
                'value': create_instance_info["environment"],
                'type': 'PLAINTEXT'
            },
            {
                'name': 'TEMPLATE_NAME',
                'value': create_instance_info["template_name"],
                'type': 'PLAINTEXT'
            },
            {
                'name': 'TEMPLATE_VARS',
                'value': create_instance_info["template_vars"],
                'type': 'PLAINTEXT'
            }
        ],
        projectName=CODEBUILD_JOB
    )
    if "build" in response and "id" in response["build"]:
        build_id = response["build"]["id"]
    return build_id


def create_instance(create_instance_info):
    stack_id = create_stack_id()
    build_id = start_build(stack_id, create_instance_info)

    return {
        'stack_id': stack_id,
        'build_id': build_id,
        'environment': create_instance_info["environment"],
        'template_name': create_instance_info["template_name"],
        'template_vars': create_instance_info["template_vars"],
    }


def build_response_from(value):
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": value
    }


def lambda_handler(event, context):
    create_instance_info = parse_event(event)
    print(f"Parsed event: event={create_instance_info}")
    result = create_instance(create_instance_info)
    print(f"Stack and build id: stackId={result['stack_id']}, buildId={result['build_id']}")
    return build_response_from(result)
