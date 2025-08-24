#!/bin/bash

# Script to replace OpenVidu recording image with custom NaevaTec version
# This script integrates environment validation and HA Controller management
# Usage: ./replace-openvidu-image.sh <IMAGE_TAG>

set -e

# Check if IMAGE_TAG is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <IMAGE_TAG>"
    echo "Example: $0 2.29.0"
    exit 1
fi

IMAGE_TAG="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🎬 Starting OpenVidu image replacement process for tag: ${IMAGE_TAG}"
echo "📡 HA Controller integration: ENABLED (always included)"

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
        echo "⚠️ validate-env.sh not found in ${SCRIPT_DIR}"
        echo "   This script is required for environment validation"
        exit 1
    fi
}

# Function to create required directories
create_directories() {
    echo "📁 Creating required directories..."
    
    # Create data directories
    mkdir -p data/minio/data
    mkdir -p data/recorder/data
    mkdir -p data/redis/data
    mkdir -p data/controller/logs
    
    # Create server directory structure
    mkdir -p server
    
    # Create recorder directory structure
    mkdir -p recorder/scripts
    mkdir -p recorder/utils
    
    echo "✅ Directories created successfully"
}

# Function to perform image replacement using standalone script functions
replace_openvidu_image() {
    echo "🔄 Performing OpenVidu image replacement..."
    
    # Image configuration variables
    IMAGE_NAME="openvidu/openvidu-recording"
    FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
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
                echo "🗑️ Found image with old maintainer label: $MAINTAINER"
                echo "🗑️ Removing old image..."
                docker rmi "${FULL_IMAGE_NAME}"
                echo "✅ Old image removed successfully"
            elif [ "$MAINTAINER" = "$NEW_MAINTAINER" ]; then
                echo "ℹ️ Image already has the new maintainer label: $MAINTAINER"
                echo "ℹ️ Skipping removal, but will rebuild to ensure latest version"
            else
                echo "⚠️ Image has different maintainer label: $MAINTAINER"
                echo "⚠️ Removing anyway to ensure clean replacement..."
                docker rmi "${FULL_IMAGE_NAME}"
            fi
        else
            echo "📦 Image ${FULL_IMAGE_NAME} not found locally"
        fi
    }
    
    # Function to build new image using docker-compose
    build_new_image_with_compose() {
        echo "🔨 Building new image with docker compose: ${FULL_IMAGE_NAME}"
        
        # Export IMAGE_TAG for docker compose
        export IMAGE_TAG="$TAG"
        
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
}

# Function to build HA Controller
build_ha_controller() {
    echo "🔨 Building HA Controller..."
    
    # Check if server/Dockerfile exists
    if [ ! -f "server/Dockerfile" ]; then
        echo "❌ server/Dockerfile not found. Please ensure HA Controller is properly set up."
        exit 1
    fi
    
    # Build HA Controller
    docker compose build ov-recorder-ha-controller
    echo "✅ HA Controller built successfully"
}

# Function to check Docker container health status
check_container_health() {
    local container_name="$1"
    local timeout="${2:-60}"
    local description="${3:-container}"

    echo "🏥 Checking $description health using Docker inspect..."

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        # Check if container exists and is running
        if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            # Check health status if healthcheck is defined
            health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "no-healthcheck")

            if [ "$health_status" = "healthy" ]; then
                echo "✅ $description is healthy"
                return 0
            elif [ "$health_status" = "no-healthcheck" ]; then
                # If no healthcheck defined, just check if running
                container_status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null || echo "not-found")
                if [ "$container_status" = "running" ]; then
                    echo "✅ $description is running (no healthcheck defined)"
                    return 0
                fi
            fi
        fi

        echo -n "."
        sleep 3
        elapsed=$((elapsed + 3))
    done

    echo ""
    echo "⚠️ $description health check timeout after ${timeout}s"
    return 1
}

