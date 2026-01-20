#!/bin/bash

# Script to set up AWS credentials for Figma MCP Server
# This should be run AFTER deploying the code to EC2

set -e

if [ -z "$1" ]; then
    echo "Usage: ./setup-aws-credentials.sh <PUBLIC_IP>"
    exit 1
fi

PUBLIC_IP=$1
KEY_NAME="mcp-server-key"

echo "🔐 Setting up AWS Credentials on EC2"
echo "======================================"
echo ""
echo "Please enter your AWS credentials:"
echo ""

read -p "AWS Region (e.g., us-east-2): " AWS_REGION
read -p "S3 Bucket Name: " AWS_BUCKET_NAME
read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
read -sp "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
echo ""
echo ""

# Create .env file content
ENV_CONTENT="# Figma MCP Server - AWS Configuration
NODE_ENV=production
PORT=3333
OUTPUT_FORMAT=yaml

# AWS S3 Configuration
AWS_REGION=${AWS_REGION}
AWS_BUCKET_NAME=${AWS_BUCKET_NAME}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
"

echo "Uploading credentials to EC2..."
echo "$ENV_CONTENT" | ssh -i ~/.ssh/${KEY_NAME}.pem \
    -o StrictHostKeyChecking=no \
    ec2-user@${PUBLIC_IP} 'cat > ~/.env'

echo ""
echo "Restarting MCP server..."
ssh -i ~/.ssh/${KEY_NAME}.pem \
    -o StrictHostKeyChecking=no \
    ec2-user@${PUBLIC_IP} 'sudo systemctl restart mcp-server'

echo ""
echo "✅ AWS credentials configured!"
echo ""
echo "Checking server status..."
ssh -i ~/.ssh/${KEY_NAME}.pem \
    -o StrictHostKeyChecking=no \
    ec2-user@${PUBLIC_IP} 'sudo systemctl status mcp-server --no-pager'

echo ""
echo "================================================"
echo "🎉 SETUP COMPLETE!"
echo "================================================"
echo ""
echo "Your MCP Server now has AWS credentials configured."
echo "Images will be uploaded to: s3://${AWS_BUCKET_NAME}"
echo ""
echo "To verify, check the logs:"
echo "  ssh -i ~/.ssh/${KEY_NAME}.pem ec2-user@${PUBLIC_IP} 'sudo journalctl -u mcp-server -f'"
echo ""
