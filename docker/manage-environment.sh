#!/bin/bash

# Development helper script for OpenVidu HA Recorder environment with HA Controller
# Complements the main replace-openvidu-image.sh workflow
# Usage: ./manage-environment.sh [command] [TAG]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TAG="${2:-2.31.0}"

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
        echo "⚠️ validate-env.sh not found, skipping validation"
    fi
}

create_directories() {
    echo "📁 Creating required directories..."
    mkdir -p data/minio/data
    mkdir -p data/recorder/data
    mkdir -p data/redis/data
    mkdir -p data/controller/logs
    mkdir -p server
    mkdir -p recorder/scripts
    mkdir -p recorder/utils
    echo "✅ Directories created"
}

start_environment() {
    echo "🚀 Starting environment (TAG: $TAG)"
    echo "📡 HA Controller: ENABLED (always included)"
    
    validate_environment
    create_directories
    
    # Export TAG for docker-compose
    export TAG="$TAG"
    
    # Start MinIO services
    echo "📦 Starting MinIO and setup..."
    docker compose up -d minio minio-mc
    
    # Wait for MinIO setup to complete
    echo "⏳ Waiting for MinIO setup to complete..."
    timeout=60
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if ! docker compose ps minio-mc | grep -q "Up"; then
            exit_code=$(docker compose ps -q minio-mc | xargs docker inspect --format='{{.State.ExitCode}}' 2>/dev/null || echo "1")
            if [ "$exit_code" = "0" ]; then
                echo "✅ MinIO setup completed successfully"
                break
            else
                echo "❌ MinIO setup failed"
                docker compose logs minio-mc
                exit 1
            fi
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    # Start HA Controller
    echo "📦 Starting Redis..."
    docker compose up -d redis
    
    echo "📦 Building and starting HA Controller..."
    docker compose build ov-recorder-ha-controller
    docker compose --profile ha-controller up -d ov-recorder-ha-controller
    
    # Wait for HA Controller
    echo "⏳ Waiting for HA Controller to be ready..."
    timeout=60
    elapsed=0
    ha_port="${HA_RECORDER_PORT:-8080}"
    
    while [ $elapsed -lt $timeout ]; do
        if curl -s -f "http://localhost:${ha_port}/actuator/health" >/dev/null 2>&1; then
            echo "✅ HA Controller is ready"
            break
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    
    if [ $elapsed -ge $timeout ]; then
        echo "⚠️ HA Controller startup timeout, check logs"
    fi
    
    echo "✅ Environment is ready"
    echo "🌐 MinIO Console: http://localhost:${MINIO_CONSOLE_PORT:-9001}"
    echo "🔗 MinIO API: http://localhost:${MINIO_API_PORT:-9000}"
    echo "📡 HA Controller API: http://localhost:${ha_port}/api/sessions"
    echo "🏥 HA Controller Health: http://localhost:${ha_port}/actuator/health"
    
    echo ""
    echo "💡 To build and deploy the OpenVidu image, run:"
    echo "   ./replace-openvidu-image.sh $TAG"
}

stop_environment() {
    echo "🛑 Stopping all services..."
    docker compose down
    echo "✅ All services stopped"
}

