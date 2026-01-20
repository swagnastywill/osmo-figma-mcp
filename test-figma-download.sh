#!/bin/bash

# Test script for Figma MCP Server
# Tests with the Teamout design file

set -e

MCP_SERVER="http://18.119.10.65:3333/mcp"
FILE_KEY="eXhID3gvQHcLZMu5IPjrnA"
NODE_ID="195:2990"

# Check if FIGMA_TOKEN is set
if [ -z "$FIGMA_TOKEN" ]; then
    echo "❌ Error: FIGMA_TOKEN environment variable not set"
    echo ""
    echo "Usage: FIGMA_TOKEN='figd_...' ./test-figma-download.sh"
    echo ""
    echo "Get your token from: https://www.figma.com/developers/api#access-tokens"
    exit 1
fi

echo "🧪 Testing Figma MCP Server"
echo "============================"
echo "Server: ${MCP_SERVER}"
echo "File: ${FILE_KEY}"
echo "Node: ${NODE_ID}"
echo ""

# Step 1: Initialize session
echo "1️⃣ Initializing MCP session..."
INIT_RESPONSE=$(curl -s -X POST "${MCP_SERVER}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"initialize\",
    \"params\": {
      \"protocolVersion\": \"2024-11-05\",
      \"clientInfo\": {\"name\": \"test-client\", \"version\": \"1.0\"},
      \"capabilities\": {}
    },
    \"id\": 1
  }")

# Extract session ID from response
SESSION_ID=$(echo "$INIT_RESPONSE" | grep -o 'mcp-session-id: [a-f0-9-]*' | cut -d' ' -f2 || \
             echo "$INIT_RESPONSE" | grep -o '"sessionId":"[^"]*"' | cut -d'"' -f4)

if [ -z "$SESSION_ID" ]; then
    echo "❌ Failed to get session ID"
    echo "Response: $INIT_RESPONSE"
    exit 1
fi

echo "✅ Session ID: ${SESSION_ID}"
echo ""

# Step 2: Get Figma data to see what's in this node
echo "2️⃣ Fetching Figma design data..."
DATA_RESPONSE=$(curl -s -X POST "${MCP_SERVER}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "mcp-session-id: ${SESSION_ID}" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"tools/call\",
    \"params\": {
      \"name\": \"get_figma_data\",
      \"arguments\": {
        \"fileKey\": \"${FILE_KEY}\",
        \"nodeId\": \"${NODE_ID}\",
        \"figmaOAuthToken\": \"${FIGMA_TOKEN}\"
      }
    },
    \"id\": 2
  }")

echo "Design data response:"
echo "$DATA_RESPONSE" | jq -r '.result.content[0].text' 2>/dev/null || echo "$DATA_RESPONSE"
echo ""

# Step 3: Download images from this node
echo "3️⃣ Testing image download..."
echo "Calling download_figma_images..."
echo ""

IMAGE_RESPONSE=$(curl -s -X POST "${MCP_SERVER}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "mcp-session-id: ${SESSION_ID}" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"tools/call\",
    \"params\": {
      \"name\": \"download_figma_images\",
      \"arguments\": {
        \"fileKey\": \"${FILE_KEY}\",
        \"nodes\": [
          {
            \"nodeId\": \"${NODE_ID}\",
            \"fileName\": \"teamout-image.png\"
          }
        ],
        \"pngScale\": 2,
        \"figmaOAuthToken\": \"${FIGMA_TOKEN}\"
      }
    },
    \"id\": 3
  }")

echo "📦 Image Download Response:"
echo "============================"
echo ""

# Extract and display the response text
RESPONSE_TEXT=$(echo "$IMAGE_RESPONSE" | jq -r '.result.content[0].text' 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$RESPONSE_TEXT" ]; then
    echo "$RESPONSE_TEXT"
    echo ""
    
    # Check for S3 URLs
    if echo "$RESPONSE_TEXT" | grep -q "S3 URL:"; then
        echo "✅ SUCCESS: S3 URLs found in response!"
        echo ""
        echo "🔗 Extracted S3 URLs:"
        echo "$RESPONSE_TEXT" | grep "S3 URL:" | sed 's/.*S3 URL: /  - /'
    else
        echo "⚠️  No S3 URLs found in response"
    fi
else
    echo "❌ Error in response:"
    echo "$IMAGE_RESPONSE" | jq '.' 2>/dev/null || echo "$IMAGE_RESPONSE"
fi

echo ""
echo "============================"
echo "Test complete!"