# Function to start services via docker compose
start_services() {
    echo "🚀 Starting services via docker compose..."

    # Check if docker-compose.yml exists
    if [ ! -f "${SCRIPT_DIR}/docker-compose.yml" ]; then
        echo "❌ docker-compose.yml not found in ${SCRIPT_DIR}"
        exit 1
    fi

    # Export IMAGE_TAG for docker compose
    export IMAGE_TAG="$TAG"

    # Get the docker compose project name for network reference
    PROJECT_NAME=$(basename "${SCRIPT_DIR}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
    if [ -z "$PROJECT_NAME" ]; then
        PROJECT_NAME="recorder-ha-controller"
    fi

    # Start MinIO services first
    echo "📦 Starting MinIO and setup containers..."
    docker compose up -d minio minio-mc

    # Wait for MinIO setup to complete
    echo "⏳ Waiting for MinIO setup to complete..."
    timeout=120
    elapsed=0
    setup_completed=false

    while [ $elapsed -lt $timeout ]; do
        if mc_status=$(docker compose ps -a minio-mc --format "{{.State}}" 2>/dev/null); then
            case "$mc_status" in
                "running")
                    echo "⏳ MinIO setup still running... (${elapsed}s elapsed)"
                    ;;
                "exited")
                    exit_code=$(docker compose ps -a minio-mc --format "{{.ExitCode}}" 2>/dev/null || echo "1")
                    if [ "$exit_code" = "0" ]; then
                        echo "✅ MinIO setup completed successfully"
                        setup_completed=true
                        break
                    else
                        echo "❌ MinIO setup failed with exit code: $exit_code"
                        echo "📋 MinIO setup logs:"
                        docker compose logs minio-mc
                        exit 1
                    fi
                    ;;
                *)
                    echo "⚠️ MinIO setup container in unexpected state: $mc_status"
                    ;;
            esac
        else
            echo "⚠️ Cannot get minio-mc container status"
        fi

        sleep 3
        elapsed=$((elapsed + 3))
    done

    if [ "$setup_completed" = false ]; then
        echo "⚠️ MinIO setup timeout reached (${timeout}s), checking final status..."
        echo "📋 MinIO setup logs:"
        docker compose logs minio-mc

        final_exit_code=$(docker compose ps -a minio-mc --format "{{.ExitCode}}" 2>/dev/null || echo "1")
        if [ "$final_exit_code" = "0" ]; then
            echo "✅ MinIO setup completed successfully (detected after timeout)"
        else
            echo "❌ MinIO setup failed or timed out"
            exit 1
        fi
    fi

    # Start Redis
    echo "📦 Starting Redis..."
    docker compose up -d redis

    # Verify MinIO is healthy using container health status
    echo "🏥 Checking MinIO health using container status..."
    if check_container_health "minio" 30 "MinIO"; then
        echo "✅ MinIO services are ready"
    else
        echo "⚠️ MinIO health check failed, but continuing..."
        # Check if MinIO is at least running
        if docker ps --format "{{.Names}}" | grep -q "^minio$"; then
            echo "📦 MinIO container is running"
        else
            echo "❌ MinIO container is not running"
            docker compose logs minio
        fi
    fi

    # Get MinIO port information for display
    minio_console_port="${MINIO_CONSOLE_PORT:-9001}"
    minio_api_port="${MINIO_API_PORT:-9000}"

    echo "🌐 MinIO Console: http://localhost:${minio_console_port}"
    echo "🔗 MinIO API: http://localhost:${minio_api_port}"
}

# Function to start HA Controller
start_ha_controller() {
    echo "🚀 Starting HA Controller..."

    # Start with ha-controller profile
    docker compose --profile ha-controller up -d ov-recorder-ha-controller

    # Wait for HA Controller to be ready using container health status
    echo "⏳ Waiting for HA Controller to be ready..."
    if check_container_health "ov-recorder-ha-controller" 90 "HA Controller"; then
        echo "✅ HA Controller is ready and running"

        # Additional verification: check if Spring Boot has started properly
        echo "🔍 Verifying Spring Boot application startup..."
        if docker logs ov-recorder-ha-controller 2>&1 | grep -q "Started.*Application in"; then
            echo "✅ Spring Boot application has started successfully"
        elif docker logs ov-recorder-ha-controller 2>&1 | grep -q "APPLICATION READY"; then
            echo "✅ HA Controller application is ready"
        else
            echo "⚠️ Spring Boot startup verification inconclusive, but container is healthy"
        fi

        return 0
    else
        echo "❌ HA Controller failed to start within timeout"
        echo "📋 Checking if container is at least running..."
        if docker ps --format "{{.Names}}" | grep -q "^ov-recorder-ha-controller$"; then
            echo "📦 HA Controller container is running but not healthy"
            echo "📋 Recent container logs:"
            docker compose logs --tail=20 ov-recorder-ha-controller
        else
            echo "❌ HA Controller container is not running"
            echo "📋 All logs:"
            docker compose logs ov-recorder-ha-controller
        fi
        exit 1
    fi
}

