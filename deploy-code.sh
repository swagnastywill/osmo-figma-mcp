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

# Copy to server
echo "Copying files to EC2..."
scp -i ~/.ssh/${KEY_NAME}.pem \
    -o StrictHostKeyChecking=no \
    /tmp/mcp-server.tar.gz \
    ec2-user@${PUBLIC_IP}:~/

# Install and configure
echo ""
echo "Installing on EC2..."
ssh -i ~/.ssh/${KEY_NAME}.pem \
    -o StrictHostKeyChecking=no \
    ec2-user@${PUBLIC_IP} << 'SSHEOF'

# Update system and install Node.js
echo "Installing Node.js..."
sudo dnf update -y
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo dnf install -y nodejs

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
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/usr/bin/node dist/bin.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PORT=3333

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
