#!/bin/bash

set -e

REGION="us-east-2"
INSTANCE_TYPE="t3.micro"
AMI_ID="ami-0ea3c35c5c3284d82"  # Amazon Linux 2023
KEY_NAME="mcp-server-key"
SECURITY_GROUP_ID="sg-0cd2bc3fe1a14170a"

echo "🚀 Launching EC2 Instance"
echo "========================="
echo ""

# Launch instance without complex user-data
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "${AMI_ID}" \
    --instance-type "${INSTANCE_TYPE}" \
    --key-name "${KEY_NAME}" \
    --security-group-ids "${SECURITY_GROUP_ID}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=MCP-Server}]" \
    --region "${REGION}" \
    --query 'Instances[0].InstanceId' \
    --output text)

echo "✅ Instance launched: ${INSTANCE_ID}"
echo ""
echo "Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}" --region "${REGION}"

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "${INSTANCE_ID}" \
    --region "${REGION}" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo "✅ Instance is running: ${PUBLIC_IP}"
echo ""
echo "Waiting for instance initialization (120 seconds)..."
sleep 120

echo ""
echo "Testing SSH connection..."
if ssh -i ~/.ssh/${KEY_NAME}.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 ec2-user@${PUBLIC_IP} "echo 'SSH works!'" 2>&1; then
    echo "✅ SSH connection successful!"
else
    echo "❌ SSH connection failed. Waiting 60 more seconds..."
    sleep 60
fi

echo ""
echo "================================================"
echo "Instance Details:"
echo "================================================"
echo "Instance ID: ${INSTANCE_ID}"
echo "Public IP: ${PUBLIC_IP}"
echo "Region: ${REGION}"
echo ""
echo "To deploy the MCP server, run:"
echo "  ./deploy-code.sh ${PUBLIC_IP}"
echo ""
