#!/bin/bash

# Environment validation script for OpenVidu MinIO configuration
# Usage: ./validate-env.sh [.env file path]

set -e

ENV_FILE="${1:-.env}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Function to load environment variables from file
load_env_file() {
    if [ ! -f "$ENV_FILE" ]; then
        print_status "$RED" "❌ Environment file not found: $ENV_FILE"
        echo
        print_status "$YELLOW" "📝 To create the .env file, you need to define the following variables:"
        echo
        show_env_template
        echo
        print_status "$RED" "🛑 Please create the .env file with the correct values and run this script again"
        exit 1
    fi
    
    print_status "$BLUE" "📄 Loading environment from: $ENV_FILE"
    
    # Export variables from .env file
    set -a
    source "$ENV_FILE"
    set +a
}

# Function to show .env template information (but not create the file)
show_env_template() {
    print_status "$BLUE" "Required .env file format (based on your HA Recorder configuration):"
    cat << 'EOF'
# HA Recorder Configuration
HA_RECORDING_STORAGE=local
CHUNK_FOLDER=/local-chunks
CHUNK_TIME_SIZE=20

# MinIO/S3 Configuration
# CRITICAL: HA_AWS_S3_SERVICE_ENDPOINT must match http://YOUR_PRIVATE_IP:MINIO_API_PORT
HA_AWS_S3_SERVICE_ENDPOINT=http://172.31.0.96:9000
HA_AWS_S3_BUCKET=ov-recordings
HA_AWS_ACCESS_KEY=naeva_minio
HA_AWS_SECRET_KEY=N43v4t3c_M1n10
MINIO_API_PORT=9000

# Additional Configuration
TAG=latest
MINIO_CONSOLE_PORT=9001
EOF
    echo
    print_status "$YELLOW" "⚠️  IMPORTANT: Make sure to:"
    echo "   1. Replace 172.31.0.96 with your actual private IP"
    echo "   2. Ensure HA_AWS_S3_SERVICE_ENDPOINT matches http://YOUR_PRIVATE_IP:MINIO_API_PORT"
    echo "   3. Use strong credentials in production"
}

