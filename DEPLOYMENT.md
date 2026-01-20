# AWS Production Deployment

Deploy the Figma MCP Server to AWS EC2 for production use.

## Prerequisites
- AWS CLI installed locally
- AWS account with EC2 permissions  
- SSH key pair created in AWS (named `mcp-server-key`)

## Production Deployment Workflow

### 1. Configure Local AWS CLI
```bash
cd deployment/
./configure-aws.sh
```

### 2. Launch EC2 Instance
```bash
./launch-instance.sh
```
Returns the public IP address for the next steps.

### 3. Deploy the MCP Server
```bash
./deploy-code.sh <PUBLIC_IP>
```
Builds, uploads, and starts the server as a systemd service.

### 4. Configure S3 Credentials
```bash
./setup-aws-credentials.sh <PUBLIC_IP>
```
Sets up S3 access for image uploads.

## Production Scripts

| Script | Purpose |
|--------|---------|
| `configure-aws.sh` | Set up local AWS CLI credentials |
| `launch-instance.sh` | Launch new EC2 instance |
| `deploy-code.sh` | Deploy MCP server to EC2 |
| `setup-aws-credentials.sh` | Configure S3 credentials on EC2 |

## Server Management

After deployment, manage your server:

```bash
# Check status
ssh -i ~/.ssh/mcp-server-key.pem ec2-user@<PUBLIC_IP> 'sudo systemctl status mcp-server'

# View logs
ssh -i ~/.ssh/mcp-server-key.pem ec2-user@<PUBLIC_IP> 'sudo journalctl -u mcp-server -f'

# Restart server
ssh -i ~/.ssh/mcp-server-key.pem ec2-user@<PUBLIC_IP> 'sudo systemctl restart mcp-server'
```

Your server will be available at: `http://<PUBLIC_IP>:3333`