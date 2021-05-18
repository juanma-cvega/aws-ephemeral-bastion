import os
import boto3

TABLE_NAME = os.environ['TABLE_NAME']
CODEBUILD_JOB = os.environ['CODEBUILD_JOB']

DYNAMODB = boto3.resource('dynamodb')
TABLE = DYNAMODB.Table(TABLE_NAME)
EC2 = boto3.client('ec2')
SSM = boto3.client('ssm')
CODEBUILD = boto3.client('codebuild')


def is_instance_up(instance):
    running = len(EC2.describe_instance_status(
        Filters=[
            {
                'Name': 'system-status.status',
                'Values': ['ok']
            }
        ],
        InstanceIds=[instance['InstanceId']]
    )['InstanceStatuses']) > 0
    print(f"Instance is running: instance={instance['InstanceId']}, running={running}")
    return running


def has_no_sessions(instance):
    sessions = len(SSM.describe_sessions(
        State='Active',
        MaxResults=100,
        Filters=[
            {
                'key': 'Target',
                'value': instance["InstanceId"]
            },
            {
                'key': 'Status',
                'value': 'Connected'
            }
        ]
    )["Sessions"])
    print(f"Instance connected sessions: instance={instance['InstanceId']}, sessions={sessions}")
    return sessions == 0


def is_instance_idle():
    return lambda instance: is_instance_up(instance) and has_no_sessions(instance)


def get_registered_instances():
    return TABLE.scan()["Items"]


def find_idle_instances(created_instances):
    return list(filter(is_instance_idle(), created_instances))


def delete_idle_instance(instance):
    CODEBUILD.start_build(
        environmentVariablesOverride=[
            {
                'name': 'STACK_ID',
                'value': instance["StackId"],
                'type': 'PLAINTEXT'
            },
            {
                'name': 'ENVIRONMENT',
                'value': instance["Environment"],
                'type': 'PLAINTEXT'
            }
        ],
        projectName=CODEBUILD_JOB,
        sourceVersion=instance["SourceVersion"]
    )


def delete_idle_instances():
    instances = get_registered_instances()
    idle_instances = find_idle_instances(instances)
    instance_names = [instance["InstanceId"] for instance in idle_instances]
    print(f"Found idle instances: count={len(idle_instances)}, instances={instance_names}")
    for instance in idle_instances:
        delete_idle_instance(instance)


def lambda_handler(event, context):
    delete_idle_instances()