# Function to validate IP address format
validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Function to validate port number
validate_port() {
    local port="$1"
    if [[ $port =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Function to validate required variables
validate_variables() {
    local errors=0
    
    print_status "$BLUE" "🔍 Validating environment variables..."
    
    # Extract private IP from HA_AWS_S3_SERVICE_ENDPOINT
    if [ -n "$HA_AWS_S3_SERVICE_ENDPOINT" ]; then
        PRIVATE_IP=$(echo "$HA_AWS_S3_SERVICE_ENDPOINT" | sed -n 's|^http://\([^:]*\):.*|\1|p')
        if [ -z "$PRIVATE_IP" ]; then
            print_status "$RED" "❌ Cannot extract IP from HA_AWS_S3_SERVICE_ENDPOINT: $HA_AWS_S3_SERVICE_ENDPOINT"
            ((errors++))
        fi
    fi
    
    # Check required variables exist
    local required_vars=("HA_AWS_S3_SERVICE_ENDPOINT" "MINIO_API_PORT" "HA_AWS_S3_BUCKET" "HA_AWS_ACCESS_KEY" "HA_AWS_SECRET_KEY")
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            print_status "$RED" "❌ Required variable $var is not set"
            ((errors++))
        fi
    done
    
    if [ $errors -gt 0 ]; then
        return 1
    fi
    
    # Validate IP address format (extracted from endpoint)
    if [ -n "$PRIVATE_IP" ] && ! validate_ip "$PRIVATE_IP"; then
        print_status "$RED" "❌ IP extracted from HA_AWS_S3_SERVICE_ENDPOINT '$PRIVATE_IP' is not a valid IP address"
        ((errors++))
    fi
    
    # Validate port numbers
    if ! validate_port "$MINIO_API_PORT"; then
        print_status "$RED" "❌ MINIO_API_PORT '$MINIO_API_PORT' is not a valid port number (1-65535)"
        ((errors++))
    fi
    
    if [ -n "$MINIO_CONSOLE_PORT" ] && ! validate_port "$MINIO_CONSOLE_PORT"; then
        print_status "$RED" "❌ MINIO_CONSOLE_PORT '$MINIO_CONSOLE_PORT' is not a valid port number (1-65535)"
        ((errors++))
    fi
    
    # Validate HA_AWS_S3_SERVICE_ENDPOINT format and consistency
    local expected_endpoint="http://${PRIVATE_IP}:${MINIO_API_PORT}"
    
    if [ "$HA_AWS_S3_SERVICE_ENDPOINT" != "$expected_endpoint" ]; then
        print_status "$RED" "❌ HA_AWS_S3_SERVICE_ENDPOINT inconsistency!"
        print_status "$RED" "   Current: $HA_AWS_S3_SERVICE_ENDPOINT"
        print_status "$RED" "   Expected: $expected_endpoint"
        print_status "$RED" "   (based on extracted IP: $PRIVATE_IP and MINIO_API_PORT: $MINIO_API_PORT)"
        ((errors++))
    fi
    
    # Validate bucket name (basic S3 bucket naming rules)
    if [[ ! "$HA_AWS_S3_BUCKET" =~ ^[a-z0-9.-]+$ ]] || [[ ${#HA_AWS_S3_BUCKET} -lt 3 ]] || [[ ${#HA_AWS_S3_BUCKET} -gt 63 ]]; then
        print_status "$RED" "❌ HA_AWS_S3_BUCKET '$HA_AWS_S3_BUCKET' doesn't follow S3 naming conventions"
        print_status "$RED" "   Must be 3-63 chars, lowercase, numbers, dots, and hyphens only"
        ((errors++))
    fi
    
    return $errors
}

# Function to auto-fix HA_AWS_S3_SERVICE_ENDPOINT
fix_ha_endpoint() {
    local expected_endpoint="http://${PRIVATE_IP}:${MINIO_API_PORT}"
    
    print_status "$YELLOW" "🔧 Auto-fixing HA_AWS_S3_SERVICE_ENDPOINT..."
    
    # Update the .env file
    if command -v sed >/dev/null 2>&1; then
        # Use sed to replace the line
        sed -i.bak "s|^HA_AWS_S3_SERVICE_ENDPOINT=.*|HA_AWS_S3_SERVICE_ENDPOINT=${expected_endpoint}|" "$ENV_FILE"
        print_status "$GREEN" "✅ Updated HA_AWS_S3_SERVICE_ENDPOINT to: $expected_endpoint"
        print_status "$BLUE" "💾 Backup created: ${ENV_FILE}.bak"
    else
        print_status "$RED" "❌ sed command not available. Please manually update:"
        print_status "$YELLOW" "   HA_AWS_S3_SERVICE_ENDPOINT=$expected_endpoint"
        return 1
    fi
}

# Function to show current configuration
show_config() {
    # Extract IP from endpoint for display
    local extracted_ip=$(echo "$HA_AWS_S3_SERVICE_ENDPOINT" | sed -n 's|^http://\([^:]*\):.*|\1|p')
    
    print_status "$BLUE" "📋 Current Configuration:"
    echo "   HA_AWS_S3_SERVICE_ENDPOINT: $HA_AWS_S3_SERVICE_ENDPOINT"
    echo "   Extracted Private IP: $extracted_ip"
    echo "   MINIO_API_PORT: $MINIO_API_PORT"
    echo "   MINIO_CONSOLE_PORT: ${MINIO_CONSOLE_PORT:-9001}"
    echo "   HA_AWS_S3_BUCKET: $HA_AWS_S3_BUCKET"
    echo "   HA_AWS_ACCESS_KEY: $HA_AWS_ACCESS_KEY"
    echo "   HA_AWS_SECRET_KEY: [${#HA_AWS_SECRET_KEY} chars]"
    echo "   HA_RECORDING_STORAGE: ${HA_RECORDING_STORAGE:-not set}"
    echo "   CHUNK_TIME_SIZE: ${CHUNK_TIME_SIZE:-not set}"
}

# Main function
main() {
    print_status "$BLUE" "🚀 OpenVidu MinIO Environment Validator"
    echo
    
    # Load environment file
    load_env_file
    
    # Show current config
    show_config
    echo
    
    # Validate variables
    if validate_variables; then
        print_status "$GREEN" "✅ All environment variables are valid!"
        echo
        print_status "$GREEN" "🎉 You can now run docker-compose safely:"
        print_status "$BLUE" "   docker-compose up -d minio minio-setup"
        return 0
    else
        echo
        print_status "$YELLOW" "⚠️  Found configuration issues."
        
        # Check if we can auto-fix the HA endpoint
        local expected_endpoint="http://${PRIVATE_IP}:${MINIO_API_PORT}"
        if [ -n "$PRIVATE_IP" ] && [ -n "$MINIO_API_PORT" ] && [ "$HA_AWS_S3_SERVICE_ENDPOINT" != "$expected_endpoint" ]; then
            echo
            read -p "Would you like to auto-fix HA_AWS_S3_SERVICE_ENDPOINT? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if fix_ha_endpoint; then
                    print_status "$GREEN" "✅ Auto-fix completed. Please run the script again to validate."
                    return 0
                fi
            fi
        fi
        
        print_status "$RED" "❌ Please fix the issues above and run the script again."
        return 1
    fi
}

# Show usage if --help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [.env_file_path]"
    echo
    echo "Validates MinIO environment configuration for OpenVidu recording setup."
    echo
    echo "Arguments:"
    echo "  .env_file_path    Path to .env file (default: .env)"
    echo
    echo "Examples:"
    echo "  $0                    # Validate default .env file"
    echo "  $0 production.env     # Validate production.env file"
    echo
    echo "If .env file doesn't exist, the script will show the required format and exit."
    exit 0
fi

# Run main function
main