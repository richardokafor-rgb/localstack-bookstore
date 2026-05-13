#!/usr/bin/env bash
# Deletes all bookstore resources from LocalStack.
# Every command is fire-and-forget (|| true) so the script is safe to run
# against a partially-deployed or already-clean stack.
set -uo pipefail

echo "==> Nuking LocalStack bookstore resources…"

# ── API Gateway ───────────────────────────────────────────────────────────────
echo "  API Gateway…"
for api_id in $(awslocal apigatewayv2 get-apis \
      --query 'Items[?contains(Name,`bookstore-catalog`)].ApiId' \
      --output text 2>/dev/null); do
  awslocal apigatewayv2 delete-api --api-id "$api_id" 2>/dev/null || true
  echo "    deleted API $api_id"
done

# ── Lambda ────────────────────────────────────────────────────────────────────
echo "  Lambda…"
awslocal lambda delete-function --function-name local-books-handler 2>/dev/null || true

# ── DynamoDB ──────────────────────────────────────────────────────────────────
echo "  DynamoDB…"
for table in local-books local-orders local-users; do
  awslocal dynamodb delete-table --table-name "$table" 2>/dev/null || true
done

# ── IAM (inline policies → managed attachments → role) ───────────────────────
echo "  IAM…"
for role in local-catalog-api-lambda-role \
            local-order-service-execution-role \
            local-order-service-task-role; do
  for pname in $(awslocal iam list-role-policies --role-name "$role" \
        --query 'PolicyNames[]' --output text 2>/dev/null); do
    awslocal iam delete-role-policy \
      --role-name "$role" --policy-name "$pname" 2>/dev/null || true
  done
  for parn in $(awslocal iam list-attached-role-policies --role-name "$role" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
    awslocal iam detach-role-policy \
      --role-name "$role" --policy-arn "$parn" 2>/dev/null || true
  done
  awslocal iam delete-role --role-name "$role" 2>/dev/null || true
done

# ── SQS ───────────────────────────────────────────────────────────────────────
echo "  SQS…"
for url in $(awslocal sqs list-queues \
      --queue-name-prefix "local-order" \
      --query 'QueueUrls[]' --output text 2>/dev/null); do
  awslocal sqs delete-queue --queue-url "$url" 2>/dev/null || true
done

# ── SNS ───────────────────────────────────────────────────────────────────────
echo "  SNS…"
for topic in $(awslocal sns list-topics \
      --query 'Topics[].TopicArn' --output text 2>/dev/null | tr '\t' '\n' | grep "local-order"); do
  for sub in $(awslocal sns list-subscriptions-by-topic \
        --topic-arn "$topic" \
        --query 'Subscriptions[].SubscriptionArn' --output text 2>/dev/null); do
    [[ "$sub" == "PendingConfirmation" ]] || \
      awslocal sns unsubscribe --subscription-arn "$sub" 2>/dev/null || true
  done
  awslocal sns delete-topic --topic-arn "$topic" 2>/dev/null || true
done

# ── S3 ────────────────────────────────────────────────────────────────────────
echo "  S3…"
awslocal s3 rb --force s3://local-bookstore-frontend 2>/dev/null || true

# ── CloudFront ────────────────────────────────────────────────────────────────
echo "  CloudFront…"
for dist_id in $(awslocal cloudfront list-distributions \
      --query 'DistributionList.Items[?contains(Origins.Items[0].DomainName,`bookstore`)].Id' \
      --output text 2>/dev/null); do
  etag=$(awslocal cloudfront get-distribution --id "$dist_id" \
    --query 'ETag' --output text 2>/dev/null || true)
  [[ -n "$etag" ]] && \
    awslocal cloudfront delete-distribution --id "$dist_id" --if-match "$etag" \
      2>/dev/null || true
done

# ── ECR ───────────────────────────────────────────────────────────────────────
echo "  ECR…"
awslocal ecr delete-repository \
  --repository-name local-order-service --force 2>/dev/null || true

# ── ECS ───────────────────────────────────────────────────────────────────────
echo "  ECS…"
awslocal ecs update-service \
  --cluster local-bookstore --service local-order-service \
  --desired-count 0 2>/dev/null || true
awslocal ecs delete-service \
  --cluster local-bookstore --service local-order-service \
  --force 2>/dev/null || true
for arn in $(awslocal ecs list-task-definitions \
      --family-prefix local-order-service \
      --query 'taskDefinitionArns[]' --output text 2>/dev/null); do
  awslocal ecs deregister-task-definition --task-definition "$arn" 2>/dev/null || true
done
awslocal ecs delete-cluster --cluster local-bookstore 2>/dev/null || true

# ── CloudWatch Logs ───────────────────────────────────────────────────────────
echo "  CloudWatch Logs…"
for lg in /aws/lambda/local-books-handler /ecs/local-order-service; do
  awslocal logs delete-log-group --log-group-name "$lg" 2>/dev/null || true
done

# ── VPC / networking ──────────────────────────────────────────────────────────
echo "  VPC / networking…"
for vpc_id in $(awslocal ec2 describe-vpcs \
      --filters "Name=tag:Name,Values=local-bookstore-vpc" \
      --query 'Vpcs[].VpcId' --output text 2>/dev/null); do
  for sg_id in $(awslocal ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
        --output text 2>/dev/null); do
    awslocal ec2 delete-security-group --group-id "$sg_id" 2>/dev/null || true
  done
  for subnet_id in $(awslocal ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'Subnets[].SubnetId' --output text 2>/dev/null); do
    awslocal ec2 delete-subnet --subnet-id "$subnet_id" 2>/dev/null || true
  done
  awslocal ec2 delete-vpc --vpc-id "$vpc_id" 2>/dev/null || true
done

echo "==> Nuke complete."
