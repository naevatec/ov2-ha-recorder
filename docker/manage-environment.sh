#!/bin/bash

# Development helper script for OpenVidu HA Recorder environment with HA Controller
# Complements the main replace-openvidu-image.sh workflow
# Usage: ./manage-environment.sh [command] [TAG]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TAG="${2:-2.31.0}"

# Load shared functions
if [ -f "${SCRIPT_DIR}/shared-functions.sh" ]; then
    source "${SCRIPT_DIR}/shared-functions.sh"
else
    echo "❌ Error: shared-functions.sh not found in ${SCRIPT_DIR}"
    echo "Please ensure all required files are present."
    exit 1
fi

show_usage() {
    echo "Usage: $0 [command] [TAG]"
    echo ""
    echo "Development helper commands:"
    echo "  start        - Start MinIO and HA Controller services"
    echo "  stop         - Stop all services"
    echo "  status       - Show status of services and images"
    echo "  logs         - Show logs from services"
    echo "  clean        - Stop services and remove volumes/images"
    echo "  test         - Test the OpenVidu recording container"
    echo "  test-recorder - Full S3 recording test (20 seconds)"
    echo "  test-ha      - Test HA Controller API"
    echo ""
    echo "TAG: Docker image tag to use (default: 2.31.0)"
    echo ""
    echo "Examples:"
    echo "  $0 start             # Start MinIO + HA Controller"
    echo "  $0 status            # Check what's running"
    echo "  $0 test-ha           # Test HA Controller API"
    echo "  $0 clean             # Clean everything"
    echo ""
    echo "Note: For full deployment workflow, use replace-openvidu-image.sh"
    echo "Note: HA Controller is always included in all operations"
}

start_environment() {
    print_header "OV Recorder Development Environment"
    print_info "Starting environment (TAG: $TAG)"
    print_info "HA Controller: ENABLED (always included)"
    
    validate_environment
    create_directories
    
    # Export TAG for docker-compose
    export TAG="$TAG"
    
    # Start MinIO services
    start_minio_services
    
    # Start HA Controller
    start_ha_controller
    
    print_success "Environment is ready"
    print_info "To build and deploy the OpenVidu image, run:"
    print_info "   ./replace-openvidu-image.sh $TAG"
}

stop_environment() {
    print_step "Stopping all services..."
    docker compose down
    print_success "All services stopped"
}

show_status() {
    print_step "Environment Status"
    
    echo ""
    print_info "Docker Compose Services:"
    if docker compose ps 2>/dev/null | grep -q "openvidu\|minio\|redis\|ov-recorder"; then
        docker compose ps
    else
        echo "   No services running"
    fi
    
    echo ""
    print_info "OpenVidu Recording Images:"
    if docker images "openvidu/openvidu-recording" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}" | tail -n +2 | grep -q "openvidu"; then
        docker images "openvidu/openvidu-recording" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}"
    else
        echo "   No OpenVidu recording images found"
    fi
    
    echo ""
    print_info "HA Controller Images:"
    if docker images | grep -q "ov-recorder-ha-controller"; then
        docker images | grep "ov-recorder-ha-controller" | head -5
    else
        echo "   No HA Controller images found"
    fi
    
    echo ""
    print_info "Environment Variables Status:"
    if [ -f ".env" ]; then
        echo "   ✅ .env file exists"
        if command -v grep >/dev/null 2>&1; then
            echo "   TAG: $(grep '^TAG=' .env 2>/dev/null | cut -d'=' -f2 || echo 'not set')"
            echo "   HA_AWS_S3_SERVICE_ENDPOINT: $(grep '^HA_AWS_S3_SERVICE_ENDPOINT=' .env 2>/dev/null | cut -d'=' -f2 || echo 'not set')"
            echo "   HA_CONTROLLER_PORT: $(grep '^HA_CONTROLLER_PORT=' .env 2>/dev/null | cut -d'=' -f2 || echo 'not set')"
            echo "   MINIO_API_PORT: $(grep '^MINIO_API_PORT=' .env 2>/dev/null | cut -d'=' -f2 || echo 'not set')"
        fi
    else
        echo "   ❌ .env file not found"
    fi
    
    # Check if HA Controller is running
    if docker compose ps ov-recorder-ha-controller 2>/dev/null | grep -q "Up"; then
        ha_port="${HA_CONTROLLER_PORT:-8080}"
        echo ""
        print_info "HA Controller Status: RUNNING"
        echo "   API: http://localhost:${ha_port}/api/sessions"
        if curl -s -f "http://localhost:${ha_port}/actuator/health" >/dev/null 2>&1; then
            echo "   Health: ✅ HEALTHY"
        else
            echo "   Health: ❌ UNHEALTHY"
        fi
    else
        echo ""
        print_info "HA Controller Status: NOT RUNNING"
    fi
}

