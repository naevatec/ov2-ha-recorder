#!/bin/bash

# ov2-ha-recorder.sh - OpenVidu2 HA Recorder Operations Management
# Daily operations control script for OpenVidu2 HA Recorder solution
# Usage: ./ov2-ha-recorder.sh [command] [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Version and branding
OV2_HA_VERSION="1.0.0"
OV2_HA_NAME="OpenVidu2 HA Recorder"

# Load configuration from .env file
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Default values if not set in .env
IMAGE_TAG="${IMAGE_TAG:-2.31.0}"
HA_CONTROLLER_HOST="${HA_CONTROLLER_HOST:-localhost}"
HA_CONTROLLER_PORT="${HA_CONTROLLER_PORT:-15443}"
HA_CONTROLLER_USERNAME="${HA_CONTROLLER_USERNAME:-naeva_admin}"

# Load shared functions if available
if [ -f "${SCRIPT_DIR}/shared-functions.sh" ]; then
    source "${SCRIPT_DIR}/shared-functions.sh"
else
    # Define minimal functions
    print_header() { echo "=== $1 ==="; }
    print_info() { echo "INFO: $1"; }
    print_success() { echo "SUCCESS: $1"; }
    print_error() { echo "ERROR: $1" >&2; }
    print_step() { echo "STEP: $1"; }
fi

show_header() {
    echo "==============================================="
    echo "  $OV2_HA_NAME v$OV2_HA_VERSION"
    echo "  High Availability Recorder for OpenVidu"
    echo "==============================================="
    echo "  Location: docker/ov2-ha-recorder.sh"
    echo "  Installation: ../ov2-ha-recorder-install.sh"
    echo "==============================================="
    echo ""
}

show_usage() {
    show_header
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "SERVICE CONTROL:"
    echo "  start               Start all HA Recorder services"
    echo "  stop                Stop all services gracefully"
    echo "  restart             Restart all services"
    echo "  status              Show detailed service status"
    echo ""
    echo "MONITORING & LOGS:"
    echo "  logs [service]      Show logs from all services or specific service"
    echo "  logs-follow [svc]   Follow logs in real-time"
    echo "  health              Check health of all services"
    echo "  monitor             Real-time monitoring dashboard"
    echo ""
    echo "API TESTING:"
    echo "  test-api            Test HA Controller API endpoints"
    echo "  test-recording      Test complete recording workflow"
    echo "  test-failover       Test failover functionality"
    echo "  test-s3             Test S3/MinIO connectivity"
    echo ""
    echo "MAINTENANCE:"
    echo "  update              Update to latest image versions"
    echo "  backup              Backup configuration and data"
    echo "  clean               Clean up old containers and images"
    echo "  reset               Reset all services and data (DANGEROUS)"
    echo ""
    echo "CONFIGURATION:"
    echo "  config              Show current configuration"
    echo "  validate            Validate configuration and environment"
    echo "  reconfigure         Reconfigure webhook integration"
    echo ""
    echo "Available Services:"
    echo "  - ov-recorder-ha-controller     HA Controller service"
    echo "  - minio                         MinIO S3 storage"
    echo "  - redis                         Redis session storage"
    echo "  - minio-mc                      MinIO setup container"
    echo ""
    echo "Examples:"
    echo "  $0 start                    # Start all services"
    echo "  $0 status                   # Check service status"
    echo "  $0 logs ov-recorder-ha-controller  # View HA Controller logs"
    echo "  $0 logs-follow minio        # Follow MinIO logs in real-time"
    echo "  $0 test-api                 # Test API connectivity"
    echo "  $0 clean                    # Cleanup old resources"
    echo ""
    echo "Documentation: https://github.com/naevatec/ov2-ha-recorder"
}

# Function to check if system is installed
check_installation() {
    if [ ! -f ".env" ]; then
        print_error "$OV2_HA_NAME is not installed"
        echo ""
        echo "Please run the installation script first:"
        echo "   cd .. && ./ov2-ha-recorder-install.sh"
        echo ""
        exit 1
    fi
}

# Function to validate environment quickly
validate_environment_quick() {
    if [ -f "validate-env.sh" ]; then
        if ! "./validate-env.sh" >/dev/null 2>&1; then
            print_error "Environment validation failed"
            echo "Run: $0 validate for details"
            exit 1
        fi
    fi
}

# Function to create required directories
create_required_directories() {
    mkdir -p data/{minio,recorder,redis,controller}/{data,logs}
}

