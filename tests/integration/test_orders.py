"""Integration tests for DynamoDB tables, SQS, and SNS directly via boto3."""
import json
import uuid

import boto3
import pytest

ENDPOINT = "http://localhost:4566"
REGION = "us-east-1"

boto_kwargs = {
    "endpoint_url": ENDPOINT,
    "region_name": REGION,
    "aws_access_key_id": "test",
    "aws_secret_access_key": "test",
}


@pytest.fixture(scope="module")
def orders_table(dynamodb):
    return dynamodb.Table("local-orders")


@pytest.fixture(scope="module")
def order_queue_url(sqs_client):
    queues = sqs_client.list_queues(QueueNamePrefix="local-order-queue")
    urls = queues.get("QueueUrls", [])
    assert urls, "Order queue not found — did tflocal apply succeed?"
    return urls[0]


@pytest.fixture(scope="module")
def notifications_topic_arn(sns_client):
    topics = sns_client.list_topics()["Topics"]
    arns = [t["TopicArn"] for t in topics if "order-notifications" in t["TopicArn"]]
    assert arns, "Notifications topic not found"
    return arns[0]


class TestDynamoDBTables:
    def test_books_table_exists(self, dynamodb):
        table = dynamodb.Table("local-books")
        assert table.table_status in ("ACTIVE", "CREATING")

    def test_orders_table_exists(self, dynamodb):
        table = dynamodb.Table("local-orders")
        assert table.table_status in ("ACTIVE", "CREATING")

    def test_users_table_exists(self, dynamodb):
        table = dynamodb.Table("local-users")
        assert table.table_status in ("ACTIVE", "CREATING")

    def test_orders_table_put_get(self, orders_table, sample_user_id):
        order_id = str(uuid.uuid4())
        item = {
            "orderId": order_id,
            "userId": sample_user_id,
            "status": "PENDING",
            "items": [{"bookId": "book-1", "quantity": 1, "price": "9.99"}],
            "totalAmount": "9.99",
        }
        orders_table.put_item(Item=item)

        result = orders_table.get_item(Key={"orderId": order_id})
        assert "Item" in result
        assert result["Item"]["orderId"] == order_id
        assert result["Item"]["userId"] == sample_user_id

    def test_orders_table_gsi_query(self, orders_table, sample_user_id):
        from boto3.dynamodb.conditions import Key

        result = orders_table.query(
            IndexName="userId-index",
            KeyConditionExpression=Key("userId").eq(sample_user_id),
        )
        assert result["Count"] >= 1


class TestSQS:
    def test_queue_exists(self, order_queue_url):
        assert "order-queue" in order_queue_url

    def test_send_receive_message(self, sqs_client, order_queue_url):
        # Drain any pre-existing messages (e.g. leftover SNS notifications from
        # earlier smoke tests) so the assertion targets only our own message.
        while True:
            drain = sqs_client.receive_message(
                QueueUrl=order_queue_url, MaxNumberOfMessages=10, WaitTimeSeconds=0
            )
            stale = drain.get("Messages", [])
            if not stale:
                break
            for m in stale:
                sqs_client.delete_message(
                    QueueUrl=order_queue_url, ReceiptHandle=m["ReceiptHandle"]
                )

        msg = {"action": "PROCESS_ORDER", "orderId": str(uuid.uuid4())}
        sqs_client.send_message(QueueUrl=order_queue_url, MessageBody=json.dumps(msg))

        response = sqs_client.receive_message(
            QueueUrl=order_queue_url,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=2,
        )
        messages = response.get("Messages", [])
        assert messages, "No messages received from queue"
        body = json.loads(messages[0]["Body"])
        assert body["action"] == "PROCESS_ORDER"

        sqs_client.delete_message(
            QueueUrl=order_queue_url,
            ReceiptHandle=messages[0]["ReceiptHandle"],
        )

    def test_dlq_exists(self, sqs_client):
        queues = sqs_client.list_queues(QueueNamePrefix="local-order-dlq")
        assert queues.get("QueueUrls"), "DLQ not found"


class TestSNS:
    def test_topic_exists(self, notifications_topic_arn):
        assert "order-notifications" in notifications_topic_arn

    def test_publish_message(self, sns_client, notifications_topic_arn):
        payload = {"eventType": "ORDER_PLACED", "orderId": str(uuid.uuid4())}
        response = sns_client.publish(
            TopicArn=notifications_topic_arn,
            Message=json.dumps(payload),
            MessageAttributes={
                "eventType": {"DataType": "String", "StringValue": "ORDER_PLACED"}
            },
        )
        assert "MessageId" in response

    def test_sqs_subscription_exists(self, sns_client, notifications_topic_arn):
        subs = sns_client.list_subscriptions_by_topic(TopicArn=notifications_topic_arn)
        assert subs["Subscriptions"], "No subscriptions on notifications topic"
        assert any(s["Protocol"] == "sqs" for s in subs["Subscriptions"])
