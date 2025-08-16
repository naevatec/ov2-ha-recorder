#!/bin/bash

# Standalone script to replace OpenVidu recording image with custom NaevaTec version
# Usage: ./replace-openvidu-image-standalone.sh <TAG>

set -e

# Check if TAG is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <TAG>"
    echo "Example: $0 2.29.0"
    exit 1
fi

TAG="$1"
IMAGE_NAME="openvidu/openvidu-recording"
FULL_IMAGE_NAME="${IMAGE_NAME}:${TAG}"
OLD_MAINTAINER="OpenVidu info@openvidu.io"
NEW_MAINTAINER="NaevaTec-OpenVidu eiglesia@openvidu.io"

echo "🔍 Checking for existing image: ${FULL_IMAGE_NAME}"

# Function to check if image exists with specific maintainer label
check_and_remove_old_image() {
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

# Function to build new image
build_new_image() {
    echo "🔨 Building new image: ${FULL_IMAGE_NAME}"
    
    # Check if Dockerfile exists
    if [ ! -f "Dockerfile" ]; then
        echo "❌ Dockerfile not found in current directory"
        exit 1
    fi
    
    # Build the image directly with docker build
    docker build -t "${FULL_IMAGE_NAME}" .
    
    # Verify the new image has correct label
    NEW_MAINTAINER_CHECK=$(docker inspect "${FULL_IMAGE_NAME}" --format='{{index .Config.Labels "maintainer"}}' 2>/dev/null || echo "")
    
    if [ "$NEW_MAINTAINER_CHECK" = "$NEW_MAINTAINER" ]; then
        echo "✅ New image built successfully with correct maintainer label: $NEW_MAINTAINER_CHECK"
    else
        echo "❌ Error: New image has incorrect maintainer label: $NEW_MAINTAINER_CHECK"
        exit 1
    fi
}

# Function to show image details
show_image_details() {
    echo "📊 Image information:"
    docker images "${FULL_IMAGE_NAME}" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}"
    
    echo ""
    echo "🏷️  Image labels:"
    docker inspect "${FULL_IMAGE_NAME}" --format='{{range $key, $value := .Config.Labels}}{{$key}}: {{$value}}{{"\n"}}{{end}}' | sort
}

# Main execution flow
main() {
    echo "🎬 Starting OpenVidu image replacement process for tag: ${TAG}"
    echo "📁 Working directory: $(pwd)"
    
    # Step 1: Check and remove old image
    check_and_remove_old_image
    
    # Step 2: Build new image
    build_new_image
    
    # Step 3: Show final status
    show_image_details
    
    echo ""
    echo "🎉 Process completed successfully!"
    echo "💡 Your new image ${FULL_IMAGE_NAME} is ready to use"
}

# Execute main function
main

echo ""
echo "🔍 Additional verification commands:"
echo "   docker inspect ${FULL_IMAGE_NAME} --format='{{json .Config.Labels}}' | jq"
echo "   docker run --rm ${FULL_IMAGE_NAME} --version"