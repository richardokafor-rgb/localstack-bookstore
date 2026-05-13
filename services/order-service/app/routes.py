import json
import os
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from flask import Blueprint, jsonify, request
from boto3.dynamodb.conditions import Key

from .models import Order

bp = Blueprint("orders", __name__)

endpoint = os.getenv("AWS_ENDPOINT_URL")
region = os.getenv("AWS_DEFAULT_REGION", "us-east-1")
boto_kwargs = {"endpoint_url": endpoint, "region_name": region} if endpoint else {"region_name": region}

dynamodb = boto3.resource("dynamodb", **boto_kwargs)
sqs = boto3.client("sqs", **boto_kwargs)
sns = boto3.client("sns", **boto_kwargs)

ORDERS_TABLE = os.environ["ORDERS_TABLE"]
USERS_TABLE = os.environ["USERS_TABLE"]
ORDER_QUEUE_URL = os.environ["ORDER_QUEUE_URL"]
NOTIFICATIONS_TOPIC_ARN = os.environ["NOTIFICATIONS_TOPIC_ARN"]

orders_table = dynamodb.Table(ORDERS_TABLE)
users_table = dynamodb.Table(USERS_TABLE)


class _DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)


def _publish_event(event_type: str, payload: dict):
    sns.publish(
        TopicArn=NOTIFICATIONS_TOPIC_ARN,
        Message=json.dumps(payload, cls=_DecimalEncoder),
        MessageAttributes={
            "eventType": {"DataType": "String", "StringValue": event_type}
        },
    )


@bp.get("/health")
def health():
    return jsonify({"status": "ok", "service": "order-service"})


@bp.get("/orders")
def list_orders():
    user_id = request.args.get("userId")
    if user_id:
        result = orders_table.query(
            IndexName="userId-index",
            KeyConditionExpression=Key("userId").eq(user_id),
        )
    else:
        result = orders_table.scan()
    return jsonify(result["Items"])


@bp.post("/orders")
def create_order():
    data = request.get_json(force=True)
    if not data.get("userId") or not data.get("items"):
        return jsonify({"message": "userId and items are required"}), 400

    # DynamoDB resource requires Decimal, not float
    items = [
        {**item, "price": Decimal(str(item["price"]))} for item in data["items"]
    ]
    total = Decimal(str(sum(
        float(item["price"]) * item.get("quantity", 1) for item in items
    )))
    order = Order(userId=data["userId"], items=items, totalAmount=total)
    orders_table.put_item(Item=order.to_dict())

    sqs.send_message(
        QueueUrl=ORDER_QUEUE_URL,
        MessageBody=json.dumps({"action": "PROCESS_ORDER", "orderId": order.orderId}),
    )
    _publish_event("ORDER_PLACED", order.to_dict())

    return jsonify(order.to_dict()), 201


@bp.get("/orders/<order_id>")
def get_order(order_id):
    result = orders_table.get_item(Key={"orderId": order_id})
    if "Item" not in result:
        return jsonify({"message": "Order not found"}), 404
    return jsonify(result["Item"])


@bp.put("/orders/<order_id>/status")
def update_order_status(order_id):
    data = request.get_json(force=True)
    new_status = data.get("status")
    valid = {"PENDING", "PROCESSING", "SHIPPED", "DELIVERED", "CANCELLED"}
    if new_status not in valid:
        return jsonify({"message": f"Invalid status. Must be one of: {valid}"}), 400

    now = datetime.now(timezone.utc).isoformat()
    try:
        result = orders_table.update_item(
            Key={"orderId": order_id},
            UpdateExpression="SET #s = :s, updatedAt = :ts",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":s": new_status, ":ts": now},
            ConditionExpression="attribute_exists(orderId)",
            ReturnValues="ALL_NEW",
        )
    except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
        return jsonify({"message": "Order not found"}), 404

    _publish_event("ORDER_UPDATED", result["Attributes"])
    return jsonify(result["Attributes"])
