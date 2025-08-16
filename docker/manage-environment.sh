#!/bin/bash

# Environment management script for OpenVidu recording image replacement
# Usage: ./manage-environment.sh [start|stop|status|logs|clean] [TAG]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TAG="${2:-latest}"

show_usage() {
    echo "Usage: $0 [start|stop|status|logs|clean|test] [TAG]"
    echo ""
    echo "Commands:"
    echo "  start   - Start MinIO and build/run the OpenVidu recording image"
    echo "  stop    - Stop all services"
    echo "  status  - Show status of all services"
    echo "  logs    - Show logs from all services"
    echo "  clean   - Stop services and remove volumes"
    echo "  test    - Test the recording container"
    echo ""
    echo "TAG: Docker image tag to use (default: latest)"
    echo ""
    echo "Examples:"
    echo "  $0 start 2.29.0"
    echo "  $0 status"
    echo "  $0 logs"
    echo "  $0 clean"
}

start_environment() {
    echo "🚀 Starting environment with TAG: $TAG"
    
    # Export TAG for docker-compose
    export TAG="$TAG"
    
    # Start MinIO first
    echo "📦 Starting MinIO..."
    docker-compose up -d minio minio-setup
    
    # Wait for MinIO setup to complete
    echo "⏳ Waiting for MinIO setup to complete..."
    docker-compose logs -f minio-setup 2>/dev/null | grep -q "MinIO setup completed" || true
    
    echo "✅ MinIO environment is ready"
    echo "🌐 MinIO Console: http://localhost:9001 (minioadmin/minioadmin123)"
    echo "🔗 MinIO API: http://localhost:9000"
}

stop_environment() {
    echo "🛑 Stopping environment..."
    docker-compose down
    echo "✅ Environment stopped"
}

show_status() {
    echo "📊 Environment Status:"
    echo ""
    docker-compose ps
    echo ""
    echo "📦 Docker Images:"
    docker images "openvidu/openvidu-recording" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}"
}

show_logs() {
    echo "📋 Service Logs:"
    docker-compose logs -f
}

clean_environment() {
    echo "🧹 Cleaning environment..."
    docker-compose down -v --remove-orphans
    
    # Remove the image if it exists
    if [ "$TAG" != "latest" ]; then
        IMAGE_NAME="openvidu/openvidu-recording:$TAG"
        if docker images "$IMAGE_NAME" --format "{{.Repository}}:{{.Tag}}" | grep -q "$IMAGE_NAME"; then
            echo "🗑️  Removing image: $IMAGE_NAME"
            docker rmi "$IMAGE_NAME" || true
        fi
    fi
    
    echo "✅ Environment cleaned"
}

test_container() {
    echo "🧪 Testing OpenVidu recording container..."
    
    export TAG="$TAG"
    
    # Build and run the container for testing
    docker-compose build openvidu-recording
    
    # Test basic functionality
    echo "🔍 Testing container basic functionality..."
    docker-compose run --rm openvidu-recording /bin/bash -c "
        echo 'Testing Chrome installation...';
        google-chrome --version;
        echo 'Testing FFmpeg installation...';
        ffmpeg -version | head -n 1;
        echo 'Testing xvfb-run-safe...';
        which xvfb-run-safe;
        echo 'Testing recordings directory...';
        ls -la /recordings;
        echo 'All tests passed!';
    "
    
    echo "✅ Container test completed successfully"
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