#!/bin/bash
# Refresh AWS SSO credentials and push them to App Runner runtime env.
# Usage: bash refresh_credentials.sh

set -euo pipefail

PROFILE="${AWS_PROFILE:-attendance}"
REGION="${AWS_REGION:-us-east-1}"
BUCKET_NAME="${S3_BUCKET_NAME:-face-attendance-images-phase1}"
SERVICE_ARN="arn:aws:apprunner:us-east-1:630596767647:service/face-attendance-backend/b6139bdbad3640cfa0b334721341b6e8"
IMAGE_URI="public.ecr.aws/k8y7f8f1/face-attendance-backend:latest"

echo "==> Refreshing AWS SSO session for profile '$PROFILE'..."
aws sso login --profile "$PROFILE"

echo "==> Exporting fresh credentials..."
CREDS_JSON="$(aws configure export-credentials --profile "$PROFILE")"
EXPIRATION="$(echo "$CREDS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Expiration','unknown'))")"
ACCESS_KEY="$(echo "$CREDS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['AccessKeyId'])")"
SECRET_KEY="$(echo "$CREDS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['SecretAccessKey'])")"
SESSION_TOKEN="$(echo "$CREDS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['SessionToken'])")"

echo "==> Building App Runner update payload..."
ACCESS_KEY="$ACCESS_KEY" \
SECRET_KEY="$SECRET_KEY" \
SESSION_TOKEN="$SESSION_TOKEN" \
REGION="$REGION" \
BUCKET_NAME="$BUCKET_NAME" \
SERVICE_ARN="$SERVICE_ARN" \
IMAGE_URI="$IMAGE_URI" \
python3 - <<'PYEOF'
import json
import os

payload = {
    "ServiceArn": os.environ["SERVICE_ARN"],
    "SourceConfiguration": {
        "ImageRepository": {
            "ImageIdentifier": os.environ["IMAGE_URI"],
            "ImageRepositoryType": "ECR_PUBLIC",
            "ImageConfiguration": {
                "Port": "3000",
                "RuntimeEnvironmentVariables": {
                    "NODE_ENV": "production",
                    "AWS_REGION": os.environ["REGION"],
                    "S3_BUCKET_NAME": os.environ["BUCKET_NAME"],
                    "AWS_ACCESS_KEY_ID": os.environ["ACCESS_KEY"],
                    "AWS_SECRET_ACCESS_KEY": os.environ["SECRET_KEY"],
                    "AWS_SESSION_TOKEN": os.environ["SESSION_TOKEN"],
                },
            },
        },
        "AutoDeploymentsEnabled": False,
    },
}

with open('/tmp/update_service.json', 'w', encoding='utf-8') as f:
    json.dump(payload, f)
print('Payload written to /tmp/update_service.json')
PYEOF

echo "==> Updating App Runner service..."
aws apprunner update-service \
  --cli-input-json file:///tmp/update_service.json \
  --region "$REGION" \
  --profile "$PROFILE" >/tmp/apprunner-update-result.json

STATUS="$(python3 - <<'PYEOF'
import json
with open('/tmp/apprunner-update-result.json', 'r', encoding='utf-8') as f:
    data = json.load(f)
print(data.get('Service', {}).get('Status', 'unknown'))
PYEOF
)"

echo "==> App Runner update submitted. Current status: $STATUS"
echo "==> Credential expiration: $EXPIRATION"
