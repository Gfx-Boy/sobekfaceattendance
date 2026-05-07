import json
import subprocess
import sys

SERVICE_ARN = "arn:aws:apprunner:us-east-1:630596767647:service/face-attendance-backend/b6139bdbad3640cfa0b334721341b6e8"
REGION = "us-east-1"
IMAGE_URI = "public.ecr.aws/k8y7f8f1/face-attendance-backend:latest"
BUCKET = "face-attendance-images-phase1"

payload = {
    "ServiceArn": SERVICE_ARN,
    "SourceConfiguration": {
        "ImageRepository": {
            "ImageIdentifier": IMAGE_URI,
            "ImageRepositoryType": "ECR_PUBLIC",
            "ImageConfiguration": {
                "Port": "3000",
                "RuntimeEnvironmentVariables": {
                    "NODE_ENV": "production",
                    "AWS_REGION": REGION,
                    "S3_BUCKET_NAME": BUCKET,
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

with open('/tmp/update_no_creds.json', 'w') as f:
    json.dump(payload, f, indent=2)
print("Payload written to /tmp/update_no_creds.json")

result = subprocess.run(
    [
        'aws', 'apprunner', 'update-service',
        '--cli-input-json', 'file:///tmp/update_no_creds.json',
        '--region', REGION,
        '--profile', 'attendance',
        '--query', 'Service.Status',
        '--output', 'text'
    ],
    capture_output=True,
    text=True
)

print("Status:", result.stdout.strip() if result.stdout else "(no stdout)")
if result.stderr:
    print("Error:", result.stderr.strip())
print("Return code:", result.returncode)
