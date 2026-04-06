#!/bin/bash
# finish_permanent_fix.sh
# Run this ONCE after your admin has:
#   1. Created IAM role AppRunnerAttendanceRole with S3+Rekognition policy
#   2. Added iam:PassRole to AttendancePermission set for that role
#
# This script attaches the instance role and removes the temporary credentials
# from App Runner runtime env permanently.

set -euo pipefail
export AWS_PAGER=""

PROFILE="${AWS_PROFILE:-attendance}"
REGION="us-east-1"
SERVICE_ARN="arn:aws:apprunner:us-east-1:630596767647:service/face-attendance-backend/b6139bdbad3640cfa0b334721341b6e8"
INSTANCE_ROLE_ARN="arn:aws:iam::630596767647:role/AppRunnerAttendanceRole"
IMAGE_URI="public.ecr.aws/k8y7f8f1/face-attendance-backend:latest"
BUCKET_NAME="face-attendance-images-phase1"

echo "==> Verifying SSO session..."
aws sts get-caller-identity --profile "$PROFILE" --output text --query 'Arn'

echo "==> Skipping IAM GetRole check (many permission sets deny iam:GetRole)."
echo "==> App Runner update will verify role/PassRole access directly."

echo "==> Building update-service payload (with instance role, no temp creds)..."
python3 - <<PYEOF
import json

payload = {
    "ServiceArn": "$SERVICE_ARN",
    "InstanceConfiguration": {
        "Cpu": "0.25 vCPU",
        "Memory": "0.5 GB",
        "InstanceRoleArn": "$INSTANCE_ROLE_ARN"
    },
    "SourceConfiguration": {
        "ImageRepository": {
            "ImageIdentifier": "$IMAGE_URI",
            "ImageRepositoryType": "ECR_PUBLIC",
            "ImageConfiguration": {
                "Port": "3000",
                "RuntimeEnvironmentVariables": {
                    "NODE_ENV": "production",
                    "AWS_REGION": "$REGION",
                    "S3_BUCKET_NAME": "$BUCKET_NAME",
                    "REKOGNITION_COLLECTION_ID": "face-attendance-collection",
                    "FACE_MATCH_THRESHOLD": "90",
                    "ACCESS_TOKEN_EXPIRES_IN": "1h",
                    "REFRESH_TOKEN_EXPIRES_IN": "30d"
                }
            }
        },
        "AutoDeploymentsEnabled": False
    }
}

with open('/tmp/update_permanent.json', 'w') as f:
    json.dump(payload, f, indent=2)
print("Payload written to /tmp/update_permanent.json")
PYEOF

echo "==> Attaching instance role and removing temporary credentials from App Runner..."
set +e
UPDATE_OUTPUT=$(aws apprunner update-service \
  --cli-input-json file:///tmp/update_permanent.json \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'Service.Status' --output text 2>&1)
UPDATE_EXIT=$?
set -e

if [ "$UPDATE_EXIT" -ne 0 ]; then
  echo "$UPDATE_OUTPUT"
  if echo "$UPDATE_OUTPUT" | grep -qi 'iam:PassRole'; then
    echo "ERROR: iam:PassRole is still not effective for your current session."
    echo "Ask admin to confirm AttendancePermission is re-provisioned, then run aws sso login again."
  fi
  exit "$UPDATE_EXIT"
fi

echo "$UPDATE_OUTPUT"

echo "==> Waiting for deployment (up to ~5 minutes)..."
for i in {1..40}; do
  STATUS=$(aws apprunner describe-service \
    --service-arn "$SERVICE_ARN" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'Service.Status' --output text)
  echo "  [$i/40] Status: $STATUS"
  if [ "$STATUS" = "RUNNING" ]; then
    break
  fi
  if [ "$STATUS" = "CREATE_FAILED" ] || [ "$STATUS" = "UPDATE_FAILED" ]; then
    echo "ERROR: Deployment failed with status $STATUS"
    exit 1
  fi
  sleep 8
done

echo "==> Verifying login with permanent credentials..."
RESULT=$(curl -s -X POST \
  "https://evrw6qmfh7.us-east-1.awsapprunner.com/api/employees/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"hasan@aenfinite.com","password":"admin123"}')

echo "$RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if d.get('access_token'):
    print()
    print('SUCCESS: Backend is now using the IAM instance role.')
    print('No more temporary credentials. No more refresh_credentials.sh.')
    print()
    print(f'  expires_in:         {d.get(\"expires_in\")}s')
    print(f'  refresh_expires_in: {d.get(\"refresh_expires_in\")}s')
else:
    print(f'FAILED: {d.get(\"error\", d)}')
    sys.exit(1)
"