# Function to wait for container completion
wait_for_container_completion() {
    local container_name="$1"
    local timeout="${2:-60}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if container_status=$(docker compose ps -a "$container_name" --format "{{.State}}" 2>/dev/null); then
            case "$container_status" in
                "exited")
                    local exit_code=$(docker compose ps -a "$container_name" --format "{{.ExitCode}}" 2>/dev/null || echo "1")
                    return $exit_code
                    ;;
                "running")
                    ;;
                *)
                    ;;
            esac
        fi

        sleep 3
        elapsed=$((elapsed + 3))
    done

    return 1  # Timeout
}

# Function to wait for service health
wait_for_service_health() {
    local container_name="$1"
    local timeout="${2:-60}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "no-healthcheck")

            if [ "$health_status" = "healthy" ] || [ "$health_status" = "no-healthcheck" ]; then
                return 0
            fi
        fi

        sleep 3
        elapsed=$((elapsed + 3))
    done

    return 1
}

# Function to start all services
start_services() {
    show_header
    print_step "Starting $OV2_HA_NAME services"

    check_installation
    validate_environment_quick
    create_required_directories

    export IMAGE_TAG="$IMAGE_TAG"

    print_info "Starting infrastructure services..."
    docker compose up -d minio minio-mc redis

    print_info "Waiting for MinIO setup..."
    wait_for_container_completion "minio-mc" 60

    print_info "Starting HA Controller..."
    docker compose --profile ha-controller up -d ov-recorder-ha-controller

    print_info "Waiting for services to become healthy..."
    wait_for_service_health "ov-recorder-ha-controller" 90

    print_success "All services started successfully"
    show_service_urls
}

# Function to stop all services
stop_services() {
    show_header
    print_step "Stopping $OV2_HA_NAME services"

    print_info "Stopping services gracefully..."
    docker compose --profile ha-controller down

    echo ""
    echo "Do you want to remove data volumes? This will delete all recordings and session data. (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        print_step "Removing volumes..."
        docker compose down -v
        print_info "Data volumes removed"
    fi

    print_success "Services stopped successfully"
}

# Function to restart services
restart_services() {
    show_header
    print_step "Restarting $OV2_HA_NAME services"

    print_info "Stopping services..."
    docker compose --profile ha-controller down

    print_info "Starting services..."
    start_services
}

# Function to check service health
check_service_health_status() {
    local services=("minio" "redis" "ov-recorder-ha-controller")

    for service in "${services[@]}"; do
        if docker compose ps "$service" 2>/dev/null | grep -q "Up"; then
            health_status=$(docker inspect "${service}" --format='{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")

            case "$health_status" in
                "healthy")
                    echo "   $service: HEALTHY"
                    ;;
                "unhealthy")
                    echo "   $service: UNHEALTHY"
                    ;;
                "starting")
                    echo "   $service: STARTING"
                    ;;
                "no-healthcheck")
                    container_status=$(docker inspect "${service}" --format='{{.State.Status}}' 2>/dev/null || echo "unknown")
                    echo "   $service: $container_status (no health check)"
                    ;;
                *)
                    echo "   $service: UNKNOWN ($health_status)"
                    ;;
            esac
        else
            echo "   $service: NOT RUNNING"
        fi
    done
}

# Function to show resource usage
show_resource_usage() {
    if command -v docker >/dev/null 2>&1; then
        echo "   Docker Containers Resource Usage:"
        local container_ids=$(docker compose ps -q 2>/dev/null)
        if [ -n "$container_ids" ]; then
            docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" $container_ids 2>/dev/null || echo "   Unable to get resource statistics"
        else
            echo "   No containers running"
        fi
    fi
}

# Function to show service URLs
show_service_urls() {
    echo ""
    print_info "Service URLs:"
    echo "   HA Controller API: http://$HA_CONTROLLER_HOST:$HA_CONTROLLER_PORT/api/sessions"
    echo "   HA Controller Health: http://$HA_CONTROLLER_HOST:$HA_CONTROLLER_PORT/actuator/health"
    echo "   MinIO Console: http://$HA_CONTROLLER_HOST:${MINIO_CONSOLE_PORT:-9001}"
    echo "   MinIO API: http://$HA_CONTROLLER_HOST:${MINIO_API_PORT:-9000}"

    if [ -n "$HA_CONTROLLER_USERNAME" ]; then
        echo ""
        print_info "Authentication:"
        echo "   Username: $HA_CONTROLLER_USERNAME"
        echo "   Password: [configured in .env]"
    fi
}

