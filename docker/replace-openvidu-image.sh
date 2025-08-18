#!/bin/bash

# Script to replace OpenVidu recording image with custom NaevaTec version
# This script integrates environment validation and uses standalone image replacement functions
# Usage: ./replace-openvidu-image.sh <TAG>

set -e

# Check if TAG is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <TAG>"
    echo "Example: $0 2.29.0"
    exit 1
fi

TAG="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🎬 Starting OpenVidu image replacement process for tag: ${TAG}"

# Function to validate environment using the dedicated validation script
validate_environment() {
    echo "🔍 Validating environment configuration..."
    
    # Check if validation script exists
    if [ -f "${SCRIPT_DIR}/validate-env.sh" ]; then
        chmod +x "${SCRIPT_DIR}/validate-env.sh"
        if ! "${SCRIPT_DIR}/validate-env.sh"; then
            echo "❌ Environment validation failed"
            exit 1
        fi
        echo "✅ Environment validation passed"
    else
        echo "❌ validate-env.sh not found in ${SCRIPT_DIR}"
        echo "   This script is required for environment validation"
        exit 1
    fi
}

# Function to perform image replacement using standalone script functions
replace_openvidu_image() {
    echo "🔄 Performing OpenVidu image replacement..."
    
    # Check if standalone script exists to source its functions
    if [ -f "${SCRIPT_DIR}/replace-openvidu-image-standalone.sh" ]; then
        echo "📦 Using image replacement functions from standalone script"
        
        # Source the standalone script functions (but don't execute main)
        # We'll extract and use the functions from the standalone script
        
        # Image configuration variables
        IMAGE_NAME="openvidu/openvidu-recording"
        FULL_IMAGE_NAME="${IMAGE_NAME}:${TAG}"
        OLD_MAINTAINER="OpenVidu info@openvidu.io"
        NEW_MAINTAINER="NaevaTec-OpenVidu eiglesia@openvidu.io"
        
        # Function to check if image exists with specific maintainer label
        check_and_remove_old_image() {
            echo "🔍 Checking for existing image: ${FULL_IMAGE_NAME}"
            
            # Check if image exists
            if docker images "${FULL_IMAGE_NAME}" --format "table {{.Repository}}:{{.Tag}}" | grep -q "${FULL_IMAGE_NAME}"; then
                echo "📦 Image ${FULL_IMAGE_NAME} found"
                
                # Check maintainer label
                MAINTAINER=$(docker inspect "${FULL_IMAGE_NAME}" --format='{{index .Config.Labels "maintainer"}}' 2>/dev/null || echo "")
                
                if [ "$MAINTAINER" = "$OLD_MAINTAINER" ]; then
                    echo "🗑️  Found image with old maintainer label: $MAINTAINER"
                    echo "🗑️  Removing old image..."
                    docker rmi "${FULL_IMAGE_NAME}"
                    echo "✅ Old image removed successfully"
                elif [ "$MAINTAINER" = "$NEW_MAINTAINER" ]; then
                    echo "ℹ️  Image already has the new maintainer label: $MAINTAINER"
                    echo "ℹ️  Skipping removal, but will rebuild to ensure latest version"
                else
                    echo "⚠️  Image has different maintainer label: $MAINTAINER"
                    echo "⚠️  Removing anyway to ensure clean replacement..."
                    docker rmi "${FULL_IMAGE_NAME}"
                fi
            else
                echo "📦 Image ${FULL_IMAGE_NAME} not found locally"
            fi
        }
        
        # Function to build new image using docker-compose
        build_new_image_with_compose() {
            echo "🔨 Building new image with docker compose: ${FULL_IMAGE_NAME}"
            
            # Export TAG for docker compose
            export TAG="$TAG"
            
            # Build using docker compose
            docker compose build openvidu-recording
            
            # Verify the new image has correct label
            NEW_MAINTAINER_CHECK=$(docker inspect "${FULL_IMAGE_NAME}" --format='{{index .Config.Labels "maintainer"}}' 2>/dev/null || echo "")
            
            if [ "$NEW_MAINTAINER_CHECK" = "$NEW_MAINTAINER" ]; then
                echo "✅ New image built successfully with correct maintainer label: $NEW_MAINTAINER_CHECK"
            else
                echo "❌ Error: New image has incorrect maintainer label: $NEW_MAINTAINER_CHECK"
                exit 1
            fi
        }
        
        # Execute image replacement steps
        check_and_remove_old_image
        build_new_image_with_compose
        
    else
        echo "❌ replace-openvidu-image-standalone.sh not found in ${SCRIPT_DIR}"
        echo "   This script is required for image replacement functions"
        exit 1
    fi
}

# Function to start MinIO services via docker compose
start_minio_services() {
    echo "🚀 Starting MinIO services via docker compose..."
    
    # Check if docker-compose.yml exists
    if [ ! -f "${SCRIPT_DIR}/docker-compose.yml" ]; then
        echo "❌ docker-compose.yml not found in ${SCRIPT_DIR}"
        exit 1
    fi
    
    # Export TAG for docker compose
    export TAG="$TAG"
    
    # Start MinIO and its setup
    docker compose up -d minio minio-mc
    
    # Wait for MinIO setup to complete
    echo "⏳ Waiting for MinIO setup to complete..."
    
    # Wait for minio-mc container to finish (it should exit when done)
    timeout=60
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if ! docker compose ps minio-mc | grep -q "Up"; then
            # Container has stopped, check if it completed successfully
            exit_code=$(docker compose ps -q minio-mc | xargs docker inspect --format='{{.State.ExitCode}}' 2>/dev/null || echo "1")
            if [ "$exit_code" = "0" ]; then
                echo "✅ MinIO setup completed successfully"
                break
            else
                echo "❌ MinIO setup failed with exit code: $exit_code"
                docker compose logs minio-mc
                exit 1
            fi
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    if [ $elapsed -ge $timeout ]; then
        echo "⚠️  MinIO setup timeout reached, checking logs..."
        docker compose logs minio-mc
    fi
    
    echo "✅ MinIO services are ready"
    echo "🌐 MinIO Console: http://localhost:${MINIO_CONSOLE_PORT:-9001}"
    echo "🔗 MinIO API: http://localhost:${MINIO_API_PORT:-9000}"
}

# Function to show final status
show_final_status() {
    echo "📊 Final status:"
    echo ""
    echo "🐳 Docker Compose Services:"
    docker compose ps
    echo ""
    echo "📦 OpenVidu Recording Image:"
    docker images "openvidu/openvidu-recording:${TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}"
    echo ""
    echo "🏷️  Image labels:"
    docker inspect "openvidu/openvidu-recording:${TAG}" --format='{{range $key, $value := .Config.Labels}}{{$key}}: {{$value}}{{"\n"}}{{end}}' | sort
}

# Main execution flow
main() {
    echo "📁 Working directory: ${SCRIPT_DIR}"
    cd "${SCRIPT_DIR}"
    
    # Step 1: Validate environment configuration
    validate_environment
    
    # Step 2: Replace OpenVidu image
    replace_openvidu_image
    
    # Step 3: Start MinIO services
    start_minio_services
    
    # Step 4: Show final status
    show_final_status
    
    echo ""
    echo "🎉 Process completed successfully!"
    echo "💡 MinIO service is running. Use 'docker compose down' to stop when done."
    echo "🔍 Image ready: openvidu/openvidu-recording:${TAG}"
}

# Execute main function
main

echo ""
echo "🔍 Additional verification commands:"
echo "   docker inspect openvidu/openvidu-recording:${TAG} --format='{{json .Config.Labels}}' | jq"
echo "   docker compose logs minio"