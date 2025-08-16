#!/bin/bash

# Development helper script for OpenVidu HA Recorder environment
# Complements the main replace-openvidu-image.sh workflow
# Usage: ./manage-environment.sh [start|stop|status|logs|clean|test] [TAG]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TAG="${2:-2.31.0}"

show_usage() {
    echo "Usage: $0 [start|stop|status|logs|clean|test] [TAG]"
    echo ""
    echo "Development helper commands:"
    echo "  start   - Start only MinIO services (no image building)"
    echo "  stop    - Stop all services"
    echo "  status  - Show status of services and images"
    echo "  logs    - Show logs from MinIO services"
    echo "  clean   - Stop services and remove volumes/images"
    echo "  test    - Test the OpenVidu recording container"
    echo ""
    echo "TAG: Docker image tag to use (default: 2.31.0)"
    echo ""
    echo "Examples:"
    echo "  $0 start           # Start MinIO with default tag"
    echo "  $0 status          # Check what's running"
    echo "  $0 test 2.31.0     # Test container functionality"
    echo "  $0 clean           # Clean everything"
    echo ""
    echo "Note: For full deployment workflow, use replace-openvidu-image.sh"
}

validate_environment() {
    echo "🔍 Validating environment..."
    if [ -f "validate-env.sh" ]; then
        chmod +x validate-env.sh
        if ! ./validate-env.sh; then
            echo "❌ Environment validation failed"
            echo "💡 Please fix environment issues before proceeding"
            exit 1
        fi
    else
        echo "⚠️  validate-env.sh not found, skipping validation"
    fi
}

start_environment() {
    echo "🚀 Starting MinIO services only (TAG: $TAG)"
    
    validate_environment
    
    # Export TAG for docker-compose
    export TAG="$TAG"
    
    # Start only MinIO services
    echo "📦 Starting MinIO and setup..."
    docker-compose up -d minio minio-mc
    
    # Wait for MinIO setup to complete
    echo "⏳ Waiting for MinIO setup to complete..."
    timeout=60
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if ! docker-compose ps minio-mc | grep -q "Up"; then
            exit_code=$(docker-compose ps -q minio-mc | xargs docker inspect --format='{{.State.ExitCode}}' 2>/dev/null || echo "1")
            if [ "$exit_code" = "0" ]; then
                echo "✅ MinIO setup completed successfully"
                break
            else
                echo "❌ MinIO setup failed"
                docker-compose logs minio-mc
                exit 1
            fi
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    echo "✅ MinIO environment is ready"
    echo "🌐 MinIO Console: http://localhost:${MINIO_CONSOLE_PORT:-9001}"
    echo "🔗 MinIO API: http://localhost:${MINIO_API_PORT:-9000}"
    echo ""
    echo "💡 To build and deploy the OpenVidu image, run:"
    echo "   ./replace-openvidu-image.sh $TAG"
}

stop_environment() {
    echo "🛑 Stopping all services..."
    docker-compose down
    echo "✅ All services stopped"
}

show_status() {
    echo "📊 Environment Status:"
    echo ""
    echo "🐳 Docker Compose Services:"
    if docker-compose ps 2>/dev/null | grep -q "openvidu"; then
        docker-compose ps
    else
        echo "   No services running"
    fi
    
    echo ""
    echo "📦 OpenVidu Recording Images:"
    if docker images "openvidu/openvidu-recording" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}" | tail -n +2 | grep -q "openvidu"; then
        docker images "openvidu/openvidu-recording" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}"
    else
        echo "   No OpenVidu recording images found"
    fi
    
    echo ""
    echo "🏷️  Environment Variables Status:"
    if [ -f ".env" ]; then
        echo "   ✅ .env file exists"
        if command -v grep >/dev/null 2>&1; then
            echo "   TAG: $(grep '^TAG=' .env 2>/dev/null | cut -d'=' -f2 || echo 'not set')"
            echo "   HA_AWS_S3_SERVICE_ENDPOINT: $(grep '^HA_AWS_S3_SERVICE_ENDPOINT=' .env 2>/dev/null | cut -d'=' -f2 || echo 'not set')"
            echo "   MINIO_API_PORT: $(grep '^MINIO_API_PORT=' .env 2>/dev/null | cut -d'=' -f2 || echo 'not set')"
        fi
    else
        echo "   ❌ .env file not found"
    fi
}

show_logs() {
    echo "📋 MinIO Service Logs:"
    echo ""
    if docker-compose ps 2>/dev/null | grep -q "minio"; then
        echo "=== MinIO Server Logs ==="
        docker-compose logs --tail=50 minio
        echo ""
        echo "=== MinIO Setup Logs ==="
        docker-compose logs --tail=20 minio-mc
    else
        echo "No MinIO services running. Start them with: $0 start"
    fi
}

clean_environment() {
    echo "🧹 Cleaning development environment..."
    
    # Stop and remove containers, networks, and volumes
    docker-compose down -v --remove-orphans
    
    # Remove OpenVidu recording images for the specified tag
    IMAGE_NAME="openvidu/openvidu-recording:$TAG"
    if docker images "$IMAGE_NAME" --format "{{.Repository}}:{{.Tag}}" | grep -q "$IMAGE_NAME"; then
        echo "🗑️  Removing image: $IMAGE_NAME"
        docker rmi "$IMAGE_NAME" || true
    fi
    
    # Clean up dangling images
    if [ "$(docker images -f "dangling=true" -q)" ]; then
        echo "🗑️  Removing dangling images..."
        docker image prune -f
    fi
    
    echo "✅ Environment cleaned"
    echo "💡 To rebuild everything, run: ./replace-openvidu-image.sh $TAG"
}

test_container() {
    echo "🧪 Testing OpenVidu recording container (TAG: $TAG)..."
    
    IMAGE_NAME="openvidu/openvidu-recording:$TAG"
    
    # Check if image exists
    if ! docker images "$IMAGE_NAME" --format "{{.Repository}}:{{.Tag}}" | grep -q "$IMAGE_NAME"; then
        echo "❌ Image $IMAGE_NAME not found"
        echo "💡 Build it first with: ./replace-openvidu-image.sh $TAG"
        exit 1
    fi
    
    # Export TAG for docker-compose
    export TAG="$TAG"
    
    echo "🔍 Testing container basic functionality..."
    docker-compose run --rm openvidu-recording /bin/bash -c "
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
        echo '';
        echo '=== Test Completed ===';
    "
    
    if [ $? -eq 0 ]; then
        echo "✅ Container test passed successfully"
    else
        echo "❌ Container test failed"
        exit 1
    fi
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
    *)
        show_usage
        exit 1
        ;;
esac