# Function to show configuration summary
show_config_summary() {
    if [ -f ".env" ]; then
        echo "   Configuration file: .env (exists)"
        echo "   Image Tag: $IMAGE_TAG"
        echo "   Storage Mode: ${HA_RECORDING_STORAGE:-s3}"
        echo "   HA Controller: $HA_CONTROLLER_HOST:$HA_CONTROLLER_PORT"
        echo "   Webhook: ${OPENVIDU_WEBHOOK:-true}"
        echo "   S3 Endpoint: ${HA_AWS_S3_SERVICE_ENDPOINT:-not configured}"
    else
        echo "   Configuration file: .env (missing - run installation first)"
    fi
}

# Function to show detailed service status
show_detailed_status() {
    show_header
    print_info "$OV2_HA_NAME Service Status"

    echo ""
    print_info "Docker Compose Services:"
    if docker compose ps 2>/dev/null | grep -E "(minio|redis|ov-recorder)" >/dev/null; then
        docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}\t{{.Ports}}"
    else
        echo "   No services running"
        echo "   Run '$0 start' to start services"
    fi

    echo ""
    print_info "Service Health Status:"
    check_service_health_status

    echo ""
    print_info "System Resources:"
    show_resource_usage

    echo ""
    print_info "Configuration Status:"
    show_config_summary

    if docker compose ps ov-recorder-ha-controller 2>/dev/null | grep -q "Up"; then
        echo ""
        print_info "HA Controller API Status:"
        test_api_connectivity_simple
    fi

    echo ""
    print_info "Quick Actions:"
    echo "   Start services: $0 start"
    echo "   View logs: $0 logs"
    echo "   Test API: $0 test-api"
    echo "   Stop services: $0 stop"
}

# Function to show logs
show_logs() {
    local service="${1:-all}"
    local follow_mode="${2:-false}"

    if [ "$service" = "all" ]; then
        print_header "All Services Logs"

        local services=("minio" "minio-mc" "redis" "ov-recorder-ha-controller")
        for svc in "${services[@]}"; do
            if docker compose ps "$svc" 2>/dev/null | grep -q -E "Up|Exit"; then
                echo ""
                echo "=== $svc Logs ==="
                if [ "$follow_mode" = "true" ]; then
                    docker compose logs --tail=10 --follow "$svc" &
                else
                    docker compose logs --tail=20 "$svc"
                fi
            fi
        done

        if [ "$follow_mode" = "true" ]; then
            echo ""
            print_info "Following logs... Press Ctrl+C to exit"
            wait
        fi
    else
        if [ "$follow_mode" = "true" ]; then
            print_header "$service Logs (Following)"
        else
            print_header "$service Logs"
        fi

        if docker compose ps "$service" 2>/dev/null | grep -q -E "Up|Exit"; then
            if [ "$follow_mode" = "true" ]; then
                docker compose logs --tail=50 --follow "$service"
            else
                docker compose logs --tail=50 "$service"
            fi
        else
            print_error "Service '$service' not found or not running"
            echo ""
            echo "Available services:"
            docker compose ps --services 2>/dev/null || echo "No services defined"
        fi
    fi
}

# Function to follow logs in real-time
follow_logs() {
    local service="${1:-all}"
    show_logs "$service" "true"
}

# Function to test API connectivity (simple version for status)
test_api_connectivity_simple() {
    local base_url="http://$HA_CONTROLLER_HOST:$HA_CONTROLLER_PORT"
    local auth="$HA_CONTROLLER_USERNAME:$HA_CONTROLLER_PASSWORD"

    if curl -s -f "$base_url/actuator/health" >/dev/null 2>&1; then
        echo "   Health endpoint: OK"
    else
        echo "   Health endpoint: FAILED"
    fi

    if curl -s -f -u "$auth" "$base_url/api/sessions" >/dev/null 2>&1; then
        local session_count=$(curl -s -u "$auth" "$base_url/api/sessions" 2>/dev/null | jq '.sessions | length' 2>/dev/null || echo "0")
        echo "   Sessions API: OK (Active sessions: $session_count)"
    else
        echo "   Sessions API: FAILED"
    fi
}

