import json
import os
import re

import boto3

METRIC_NAMESPACE = "GJ2026/BookReservation"

dynamodb = boto3.resource("dynamodb")
cloudwatch = boto3.client("cloudwatch")
table = dynamodb.Table("books")

CLIENT_ID_PATTERN = re.compile(r"^[A-Za-z][0-9]+$")


def _project(item):
    return {
        "username": item.get("username"),
        "email": item.get("email"),
        "concert_name": item.get("concert_name"),
    }


def _put_query_count(client_id):
    cloudwatch.put_metric_data(
        Namespace=METRIC_NAMESPACE,
        MetricData=[
            {
                "MetricName": "QueryCount",
                "Dimensions": [{"Name": "client_id", "Value": "ALL"}],
                "Value": 1,
                "Unit": "Count",
            },
        ]
        + (
            [
                {
                    "MetricName": "QueryCount",
                    "Dimensions": [{"Name": "client_id", "Value": client_id}],
                    "Value": 1,
                    "Unit": "Count",
                }
            ]
            if client_id
            else []
        ),
    )


def handler(event, context):
    query = event.get("queryStringParameters") or {}
    client_id = query.get("client_id")

    if client_id:
        if not CLIENT_ID_PATTERN.match(client_id):
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"message": "invalid client_id"}),
            }

        resp = table.query(
            IndexName="client_id-index",
            KeyConditionExpression="client_id = :cid",
            ExpressionAttributeValues={":cid": client_id},
        )
        items = [_project(i) for i in resp.get("Items", [])]
        _put_query_count(client_id)
    else:
        resp = table.scan()
        items = [_project(i) for i in resp.get("Items", [])]
        _put_query_count(None)

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(items),
    }