show_status() {
    echo "📊 Environment Status:"
    echo ""
    echo "🐳 Docker Compose Services:"
    if docker compose ps 2>/dev/null | grep -q "openvidu\|minio\|redis\|ov-recorder"; then
        docker compose ps
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
    echo "📡 HA Controller Images:"
    if docker images | grep -q "ov-recorder-ha-controller"; then
        docker images | grep "ov-recorder-ha-controller" | head -5
    else
        echo "   No HA Controller images found"
    fi
    
    echo ""
    echo "🏷️ Environment Variables Status:"
    if [ -f ".env" ]; then
        echo "   ✅ .env file exists"
        if command -v grep >/dev/null 2>&1; then
            echo "   TAG: $(grep '^TAG=' .env 2>/dev/null | cut -d'=' -f2 || echo 'not set')"
            echo "   HA_AWS_S3_SERVICE_ENDPOINT: $(grep '^HA_AWS_S3_SERVICE_ENDPOINT=' .env 2>/dev/null | cut -d'=' -f2 || echo 'not set')"
            echo "   HA_RECORDER_PORT: $(grep '^HA_RECORDER_PORT=' .env 2>/dev/null | cut -d'=' -f2 || echo 'not set')"
            echo "   MINIO_API_PORT: $(grep '^MINIO_API_PORT=' .env 2>/dev/null | cut -d'=' -f2 || echo 'not set')"
        fi
    else
        echo "   ❌ .env file not found"
    fi
    
    # Check if HA Controller is running
    if docker compose ps ov-recorder-ha-controller 2>/dev/null | grep -q "Up"; then
        ha_port="${HA_RECORDER_PORT:-8080}"
        echo ""
        echo "📡 HA Controller Status: RUNNING"
        echo "   API: http://localhost:${ha_port}/api/sessions"
        if curl -s -f "http://localhost:${ha_port}/actuator/health" >/dev/null 2>&1; then
            echo "   Health: ✅ HEALTHY"
        else
            echo "   Health: ❌ UNHEALTHY"
        fi
    else
        echo ""
        echo "📡 HA Controller Status: NOT RUNNING"
    fi
}

show_logs() {
    echo "📋 Service Logs:"
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
    echo "🧹 Cleaning development environment..."
    
    # Stop and remove containers, networks, and volumes
    docker compose down -v --remove-orphans
    
    # Remove OpenVidu recording images for the specified tag
    IMAGE_NAME="openvidu/openvidu-recording:$TAG"
    if docker images "$IMAGE_NAME" --format "{{.Repository}}:{{.Tag}}" | grep -q "$IMAGE_NAME"; then
        echo "🗑️ Removing image: $IMAGE_NAME"
        docker rmi "$IMAGE_NAME" || true
    fi
    
    # Remove HA Controller images
    HA_IMAGES=$(docker images | grep "ov-recorder-ha-controller" | awk '{print $3}' || true)
    if [ -n "$HA_IMAGES" ]; then
        echo "🗑️ Removing HA Controller images..."
        echo "$HA_IMAGES" | xargs docker rmi || true
    fi
    
    # Clean up dangling images
    if [ "$(docker images -f "dangling=true" -q)" ]; then
        echo "🗑️ Removing dangling images..."
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
    
    # Export TAG for docker compose
    export TAG="$TAG"
    
    echo "🔍 Testing container basic functionality..."
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
        echo "✅ Container test passed successfully"
    else
        echo "❌ Container test failed"
        exit 1
    fi
}