# Function to show final status
show_final_status() {
    echo "📊 Final status:"
    echo ""
    echo "🐳 Docker Compose Services:"
    docker compose ps
    echo ""
    echo "📦 OpenVidu Recording Image:"
    docker images "${IMAGE_NAME}:${IMAGE_TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}"
    echo ""
    echo "🏷️ Image labels:"
    docker inspect "${IMAGE_NAME}:${IMAGE_TAG}" --format='{{range $key, $value := .Config.Labels}}{{$key}}: {{$value}}{{"\n"}}{{end}}' | sort

    echo ""
    echo "📡 HA Controller Status:"
    ha_port="${HA_CONTROLLER_PORT:-8080}"
    echo "   • API: http://localhost:${ha_port}/api/sessions"
    echo "   • Health: http://localhost:${ha_port}/actuator/health"
    username="${HA_CONTROLLER_USERNAME:-recorder}"
    password="${HA_CONTROLLER_PASSWORD:-rec0rd3r_2024!}"
    echo "   • Auth: ${username} / [password hidden]"
    echo ""
    echo "📋 Quick Commands (adjust for remote context if needed):"
    echo "   • Health: curl -u ${username}:${password} http://localhost:${ha_port}/api/sessions/health"
    echo "   • Logs: docker compose logs ov-recorder-ha-controller"
    echo ""
    echo "🐳 Docker-based Commands (work with remote contexts):"
    echo "   • Container status: docker ps --filter name=ov-recorder-ha-controller"
    echo "   • Health check: docker inspect ov-recorder-ha-controller --format='{{.State.Health.Status}}'"
    echo "   • Container logs: docker logs ov-recorder-ha-controller"
    echo "   • Exec into container: docker exec -it ov-recorder-ha-controller sh"
}

# Main execution flow
main() {
    echo "📁 Working directory: ${SCRIPT_DIR}"
    cd "${SCRIPT_DIR}"

    # Step 1: Validate environment configuration
    validate_environment

    # Step 2: Create required directories
    create_directories

    # Step 3: Build HA Controller if requested
    build_ha_controller

    # Step 4: Replace OpenVidu image
    replace_openvidu_image

    # Step 5: Start MinIO services
    start_services

    # Step 6: Start HA Controller if requested
    start_ha_controller

    # Step 7: Show final status
    show_final_status

    echo ""
    echo "🎉 Process completed successfully!"
    echo "💡 Services are running. Use 'docker compose down' to stop when done."
    echo "📸 Image ready: ${IMAGE_NAME}:${IMAGE_TAG}"
    echo "📡 HA Controller ready: http://localhost:${HA_CONTROLLER_PORT:-8080}"
    echo ""
    echo "🔧 Note: Health checks now use Docker containers, compatible with remote contexts!"
}

# Execute main function
main

echo ""
echo "📋 Additional verification commands:"
echo "   docker inspect ${IMAGE_NAME}:${IMAGE_TAG} --format='{{json .Config.Labels}}' | jq"
echo "   docker compose logs minio"
echo "   docker compose logs ov-recorder-ha-controller"
echo ""
echo "🐳 Remote-context-friendly verification:"
echo "   docker ps --filter name=ov-recorder-ha-controller --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
echo "   docker inspect ov-recorder-ha-controller --format='{{.State.Health.Status}}'"