# Function to test API connectivity
test_api_connectivity() {
    print_header "Testing HA Controller API"

    check_installation

    local base_url="http://$HA_CONTROLLER_HOST:$HA_CONTROLLER_PORT"
    local auth="$HA_CONTROLLER_USERNAME:$HA_CONTROLLER_PASSWORD"

    echo "Testing API endpoints..."
    echo "Base URL: $base_url"
    echo "Authentication: $HA_CONTROLLER_USERNAME"
    echo ""

    # Test health endpoint
    print_step "Testing health endpoint..."
    if curl -s -f "$base_url/actuator/health" >/dev/null 2>&1; then
        print_success "Health endpoint: OK"
        health_response=$(curl -s "$base_url/actuator/health" 2>/dev/null)
        if command -v jq >/dev/null 2>&1; then
            echo "$health_response" | jq '.'
        else
            echo "$health_response"
        fi
    else
        print_error "Health endpoint: FAILED"
        echo "   Make sure HA Controller is running: $0 start"
    fi
    echo ""

    # Test sessions endpoint
    print_step "Testing sessions API..."
    if curl -s -f -u "$auth" "$base_url/api/sessions" >/dev/null 2>&1; then
        print_success "Sessions API: OK"
        session_response=$(curl -s -u "$auth" "$base_url/api/sessions" 2>/dev/null)
        if command -v jq >/dev/null 2>&1 && echo "$session_response" | jq . >/dev/null 2>&1; then
            session_count=$(echo "$session_response" | jq '.sessions | length' 2>/dev/null || echo "unknown")
            echo "   Active sessions: $session_count"
            if [ "$session_count" != "0" ] && [ "$session_count" != "unknown" ]; then
                echo "   Session details:"
                echo "$session_response" | jq '.sessions[] | {sessionId, status, containerId}' 2>/dev/null || echo "$session_response"
            fi
        else
            echo "   Response: $session_response"
        fi
    else
        print_error "Sessions API: FAILED"
        echo "   Check authentication credentials in .env file"
    fi
    echo ""

    # Test webhook endpoint
    print_step "Testing webhook endpoint..."
    webhook_response=$(curl -s -w "%{http_code}" -X POST "$base_url/openvidu/webhook" \
         -H "Content-Type: application/json" \
         -d '{"event":"test","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
         -o /dev/null 2>/dev/null)

    if [ "$webhook_response" = "200" ] || [ "$webhook_response" = "202" ]; then
        print_success "Webhook endpoint: OK (HTTP $webhook_response)"
    else
        print_error "Webhook endpoint: FAILED (HTTP $webhook_response)"
    fi

    echo ""
    print_info "API Test Summary:"
    echo "   Health: $(curl -s -f "$base_url/actuator/health" >/dev/null 2>&1 && echo "OK" || echo "FAILED")"
    echo "   Sessions: $(curl -s -f -u "$auth" "$base_url/api/sessions" >/dev/null 2>&1 && echo "OK" || echo "FAILED")"
    echo "   Webhook: $([ "$webhook_response" = "200" ] || [ "$webhook_response" = "202" ] && echo "OK" || echo "FAILED")"
}

# Function to test complete recording workflow
test_recording_workflow() {
    print_header "Testing Complete Recording Workflow"

    check_installation

    local base_url="http://$HA_CONTROLLER_HOST:$HA_CONTROLLER_PORT"
    local auth="$HA_CONTROLLER_USERNAME:$HA_CONTROLLER_PASSWORD"
    local session_id="test-session-$(date +%s)"

    print_step "Creating test recording session..."

    local create_payload="{
        \"sessionId\": \"$session_id\",
        \"recordingName\": \"test-recording-$(date +%s)\",
        \"outputMode\": \"COMPOSED\",
        \"recordingLayout\": \"BEST_FIT\"
    }"

    local create_response
    create_response=$(curl -s -u "$auth" -X POST "$base_url/api/sessions" \
        -H "Content-Type: application/json" \
        -d "$create_payload" 2>/dev/null)

    if command -v jq >/dev/null 2>&1 && echo "$create_response" | jq . >/dev/null 2>&1; then
        print_success "Session created: $session_id"
        echo "$create_response" | jq .

        print_step "Checking session status..."
        sleep 5

        local status_response
        status_response=$(curl -s -u "$auth" "$base_url/api/sessions/$session_id" 2>/dev/null)

        if command -v jq >/dev/null 2>&1 && echo "$status_response" | jq . >/dev/null 2>&1; then
            print_success "Session status retrieved"
            echo "$status_response" | jq .

            print_step "Cleaning up test session..."
            local cleanup_response
            cleanup_response=$(curl -s -u "$auth" -X DELETE "$base_url/api/sessions/$session_id" 2>/dev/null)
            print_success "Test session cleaned up"
            if command -v jq >/dev/null 2>&1 && echo "$cleanup_response" | jq . >/dev/null 2>&1; then
                echo "$cleanup_response" | jq .
            fi
        else
            print_error "Failed to get session status"
            echo "Response: $status_response"
        fi
    else
        print_error "Failed to create test session"
        echo "Response: $create_response"
        echo ""
        print_info "Possible issues:"
        echo "   - HA Controller not running (check with: $0 status)"
        echo "   - Authentication failed (check credentials in .env)"
        echo "   - Network connectivity issues"
    fi
}

