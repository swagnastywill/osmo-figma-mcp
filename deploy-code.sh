#!/bin/bash

set -e

if [ -z "$1" ]; then
    echo "Usage: ./deploy-code.sh <PUBLIC_IP>"
    exit 1
fi

PUBLIC_IP=$1
KEY_NAME="mcp-server-key"

echo "📦 Deploying MCP Server to ${PUBLIC_IP}"
echo "========================================"
echo ""

# Build and package
echo "Building project..."
npm run build

echo "Creating deployment package..."
tar -czf /tmp/mcp-server.tar.gz \
    dist/ \
    package.json \
    pnpm-lock.yaml \
    .env

# Copy to server (detect username)
echo "Copying files to EC2..."
# Try ubuntu first, fallback to ec2-user
if ssh -i ~/.ssh/${KEY_NAME}.pem -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@${PUBLIC_IP} 'echo ok' &>/dev/null; then
    EC2_USER="ubuntu"
else
    EC2_USER="ec2-user"
fi
echo "Using username: ${EC2_USER}"

scp -i ~/.ssh/${KEY_NAME}.pem \
    -o StrictHostKeyChecking=no \
    /tmp/mcp-server.tar.gz \
    ${EC2_USER}@${PUBLIC_IP}:~/

# Install and configure
echo ""
echo "Installing on EC2..."
ssh -i ~/.ssh/${KEY_NAME}.pem \
    -o StrictHostKeyChecking=no \
    ${EC2_USER}@${PUBLIC_IP} << 'SSHEOF'

# Update system and install Node.js
echo "Installing Node.js..."
# Detect OS and install accordingly
if [ -f /etc/debian_version ]; then
    # Ubuntu/Debian
    sudo apt-get update -y
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
else
    # Amazon Linux
    sudo dnf update -y
    curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
    sudo dnf install -y nodejs
fi

# Install pnpm
sudo npm install -g pnpm

# Extract and install
tar -xzf mcp-server.tar.gz
rm mcp-server.tar.gz
pnpm install --prod

# Create systemd service
echo "Creating systemd service..."
sudo tee /etc/systemd/system/mcp-server.service > /dev/null << 'SERVICEEOF'
[Unit]
Description=Figma MCP Server
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$(pwd)
ExecStart=/usr/bin/node dist/bin.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PORT=3333
EnvironmentFile=$(pwd)/.env

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Start service
sudo systemctl daemon-reload
sudo systemctl enable mcp-server
sudo systemctl start mcp-server

echo ""
echo "✅ MCP Server deployed and started!"
echo ""
echo "Checking status..."
sudo systemctl status mcp-server --no-pager
SSHEOF

echo ""
echo "================================================"
echo "🎉 DEPLOYMENT COMPLETE!"
echo "================================================"
echo ""
echo "Your MCP Server is running at:"
echo "  http://${PUBLIC_IP}:3333"
echo ""
echo "To check logs:"
echo "  ssh -i ~/.ssh/${KEY_NAME}.pem ec2-user@${PUBLIC_IP} 'sudo journalctl -u mcp-server -f'"
echo ""
echo "To check status:"
echo "  ssh -i ~/.ssh/${KEY_NAME}.pem ec2-user@${PUBLIC_IP} 'sudo systemctl status mcp-server'"
echo ""