show_logs() {
    print_step "Service Logs"
    
    echo ""
    if docker compose ps 2>/dev/null | grep -q "minio"; then
        echo "=== MinIO Server Logs ==="
        docker compose logs --tail=20 minio
        echo ""
        echo "=== MinIO Setup Logs ==="
        docker compose logs --tail=10 minio-mc
        echo ""
    fi
    
    if docker compose ps 2>/dev/null | grep -q "ov-recorder-ha-controller"; then
        echo "=== HA Controller Logs ==="
        docker compose logs --tail=30 ov-recorder-ha-controller
        echo ""
    fi
    
    if docker compose ps 2>/dev/null | grep -q "redis"; then
        echo "=== Redis Logs ==="
        docker compose logs --tail=10 redis
        echo ""
    fi
    
    if docker compose ps 2>/dev/null | grep -q "openvidu-recording"; then
        echo "=== OpenVidu Recording Logs ==="
        docker compose logs --tail=20 openvidu-recording
    fi
    
    if ! docker compose ps 2>/dev/null | grep -q -E "minio|redis|ov-recorder|openvidu"; then
        echo "No services running. Start them with: $0 start"
    fi
}

clean_environment() {
    print_step "Cleaning development environment..."
    
    # Stop and remove containers, networks, and volumes
    docker compose down -v --remove-orphans
    
    # Remove OpenVidu recording images for the specified tag
    IMAGE_NAME="openvidu/openvidu-recording:$TAG"
    if docker images "$IMAGE_NAME" --format "{{.Repository}}:{{.Tag}}" | grep -q "$IMAGE_NAME"; then
        print_info "Removing image: $IMAGE_NAME"
        docker rmi "$IMAGE_NAME" || true
    fi
    
    # Remove HA Controller images
    HA_IMAGES=$(docker images | grep "ov-recorder-ha-controller" | awk '{print $3}' || true)
    if [ -n "$HA_IMAGES" ]; then
        print_info "Removing HA Controller images..."
        echo "$HA_IMAGES" | xargs docker rmi || true
    fi
    
    # Clean up dangling images
    if [ "$(docker images -f "dangling=true" -q)" ]; then
        print_info "Removing dangling images..."
        docker image prune -f
    fi
    
    print_success "Environment cleaned"
    print_info "To rebuild everything, run: ./replace-openvidu-image.sh $TAG"
}

