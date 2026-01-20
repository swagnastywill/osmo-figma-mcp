#!/bin/bash

echo "🔐 Secure AWS Configuration"
echo "==========================="
echo ""
echo "This script will securely configure AWS CLI."
echo "Your credentials will be stored in ~/.aws/credentials"
echo ""

# Prompt for credentials (input will be hidden for secret key)
read -p "Enter your AWS Access Key ID: " ACCESS_KEY
read -sp "Enter your AWS Secret Access Key: " SECRET_KEY
echo ""
read -p "Enter your preferred AWS region (e.g., us-east-1): " REGION

# Configure AWS
aws configure set aws_access_key_id "$ACCESS_KEY"
aws configure set aws_secret_access_key "$SECRET_KEY"
aws configure set region "$REGION"
aws configure set output json

echo ""
echo "✅ AWS CLI configured!"
echo ""
echo "Testing connection..."
aws sts get-caller-identity

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Success! AWS is configured and working."
else
    echo ""
    echo "❌ Configuration failed. Please check your credentials."
fi
