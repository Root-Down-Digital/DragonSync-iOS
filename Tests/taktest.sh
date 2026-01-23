#!/bin/bash

HOST="${1:-takserver.example.com}"
USERNAME="${2:-testuser}"
PASSWORD="${3:-testpass}"

echo "=== TAK Server Connectivity Test ==="
echo "Host: $HOST"
echo ""

# Test 1: Basic connectivity
echo "[1] Testing basic connectivity..."
ping -c 3 $HOST > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Host is reachable"
else
    echo "✗ Host is unreachable"
    exit 1
fi

# Test 2: Enrollment port (8446)
echo ""
echo "[2] Testing enrollment port (8446)..."
timeout 5 bash -c "cat < /dev/null > /dev/tcp/$HOST/8446" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✓ Port 8446 is open"
    
    # Test HTTPS on enrollment port
    curl -k -s -o /dev/null -w "%{http_code}" https://$HOST:8446/Marti/api/tls > /tmp/status.txt
    STATUS=$(cat /tmp/status.txt)
    if [ "$STATUS" = "200" ] || [ "$STATUS" = "401" ]; then
        echo "✓ Enrollment endpoint responding (HTTP $STATUS)"
    else
        echo "⚠ Enrollment endpoint returned HTTP $STATUS"
    fi
else
    echo "✗ Port 8446 is closed or filtered"
fi

# Test 3: Streaming ports
echo ""
echo "[3] Testing streaming ports..."
for PORT in 8087 8089; do
    timeout 5 bash -c "cat < /dev/null > /dev/tcp/$HOST/$PORT" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✓ Port $PORT is open"
    else
        echo "✗ Port $PORT is closed or filtered"
    fi
done

# Test 4: Download truststore
echo ""
echo "[4] Testing truststore download..."
curl -k -s https://$HOST/api/truststore -o /tmp/truststore.pem 2>/dev/null
if [ $? -eq 0 ] && [ -f /tmp/truststore.pem ]; then
    SIZE=$(wc -c < /tmp/truststore.pem)
    echo "✓ Truststore downloaded ($SIZE bytes)"
    
    # Verify it's a valid certificate
    openssl x509 -in /tmp/truststore.pem -noout -subject 2>/dev/null
    if [ $? -eq 0 ]; then
        SUBJECT=$(openssl x509 -in /tmp/truststore.pem -noout -subject 2>/dev/null)
        echo "  Subject: $SUBJECT"
    fi
else
    echo "⚠ Truststore download failed or unavailable"
fi

# Test 5: Test enrollment with credentials (if provided)
if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
    echo ""
    echo "[5] Testing enrollment authentication..."
    
    RESPONSE=$(curl -k -s -w "\n%{http_code}" \
        -u "$USERNAME:$PASSWORD" \
        https://$HOST:8446/Marti/api/tls/config 2>/dev/null)
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✓ Authentication successful"
    elif [ "$HTTP_CODE" = "401" ]; then
        echo "✗ Authentication failed - check credentials"
    else
        echo "⚠ Unexpected response: HTTP $HTTP_CODE"
    fi
fi

# Test 6: Certificate chain validation
echo ""
echo "[6] Testing TLS certificate chain..."
echo | openssl s_client -connect $HOST:8446 -showcerts 2>/dev/null | \
    openssl x509 -noout -dates 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✓ TLS certificate valid"
    EXPIRY=$(echo | openssl s_client -connect $HOST:8446 -showcerts 2>/dev/null | \
        openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    echo "  Expires: $EXPIRY"
else
    echo "⚠ Could not validate certificate"
fi

echo ""
echo "=== Test Complete ==="