# Function to test S3/MinIO connectivity
test_s3_connectivity() {
    print_header "Testing S3/MinIO Connectivity"

    check_installation

    if ! docker compose ps minio 2>/dev/null | grep -q "Up"; then
        print_error "MinIO container is not running"
        echo "Start services first: $0 start"
        return 1
    fi

    local minio_url="http://$HA_CONTROLLER_HOST:${MINIO_API_PORT:-9000}"
    print_step "Testing MinIO health endpoint..."

    if curl -s -f "$minio_url/minio/health/live" >/dev/null 2>&1; then
        print_success "MinIO health: OK"
    else
        print_error "MinIO health: FAILED"
        echo "   MinIO might be starting up or misconfigured"
    fi

    print_step "Testing MinIO API access..."
    local access_key="${HA_AWS_ACCESS_KEY:-naeva_minio}"
    local secret_key="${HA_AWS_SECRET_KEY:-N43v4t3c_M1n10}"

    print_info "Attempting to verify bucket access..."
    echo "   Endpoint: $minio_url"
    echo "   Bucket: ${HA_AWS_S3_BUCKET:-ov-recordings}"
    echo "   Access Key: $access_key"

    if docker compose ps minio-mc 2>/dev/null | grep -q "Exit"; then
        print_step "Using MinIO client to test connectivity..."

        if docker compose run --rm minio-mc mc ls ovrecorder 2>/dev/null; then
            print_success "S3/MinIO connectivity: OK"
        else
            print_info "S3/MinIO connectivity test completed (check logs for details)"
        fi
    else
        print_info "MinIO client container not available for detailed testing"
    fi

    echo ""
    print_info "MinIO Console Access:"
    echo "   URL: http://$HA_CONTROLLER_HOST:${MINIO_CONSOLE_PORT:-9001}"
    echo "   Username: $access_key"
    echo "   Password: [configured in .env]"
}

# Function to run full environment validation
validate_environment_full() {
    print_header "Environment Validation"

    if [ -f "validate-env.sh" ]; then
        chmod +x "validate-env.sh"
        if "./validate-env.sh"; then
            print_success "Environment validation passed"
        else
            print_error "Environment validation failed"
            echo ""
            echo "Fix the issues above and run validation again"
        fi
    else
        print_error "validate-env.sh not found"
        echo ""
        echo "Basic validation:"
        if [ -f ".env" ]; then
            print_success ".env file exists"
        else
            print_error ".env file missing - run installation first"
        fi

        if command -v docker >/dev/null 2>&1; then
            print_success "Docker is available"
        else
            print_error "Docker is not available"
        fi

        if command -v docker compose >/dev/null 2>&1; then
            print_success "Docker Compose is available"
        else
            print_error "Docker Compose is not available"
        fi
    fi
}

# Function to show current configuration
show_configuration() {
    print_header "Current Configuration"

    check_installation

    echo ""
    print_info "Environment Configuration:"
    echo "   Configuration file: $(pwd)/.env"
    echo ""

    echo "Core Settings:"
    echo "   IMAGE_TAG: $IMAGE_TAG"
    echo "   HA_RECORDING_STORAGE: ${HA_RECORDING_STORAGE:-s3}"
    echo "   OPENVIDU_RECORDING_PATH: ${OPENVIDU_RECORDING_PATH:-/opt/openvidu/recordings}"
    echo ""

    echo "HA Controller:"
    echo "   Host: $HA_CONTROLLER_HOST"
    echo "   Port: $HA_CONTROLLER_PORT"
    echo "   Username: $HA_CONTROLLER_USERNAME"
    echo "   Password: [hidden]"
    echo ""

    echo "Storage (S3/MinIO):"
    echo "   Endpoint: ${HA_AWS_S3_SERVICE_ENDPOINT:-not set}"
    echo "   Bucket: ${HA_AWS_S3_BUCKET:-not set}"
    echo "   MinIO API Port: ${MINIO_API_PORT:-9000}"
    echo "   MinIO Console Port: ${MINIO_CONSOLE_PORT:-9001}"
    echo ""

    echo "Webhook Integration:"
    echo "   Enabled: ${OPENVIDU_WEBHOOK:-true}"
    echo "   Endpoint: ${OPENVIDU_WEBHOOK_ENDPOINT:-not set}"
    echo ""

    echo "Timing Configuration:"
    echo "   Heartbeat Interval: ${HEARTBEAT_INTERVAL:-10}s"
    echo "   Failover Check: ${HA_FAILOVER_CHECK_INTERVAL:-15}s"
    echo "   Max Missed Heartbeats: ${HA_MAX_MISSED_HEARTBEATS:-3}"

    echo ""
    echo "To modify configuration:"
    echo "   1. Edit .env file"
    echo "   2. Copy to recording path: cp .env ${OPENVIDU_RECORDING_PATH:-/opt/openvidu/recordings}/.env"
    echo "   3. Restart services: $0 restart"
}

