import json
import os
import boto3
import urllib.parse

sfn_client = boto3.client('stepfunctions')
state_machine_arn = '<STEPFUNCTION_ARN>'


def lambda_handler(event, context):
    try:
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        print(f"Detected new file upload - Bucket: {bucket}, Key: {key}")
        
        state_machine_input = {
            "key": key
        }
        
        response = sfn_client.start_execution(
            stateMachineArn=state_machine_arn,
            input=json.dumps(state_machine_input)
        )
        
        print(f"Successfully started Step Functions execution. Execution ARN: {response['executionArn']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Step Functions triggered successfully!')
        }
        
    except Exception as e:
        print(f"Error triggering Step Functions: {str(e)}")
        raise e