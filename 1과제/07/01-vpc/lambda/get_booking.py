import json
import os

import boto3

TABLE_NAME = os.environ["TABLE_NAME"]
dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION"))
table = dynamodb.Table(TABLE_NAME)


def handler(event, context):
    qs = event.get("queryStringParameters") or {}
    booking_id = qs.get("booking_id")
    email = qs.get("email")
    concert_name = qs.get("concert_name")

    if not booking_id:
        return _response(400, {"error": "booking_id is required"})

    item = table.get_item(Key={"booking_id": booking_id}).get("Item")
    if not item:
        return _response(404, {"error": "booking not found"})

    if email and item.get("email") != email:
        return _response(404, {"error": "booking not found"})
    if concert_name and item.get("concert_name") != concert_name:
        return _response(404, {"error": "booking not found"})

    return _response(200, item)


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "statusDescription": f"{status_code} OK" if status_code == 200 else f"{status_code} Error",
        "isBase64Encoded": False,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str),
    }