# Function to update .env values
update_env_value() {
    local key="$1"
    local value="$2"
    local env_file=".env"

    if grep -q "^${key}=" "$env_file" 2>/dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^${key}=.*|${key}=${value}|" "$env_file"
        else
            sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
        fi
    else
        echo "${key}=${value}" >> "$env_file"
    fi
}

# Function to reconfigure webhook integration
reconfigure_webhook() {
    print_header "Reconfiguring Webhook Integration"

    check_installation

    echo "Current webhook configuration:"
    echo "   Enabled: ${OPENVIDU_WEBHOOK:-true}"
    echo "   Endpoint: ${OPENVIDU_WEBHOOK_ENDPOINT:-not set}"
    echo ""

    local ha_host=$(grep "^HA_CONTROLLER_HOST=" ".env" | cut -d'=' -f2)
    local ha_port=$(grep "^HA_CONTROLLER_PORT=" ".env" | cut -d'=' -f2)
    local webhook_url="http://${ha_host}:${ha_port}/openvidu/webhook"

    echo "Recommended webhook endpoint: $webhook_url"
    echo ""
    echo "Do you want to update the webhook configuration? (y/N)"
    read -r response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        update_env_value "OPENVIDU_WEBHOOK" "true"
        update_env_value "OPENVIDU_WEBHOOK_ENDPOINT" "$webhook_url"

        local recording_path="${OPENVIDU_RECORDING_PATH:-/opt/openvidu/recordings}"
        if cp ".env" "$recording_path/.env" 2>/dev/null || sudo cp ".env" "$recording_path/.env" 2>/dev/null; then
            print_success "Configuration copied to recording path"
        else
            print_error "Failed to copy configuration to recording path"
            echo "   Please manually copy .env to: $recording_path/.env"
        fi

        print_success "Webhook configuration updated"
        echo ""
        echo "Don't forget to update your OpenVidu .env file:"
        echo "   OPENVIDU_WEBHOOK=true"
        echo "   OPENVIDU_WEBHOOK_ENDPOINT=$webhook_url"
        echo ""
        echo "Then restart OpenVidu services"
    else
        print_info "Webhook configuration unchanged"
    fi
}

# Function to backup configuration and data
backup_data() {
    print_header "Backing up $OV2_HA_NAME Data"

    local backup_dir="backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"

    print_step "Creating backup in: $backup_dir"

    if [ -f ".env" ]; then
        cp ".env" "$backup_dir/.env"
        print_info "Configuration backed up"
    fi

    if [ -d "data" ]; then
        cp -r "data" "$backup_dir/"
        print_info "Data directories backed up"
    fi

    if [ -f "docker-compose.yml" ]; then
        cp "docker-compose.yml" "$backup_dir/"
    fi

    cat > "$backup_dir/restore.sh" << 'EOF'
#!/bin/bash
echo "Restoring ov2-ha-recorder backup..."
BACKUP_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$(dirname "$BACKUP_DIR")"

cd "$TARGET_DIR"

if [ -f "ov2-ha-recorder.sh" ]; then
    ./ov2-ha-recorder.sh stop 2>/dev/null || true
fi

if [ -f "$BACKUP_DIR/.env" ]; then
    cp "$BACKUP_DIR/.env" .env
    echo "Configuration restored"
fi

if [ -d "$BACKUP_DIR/data" ]; then
    rm -rf data 2>/dev/null || true
    cp -r "$BACKUP_DIR/data" .
    echo "Data restored"
fi

if [ -f "$BACKUP_DIR/docker-compose.yml" ]; then
    cp "$BACKUP_DIR/docker-compose.yml" .
    echo "Docker compose configuration restored"
fi

echo "Restore completed."
echo "Start services with: ./ov2-ha-recorder.sh start"
EOF
    chmod +x "$backup_dir/restore.sh"

    print_success "Backup created: $backup_dir"
    echo "   Configuration: $backup_dir/.env"
    echo "   Data: $backup_dir/data/"
    echo "   To restore: cd $backup_dir && ./restore.sh"
}

