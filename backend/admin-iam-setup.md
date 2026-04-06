# One-Time Admin Fix: Permanent AWS Credentials for App Runner

## Problem

The App Runner container currently uses temporary AWS SSO session credentials
(`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) injected as
environment variables. These expire every 10–12 hours, causing 500 errors.

## Solution (admin does this once)

Attach a permanent IAM instance role to App Runner. The container will then
call AWS services as that role — no expiring tokens ever.

---

## Step 1 — Create the IAM Instance Role

Go to **IAM → Roles → Create role**.

**Trusted entity type:** AWS service  
**Use case:** (scroll down) → `App Runner Task` (or paste the trust policy below manually)

**Trust policy JSON:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "tasks.apprunner.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

**Role name:** `AppRunnerAttendanceRole`  
**Description:** Instance role for face-attendance App Runner service

---

## Step 2 — Attach Permissions to the Role

After creating the role, go to its **Permissions** tab → **Add permissions → Create inline policy**.

**Policy JSON:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3FaceAttendance",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::face-attendance-images-phase1",
        "arn:aws:s3:::face-attendance-images-phase1/*"
      ]
    },
    {
      "Sid": "RekognitionFaceAttendance",
      "Effect": "Allow",
      "Action": [
        "rekognition:CreateCollection",
        "rekognition:DeleteCollection",
        "rekognition:IndexFaces",
        "rekognition:SearchFacesByImage",
        "rekognition:DeleteFaces",
        "rekognition:ListFaces",
        "rekognition:DescribeCollection",
        "rekognition:ListCollections"
      ],
      "Resource": "*"
    }
  ]
}
```

**Policy name:** `FaceAttendanceS3Rekognition`

After saving, the role ARN will be:
```
arn:aws:iam::630596767647:role/AppRunnerAttendanceRole
```

---

## Step 3 — Grant `iam:PassRole` to the AttendancePermission Set

This is the one permission missing that blocks the developer from attaching the
role themselves. Add it as an inline policy on the **AttendancePermission**
permission set in **IAM Identity Center**.

Go to **IAM Identity Center → Permission sets → AttendancePermission → Inline policy → Edit**.

Add this statement to the existing inline policy (or create one if none exists):

```json
{
  "Sid": "AllowPassRoleToAppRunner",
  "Effect": "Allow",
  "Action": "iam:PassRole",
  "Resource": "arn:aws:iam::630596767647:role/AppRunnerAttendanceRole",
  "Condition": {
    "StringEquals": {
      "iam:PassedToService": [
        "tasks.apprunner.amazonaws.com",
        "apprunner.amazonaws.com"
      ]
    }
  }
}
```

> This is scoped to only the one role and only for App Runner — minimal blast radius.

After saving the permission set, re-provision it (IAM Identity Center will
prompt you, or go to **AWS Accounts → Re-provision**).

---

## Step 4 — Developer runs finish script

Once Step 3 is done, the developer runs this one command from their terminal:

```bash
cd /Users/hasanhsb/FaceRecognition/face_attendance/backend
bash finish_permanent_fix.sh
```

That script will:
1. Attach `AppRunnerAttendanceRole` to the App Runner service
2. Remove `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` from runtime env
3. Deploy and verify the service is running with permanent credentials

---

## Verification (after script)

Once deployed, login should still return HTTP 200 with no credential-related errors.
Run:
```bash
curl -s -X POST https://evrw6qmfh7.us-east-1.awsapprunner.com/api/employees/login \
  -H "Content-Type: application/json" \
  -d '{"email":"hasan@aenfinite.com","password":"admin123"}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK' if d.get('access_token') else d.get('error'))"
```

Expected output: `OK`

## After This Fix

- `refresh_credentials.sh` is no longer needed
- The 500 error will never return due to credential expiry
- App Runner automatically uses the instance role for all S3 and Rekognition calls