test_container() {
    print_step "Testing OpenVidu recording container (TAG: $TAG)..."
    
    IMAGE_NAME="openvidu/openvidu-recording:$TAG"
    
    # Check if image exists
    if ! docker images "$IMAGE_NAME" --format "{{.Repository}}:{{.Tag}}" | grep -q "$IMAGE_NAME"; then
        print_error "Image $IMAGE_NAME not found"
        print_info "Build it first with: ./replace-openvidu-image.sh $TAG"
        exit 1
    fi
    
    # Export TAG for docker compose
    export TAG="$TAG"
    
    print_info "Testing container basic functionality..."
    docker compose run --rm openvidu-recording /bin/bash -c "
        echo '=== Testing System Components ===';
        echo 'Chrome version:';
        google-chrome --version 2>/dev/null || echo 'Chrome not found';
        echo '';
        echo 'FFmpeg version:';
        ffmpeg -version 2>/dev/null | head -n 1 || echo 'FFmpeg not found';
        echo '';
        echo 'Testing xvfb-run-safe:';
        which xvfb-run-safe || echo 'xvfb-run-safe not found';
        echo '';
        echo 'Testing recordings directory:';
        ls -la /recordings 2>/dev/null || echo 'Recordings directory not accessible';
        echo '';
        echo 'Environment variables:';
        echo \"HA_AWS_S3_SERVICE_ENDPOINT: \$HA_AWS_S3_SERVICE_ENDPOINT\";
        echo \"HA_AWS_S3_BUCKET: \$HA_AWS_S3_BUCKET\";
        echo \"MINIO_API_PORT: \$MINIO_API_PORT\";
        echo \"HA_CONTROLLER_URL: \$HA_CONTROLLER_URL\";
        echo '';
        echo '=== Test Completed ===';
    "
    
    if [ $? -eq 0 ]; then
        print_success "Container test passed successfully"
    else
        print_error "Container test failed"
        exit 1
    fi
}

test_recorder() {
    print_step "Full S3 Recording Test (TAG: $TAG)"
    echo "This will test a complete 20-second recording workflow with S3 storage"
    echo ""
    
    # Validate environment first
    validate_environment
    
    IMAGE_NAME="openvidu/openvidu-recording:$TAG"
    
    # Check if image exists
    if ! docker images "$IMAGE_NAME" --format "{{.Repository}}:{{.Tag}}" | grep -q "$IMAGE_NAME"; then
        print_error "Image $IMAGE_NAME not found"
        print_info "Build it first with: ./replace-openvidu-image.sh $TAG"
        exit 1
    fi
    
    # Ensure MinIO is running
    if ! docker compose ps minio | grep -q "Up"; then
        print_info "Starting MinIO services first..."
        start_environment
    fi
    
    # Export environment for docker compose
    export TAG="$TAG"
    export HA_RECORDING_STORAGE="s3"
    
    print_info "Starting recording test with S3 storage..."
    print_info "Creating local directories..."
    mkdir -p ./data/recorder/data
    
    # Start recorder with test profile
    docker compose --profile test up -d openvidu-recording
    
    # Wait for container to be ready
    print_info "Waiting for recorder to initialize..."
    sleep 5
    
    # Check if container is running
    if ! docker compose ps openvidu-recording | grep -q "Up"; then
        print_error "Recorder failed to start"
        docker compose logs openvidu-recording
        exit 1
    fi
    
    print_success "Recorder container is running"
    print_info "Container logs (last 10 lines):"
    docker compose logs --tail=10 openvidu-recording
    
    echo ""
    print_info "Test Summary:"
    echo "   - MinIO is accessible at: http://localhost:${MINIO_CONSOLE_PORT:-9001}"
    echo "   - Bucket: ${HA_AWS_S3_BUCKET:-ov-recordings}"
    echo "   - Local recordings: ./data/recorder/data"
    echo "   - S3 Storage mode: ENABLED"
    echo ""
    print_info "Check MinIO console to verify S3 connectivity works"
    print_info "Use 'docker compose logs openvidu-recording' for detailed logs"
    echo ""
    print_info "To stop the test:"
    echo "   docker compose --profile test down"
}

# Main execution
case "${1:-}" in
    start)
        start_environment
        ;;
    stop)
        stop_environment
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    clean)
        clean_environment
        ;;
    test)
        test_container
        ;;
    test-ha)
        test_ha_controller_api
        ;;
    test-recorder)
        test_recorder
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