# Function to clean up resources
cleanup_resources() {
    print_header "Cleaning up $OV2_HA_NAME Resources"

    echo "This will remove:"
    echo "  - Stopped containers"
    echo "  - Unused networks"
    echo "  - Dangling images"
    echo "  - Old ov2-ha-recorder images (keeping latest 3)"
    echo ""
    echo "Data volumes will be preserved unless explicitly removed."
    echo ""
    echo "Continue? (y/N)"
    read -r response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        print_step "Stopping services..."
        docker compose down --remove-orphans 2>/dev/null || true

        print_step "Removing unused Docker resources..."
        docker system prune -f

        print_step "Cleaning up old HA Recorder images..."
        old_images=$(docker images | grep "ov-recorder-ha-controller" | awk '{print $3}' | tail -n +4)
        if [ -n "$old_images" ]; then
            echo "$old_images" | xargs docker rmi 2>/dev/null || true
        fi

        old_recording_images=$(docker images | grep "openvidu.*recording" | awk '{print $3}' | tail -n +4)
        if [ -n "$old_recording_images" ]; then
            echo "$old_recording_images" | xargs docker rmi 2>/dev/null || true
        fi

        print_success "Cleanup completed"

        if command -v df >/dev/null 2>&1; then
            echo ""
            print_info "Current disk usage:"
            df -h . | tail -n 1
        fi
    else
        print_info "Cleanup cancelled"
    fi
}

# Function to reset everything
reset_services() {
    print_header "Resetting $OV2_HA_NAME Services"

    echo "WARNING: This will remove ALL data including:"
    echo "  - All containers and networks"
    echo "  - All data volumes (recordings, Redis data, etc.)"
    echo "  - All Docker images"
    echo ""
    echo "Configuration files (.env) will be preserved."
    echo ""
    echo "This action cannot be undone!"
    echo ""
    echo "Are you absolutely sure? Type 'RESET' to continue:"
    read -r response

    if [ "$response" = "RESET" ]; then
        print_step "Stopping and removing all services..."
        docker compose down -v --remove-orphans 2>/dev/null || true

        print_step "Removing ov2-ha-recorder images..."
        docker images | grep -E "(openvidu.*recording|ov-recorder)" | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true

        print_step "Removing data directories..."
        rm -rf data/ 2>/dev/null || true

        print_step "Cleaning Docker system..."
        docker system prune -a -f --volumes 2>/dev/null || true

        print_success "Reset completed"
        echo ""
        echo "To reinstall:"
        echo "   cd .. && ./ov2-ha-recorder-install.sh"
        echo ""
        echo "Configuration preserved in .env file"
    else
        print_info "Reset cancelled"
    fi
}

# Function to update services
update_services() {
    print_header "Updating $OV2_HA_NAME Services"

    check_installation

    echo "This will:"
    echo "  - Pull latest base images"
    echo "  - Rebuild custom images"
    echo "  - Restart services with new images"
    echo ""
    echo "Continue? (y/N)"
    read -r response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        print_step "Pulling latest base images..."
        docker compose pull

        print_step "Rebuilding custom images..."
        export IMAGE_TAG="$IMAGE_TAG"
        docker compose build --no-cache

        print_step "Restarting services with new images..."
        restart_services

        print_success "Update completed"
    else
        print_info "Update cancelled"
    fi
}

# Function to monitor services in real-time
monitor_services() {
    print_header "Real-time Service Monitoring"
    print_info "Press Ctrl+C to exit monitoring"

    check_installation

    echo ""
    echo "Service Status Monitor:"
    while true; do
        clear
        echo "$OV2_HA_NAME - Live Monitor ($(date))"
        echo "=========================================="

        echo ""
        echo "Services:"
        docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}" 2>/dev/null || echo "No services running"

        echo ""
        echo "Resource Usage:"
        local container_ids=$(docker compose ps -q 2>/dev/null)
        if [ -n "$container_ids" ]; then
            docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" $container_ids 2>/dev/null || echo "Unable to get stats"
        else
            echo "No containers running"
        fi

        echo ""
        echo "Recent Activity (last 3 log entries):"
        if docker compose ps ov-recorder-ha-controller 2>/dev/null | grep -q "Up"; then
            docker compose logs --tail=3 --since=30s ov-recorder-ha-controller 2>/dev/null | tail -3 || echo "No recent activity"
        else
            echo "HA Controller not running"
        fi

        echo ""
        echo "Quick Commands:"
        echo "  Ctrl+C - Exit monitor"
        echo "  Run '$0 logs' in another terminal for detailed logs"

        sleep 5
    done
}

