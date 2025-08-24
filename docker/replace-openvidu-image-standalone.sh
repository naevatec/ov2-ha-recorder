#!/bin/bash

# Standalone script to replace OpenVidu recording image with custom NaevaTec version
# Usage: ./replace-openvidu-image-standalone.sh <IMAGE_TAG>

set -e

# Check if IMAGE_TAG is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <IMAGE_TAG>"
    echo "Example: $0 2.29.0"
    exit 1
fi

IMAGE_TAG="$1"
IMAGE_NAME="openvidu/openvidu-recording"
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
OLD_MAINTAINER="OpenVidu info@openvidu.io"
NEW_MAINTAINER="NaevaTec-OpenVidu eiglesia@openvidu.io"

echo "🎬 Starting OpenVidu image replacement process for tag: ${IMAGE_TAG}"
echo "📁 Working directory: $(pwd)"

# Function to check if image exists with specific maintainer label
check_and_remove_old_image() {
    echo "🔍 Checking for existing image: ${FULL_IMAGE_NAME}"

    # Check if image exists
    if docker images "${FULL_IMAGE_NAME}" --format "table {{.Repository}}:{{.Tag}}" | grep -q "${FULL_IMAGE_NAME}"; then
        echo "📦 Image ${FULL_IMAGE_NAME} found"

        # Check maintainer label
        MAINTAINER=$(docker inspect "${FULL_IMAGE_NAME}" --format='{{index .Config.Labels "maintainer"}}' 2>/dev/null || echo "")

        if [ "$MAINTAINER" = "$OLD_MAINTAINER" ]; then
            echo "🗑️ Found image with old maintainer label: $MAINTAINER"
            echo "🗑️ Removing old image..."
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

# Function to build new image using docker-compose (matches your project structure)
build_new_image() {
    echo "🔨 Building new image: ${FULL_IMAGE_NAME}"

    # Check if docker-compose.yml exists
    if [ ! -f "docker-compose.yml" ]; then
        echo "❌ docker-compose.yml not found in current directory"
        echo "   Make sure you're running this script from the docker/ directory"
        exit 1
    fi

    # Check if recorder/Dockerfile exists
    if [ ! -f "recorder/Dockerfile" ]; then
        echo "❌ recorder/Dockerfile not found"
        echo "   Expected structure:"
        echo "   docker/"
        echo "   ├── docker-compose.yml"
        echo "   ├── recorder/"
        echo "   │   └── Dockerfile"
        echo "   └── replace-openvidu-image-standalone.sh"
        exit 1
    fi

    # Export IMAGE_TAG for docker compose
    export IMAGE_TAG="$TAG"

    # Build the image using docker-compose (matches your working script)
    echo "🐳 Building with docker-compose..."
    docker compose build openvidu-recording

    # Verify the new image has correct label
    NEW_MAINTAINER_CHECK=$(docker inspect "${FULL_IMAGE_NAME}" --format='{{index .Config.Labels "maintainer"}}' 2>/dev/null || echo "")

    if [ "$NEW_MAINTAINER_CHECK" = "$NEW_MAINTAINER" ]; then
        echo "✅ New image built successfully with correct maintainer label: $NEW_MAINTAINER_CHECK"
    else
        echo "❌ Error: New image has incorrect maintainer label: $NEW_MAINTAINER_CHECK"
        echo "   Expected: $NEW_MAINTAINER"
        echo "   Got: $NEW_MAINTAINER_CHECK"
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

# Function to check project structure
check_project_structure() {
    echo "🔍 Checking project structure..."

    # Required files/directories
    required_items=(
        "docker-compose.yml"
        "recorder/"
        "recorder/Dockerfile"
    )

    missing_items=()

    for item in "${required_items[@]}"; do
        if [ ! -e "$item" ]; then
            missing_items+=("$item")
        fi
    done

    if [ ${#missing_items[@]} -gt 0 ]; then
        echo "❌ Missing required project files/directories:"
        for item in "${missing_items[@]}"; do
            echo "   - $item"
        done
        echo ""
        echo "Expected project structure:"
        echo "docker/"
        echo "├── docker-compose.yml"
        echo "├── recorder/"
        echo "│   ├── Dockerfile"
        echo "│   ├── scripts/"
        echo "│   └── utils/"
        echo "├── server/"
        echo "└── replace-openvidu-image-standalone.sh"
        exit 1
    fi

    echo "✅ Project structure is valid"
}

# Main execution flow
main() {
    echo "📁 Working directory: $(pwd)"

    # Step 1: Check project structure
    check_project_structure

    # Step 2: Check and remove old image
    check_and_remove_old_image

    # Step 3: Build new image using docker-compose
    build_new_image

    # Step 4: Show final status
    show_image_details

    echo ""
    echo "🎉 Process completed successfully!"
    echo "💡 Your new image ${FULL_IMAGE_NAME} is ready to use"
    echo ""
    echo "🚀 To start the full environment, use:"
    echo "   ./replace-openvidu-image.sh ${IMAGE_TAG}"
}

# Execute main function
main

echo ""
echo "🔍 Additional verification commands:"
echo "   docker inspect ${FULL_IMAGE_NAME} --format='{{json .Config.Labels}}' | jq"
echo "   docker run --rm ${FULL_IMAGE_NAME} --version"
echo "   docker compose up -d  # To start with this image"