test_ha_controller() {
    echo "🧪 Testing HA Controller API..."
    
    ha_port="${HA_RECORDER_PORT:-8080}"
    username="${HA_RECORDER_USERNAME:-recorder}"
    password="${HA_RECORDER_PASSWORD:-rec0rd3r_2024!}"
    
    # Check if HA Controller is running
    if ! docker compose ps ov-recorder-ha-controller | grep -q "Up"; then
        echo "❌ HA Controller is not running"
        echo "💡 Start it first with: $0 start $TAG"
        exit 1
    fi
    
    # Test health endpoint
    echo "🏥 Testing health endpoint..."
    if curl -s -f "http://localhost:${ha_port}/actuator/health" >/dev/null 2>&1; then
        echo "✅ Health endpoint is accessible"
    else
        echo "❌ Health endpoint is not accessible"
        exit 1
    fi
    
    # Test authenticated health endpoint
    echo "🔐 Testing authenticated health endpoint..."
    if curl -s -u "${username}:${password}" "http://localhost:${ha_port}/api/sessions/health" | grep -q "healthy"; then
        echo "✅ Authenticated health endpoint is working"
    else
        echo "❌ Authenticated health endpoint failed"
        exit 1
    fi
    
    # Test session creation
    echo "📝 Testing session creation..."
    session_id="test-$(date +%s)"
    session_response=$(curl -s -u "${username}:${password}" -X POST \
        "http://localhost:${ha_port}/api/sessions" \
        -H "Content-Type: application/json" \
        -d "{\"sessionId\":\"${session_id}\",\"clientId\":\"test-client\",\"clientHost\":\"127.0.0.1\"}")
    
    if echo "$session_response" | grep -q "$session_id"; then
        echo "✅ Session creation test passed"
        
        # Test session retrieval
        echo "📋 Testing session retrieval..."
        if curl -s -u "${username}:${password}" "http://localhost:${ha_port}/api/sessions/${session_id}" | grep -q "$session_id"; then
            echo "✅ Session retrieval test passed"
        else
            echo "❌ Session retrieval test failed"
        fi
        
        # Test heartbeat
        echo "💓 Testing heartbeat..."
        if curl -s -u "${username}:${password}" -X PUT "http://localhost:${ha_port}/api/sessions/${session_id}/heartbeat" | grep -q "Heartbeat updated"; then
            echo "✅ Heartbeat test passed"
        else
            echo "❌ Heartbeat test failed"
        fi
        
        # Clean up test session
        curl -s -u "${username}:${password}" -X DELETE "http://localhost:${ha_port}/api/sessions/${session_id}" >/dev/null
        echo "🧹 Test session cleaned up"
        
    else
        echo "❌ Session creation test failed"
        echo "Response: $session_response"
        exit 1
    fi
    
    echo "✅ All HA Controller tests passed!"
}

test_recorder() {
    echo "🎥 Full S3 Recording Test (TAG: $TAG)"
    echo "This will test a complete 20-second recording workflow with S3 storage"
    echo ""
    
    # Validate environment first
    validate_environment
    
    IMAGE_NAME="openvidu/openvidu-recording:$TAG"
    
    # Check if image exists
    if ! docker images "$IMAGE_NAME" --format "{{.Repository}}:{{.Tag}}" | grep -q "$IMAGE_NAME"; then
        echo "❌ Image $IMAGE_NAME not found"
        echo "💡 Build it first with: ./replace-openvidu-image.sh $TAG"
        exit 1
    fi
    
    # Ensure MinIO is running
    if ! docker compose ps minio | grep -q "Up"; then
        echo "🚀 Starting MinIO services first..."
        start_environment
    fi
    
    # Export environment for docker compose
    export TAG="$TAG"
    export HA_RECORDING_STORAGE="s3"
    
    echo "🎬 Starting recording test with S3 storage..."
    echo "📁 Creating local directories..."
    mkdir -p ./data/recorder/data
    
    # Start recorder with test profile
    docker compose --profile test up -d openvidu-recording
    
    # Wait for container to be ready
    echo "⏳ Waiting for recorder to initialize..."
    sleep 5
    
    # Check if container is running
    if ! docker compose ps openvidu-recording | grep -q "Up"; then
        echo "❌ Recorder failed to start"
        docker compose logs openvidu-recording
        exit 1
    fi
    
    echo "✅ Recorder container is running"
    echo "📋 Container logs (last 10 lines):"
    docker compose logs --tail=10 openvidu-recording
    
    echo ""
    echo "📊 Test Summary:"
    echo "   - MinIO is accessible at: http://localhost:${MINIO_CONSOLE_PORT:-9001}"
    echo "   - Bucket: ${HA_AWS_S3_BUCKET:-ov-recordings}"
    echo "   - Local recordings: ./data/recorder/data"
    echo "   - S3 Storage mode: ENABLED"
    echo ""
    echo "💡 Check MinIO console to verify S3 connectivity works"
    echo "💡 Use 'docker compose logs openvidu-recording' for detailed logs"
    echo ""
    echo "🛑 To stop the test:"
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
        test_ha_controller
        ;;
    test-recorder)
        test_recorder
        ;;
    *)
        show_usage
        exit 1
        ;;
esac