# Function to test failover functionality
test_failover() {
    print_header "Failover Testing"

    check_installation

    print_info "Failover testing requires a running recording session"
    echo ""
    echo "This test will:"
    echo "  1. Check for active recording sessions"
    echo "  2. If sessions exist, demonstrate failover capabilities"
    echo "  3. Show failover history and statistics"
    echo ""

    local base_url="http://$HA_CONTROLLER_HOST:$HA_CONTROLLER_PORT"
    local auth="$HA_CONTROLLER_USERNAME:$HA_CONTROLLER_PASSWORD"

    print_step "Checking for active recording sessions..."
    local sessions_response=$(curl -s -u "$auth" "$base_url/api/sessions" 2>/dev/null)

    if command -v jq >/dev/null 2>&1 && echo "$sessions_response" | jq . >/dev/null 2>&1; then
        local session_count=$(echo "$sessions_response" | jq '.sessions | length' 2>/dev/null || echo "0")

        if [ "$session_count" = "0" ]; then
            print_info "No active sessions found"
            echo ""
            echo "To test failover functionality:"
            echo "  1. Create a test session: $0 test-recording"
            echo "  2. Run failover test again: $0 test-failover"
        else
            print_success "Found $session_count active session(s)"
            echo "$sessions_response" | jq '.sessions[] | {sessionId, status, containerId}'

            echo ""
            echo "Failover testing options:"
            echo "  1. Manual failover trigger"
            echo "  2. View failover history"
            echo "  3. Show failover statistics"
            echo ""
            echo "Enter choice (1-3, or any other key to exit):"
            read -r choice

            case "$choice" in
                1)
                    local session_id=$(echo "$sessions_response" | jq -r '.sessions[0].sessionId' 2>/dev/null)
                    if [ -n "$session_id" ] && [ "$session_id" != "null" ]; then
                        echo ""
                        echo "Triggering manual failover for session: $session_id"
                        echo "Are you sure? (y/N)"
                        read -r confirm
                        if [[ "$confirm" =~ ^[Yy]$ ]]; then
                            local failover_response=$(curl -s -u "$auth" -X POST "$base_url/api/failover/$session_id" \
                                -H "Content-Type: application/json" \
                                -d '{"reason": "MANUAL_TEST", "preserveProgress": true}' 2>/dev/null)

                            if command -v jq >/dev/null 2>&1 && echo "$failover_response" | jq . >/dev/null 2>&1; then
                                print_success "Failover triggered successfully"
                                echo "$failover_response" | jq .
                            else
                                print_error "Failover request failed"
                                echo "Response: $failover_response"
                            fi
                        fi
                    fi
                    ;;
                2)
                    local session_id=$(echo "$sessions_response" | jq -r '.sessions[0].sessionId' 2>/dev/null)
                    if [ -n "$session_id" ] && [ "$session_id" != "null" ]; then
                        print_step "Retrieving failover history for session: $session_id"
                        local history_response=$(curl -s -u "$auth" "$base_url/api/failover/$session_id/history" 2>/dev/null)

                        if command -v jq >/dev/null 2>&1 && echo "$history_response" | jq . >/dev/null 2>&1; then
                            echo "$history_response" | jq .
                        else
                            echo "Response: $history_response"
                        fi
                    fi
                    ;;
                3)
                    print_step "Showing system failover statistics..."
                    print_info "Active sessions: $session_count"

                    local metrics_response=$(curl -s "$base_url/actuator/metrics" 2>/dev/null)
                    if command -v jq >/dev/null 2>&1 && echo "$metrics_response" | jq . >/dev/null 2>&1; then
                        echo "System metrics available at: $base_url/actuator/metrics"
                    fi
                    ;;
                *)
                    print_info "Failover test cancelled"
                    ;;
            esac
        fi
    else
        print_error "Failed to retrieve session information"
        echo "Make sure HA Controller is running: $0 status"
    fi
}

# Main command dispatcher
main() {
    case "${1:-}" in
        start)
            start_services
            ;;
        stop)
            stop_services
            ;;
        restart)
            restart_services
            ;;
        status)
            show_detailed_status
            ;;
        logs)
            show_logs "${2:-all}"
            ;;
        logs-follow)
            follow_logs "${2:-all}"
            ;;
        health)
            print_header "Health Check"
            check_service_health_status
            ;;
        monitor)
            monitor_services
            ;;
        test-api)
            test_api_connectivity
            ;;
        test-recording)
            test_recording_workflow
            ;;
        test-s3)
            test_s3_connectivity
            ;;
        test-failover)
            test_failover
            ;;
        config)
            show_configuration
            ;;
        validate)
            validate_environment_full
            ;;
        reconfigure)
            reconfigure_webhook
            ;;
        backup)
            backup_data
            ;;
        update)
            update_services
            ;;
        clean)
            cleanup_resources
            ;;
        reset)
            reset_services
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
