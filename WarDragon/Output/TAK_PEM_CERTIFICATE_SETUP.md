# TAK Server PEM Certificate Setup Guide

## Overview

WarDragon now supports **PEM certificates** for TAK Server connections! This is the recommended format for most TAK servers.

## What Changed

### Added Support For:
- ✅ **PEM client certificates** (.pem, .crt, .cer files)
- ✅ **PEM private keys** (.key files)
- ✅ **Encrypted private keys** (with password support)
- ✅ **Multiple key formats** (PKCS#8, RSA, EC)
- ✅ **P12/PKCS12 certificates** (still supported)

### Updated Files:
1. `TAKConfiguration.swift` - Added PEM certificate fields and keychain storage
2. `TAKClient.swift` - Added PEM certificate loading and TLS configuration
3. `TAKServerSettingsView.swift` - Added PEM import UI
4. `Settings.swift` - Added PEM password storage

## How to Use PEM Certificates

### Step 1: Get Your Certificates from TAK Server

Your TAK server administrator should provide you with:
- `client.pem` or `client.crt` - Your client certificate
- `client.key` - Your private key

Some servers provide these in a combined file or separate files.

### Step 2: Import in WarDragon

1. Open **Settings** → **TAK Server**
2. Enable TAK Server if not already enabled
3. Set Protocol to **TLS**
4. In the **TLS Configuration** section:
   - Select **PEM (Recommended)** from the certificate type picker
   - Tap **Import PEM Certificate** and select your `.pem` or `.crt` file
   - Tap **Import PEM Private Key** and select your `.key` file
   - If your private key is encrypted, enter the password when prompted

5. Enter your TAK server **hostname** and **port** (usually 8089 for TLS)
6. Tap **Test Connection** to verify

### Step 3: Verify Connection

If the connection test succeeds:
- ✅ Your certificates are configured correctly
- ✅ Enable TAK Server to start sending drone data

If it fails:
- Check the error message
- Verify hostname and port
- Try enabling "Skip Certificate Verification" for testing (⚠️ UNSAFE for production)

## Troubleshooting

### "Failed to parse PEM certificate"
- Ensure the file contains `-----BEGIN CERTIFICATE-----`
- Make sure it's a valid PEM-encoded certificate

### "Failed to parse PEM private key"
- The key file should contain one of:
  - `-----BEGIN PRIVATE KEY-----` (PKCS#8)
  - `-----BEGIN RSA PRIVATE KEY-----` (RSA format)
  - `-----BEGIN EC PRIVATE KEY-----` (EC format)

### "CERTIFICATE_VERIFY_FAILED"
- Your client certificate might not be trusted by the TAK server
- The server's CA might not match your certificate
- Try enabling "Skip Certificate Verification" for testing

### "Incorrect certificate password"
- If your private key is encrypted, make sure you enter the correct password
- If your key is not encrypted, leave the password field empty

## Certificate Types Comparison

### PEM (Recommended) ✅
- **Pros:**
  - Text-based, easy to view and edit
  - Widely supported across TAK servers
  - Can easily inspect certificate details
  - Standard format for most TAK deployments
- **Cons:**
  - Requires two files (cert + key)
  
### P12/PKCS12
- **Pros:**
  - Single file contains both cert and key
  - Password protected
- **Cons:**
  - Binary format, harder to inspect
  - More complex to troubleshoot

## Security Notes

⚠️ **Keep your private keys secure!**
- Never share your private key
- Store certificates securely
- All certificates are encrypted in the iOS Keychain

⚠️ **"Skip Certificate Verification" is UNSAFE**
- Only use for testing
- Disables all TLS security checks
- Never use in production environments

## Advanced: Combined PEM Files

Some TAK servers provide a single `.pem` file containing both the certificate and private key:

```
-----BEGIN CERTIFICATE-----
[certificate data]
-----END CERTIFICATE-----
-----BEGIN RSA PRIVATE KEY-----
[private key data]
-----END RSA PRIVATE KEY-----
```

To use this:
1. Split the file into two parts
2. Save the certificate section to `client.crt`
3. Save the key section to `client.key`
4. Import both files separately

## Support

If you continue to experience issues:
1. Check the Console app logs for detailed error messages
2. Verify your certificates work with other TAK clients (ATAK/WinTAK)
3. Contact your TAK server administrator to verify certificate requirements
