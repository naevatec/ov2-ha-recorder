#!/bin/bash

# Shared functions library for OpenVidu HA Recorder scripts
# This file contains common functions used by multiple scripts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper functions for output
print_header() {
    echo -e "${CYAN}=============================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}=============================================${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# Validation functions
validate_environment() {
    echo "🔍 Validating environment..."
    if [ -f "validate-env.sh" ]; then
        chmod +x validate-env.sh
        if ! ./validate-env.sh; then
            print_error "Environment validation failed"
            echo "💡 Please fix environment issues before proceeding"
            exit 1
        fi
    else
        print_warning "validate-env.sh not found, skipping validation"
    fi
}

# Directory management
create_directories() {
    print_step "Creating required directories..."
    mkdir -p data/minio/data
    mkdir -p data/recorder/data
    mkdir -p data/redis/data
    mkdir -p data/controller/logs
    mkdir -p server
    mkdir -p recorder/scripts
    mkdir -p recorder/utils
    print_success "Directories created"
}

# MinIO setup functions
wait_for_minio_setup() {
    print_step "Waiting for MinIO setup to complete..."
    timeout=120
    elapsed=0
    setup_completed=false
    
    while [ $elapsed -lt $timeout ]; do
        # Check if minio-mc container exists and get its status
        if mc_status=$(docker compose ps -a minio-mc --format "{{.State}}" 2>/dev/null); then
            case "$mc_status" in
                "running")
                    echo -n "."
                    ;;
                "exited")
                    exit_code=$(docker compose ps -a minio-mc --format "{{.ExitCode}}" 2>/dev/null || echo "1")
                    if [ "$exit_code" = "0" ]; then
                        echo ""
                        print_success "MinIO setup completed successfully"
                        setup_completed=true
                        break
                    else
                        echo ""
                        print_error "MinIO setup failed with exit code: $exit_code"
                        echo "📋 MinIO setup logs:"
                        docker compose logs minio-mc
                        exit 1
                    fi
                    ;;
                *)
                    echo -n "."
                    ;;
            esac
        else
            echo -n "."
        fi
        
        sleep 3
        elapsed=$((elapsed + 3))
    done
    
    if [ "$setup_completed" = false ]; then
        echo ""
        print_warning "MinIO setup timeout reached (${timeout}s), checking final status..."
        echo "📋 MinIO setup logs:"
        docker compose logs minio-mc
        
        # Check if setup actually completed despite timeout
        if docker compose logs minio-mc | grep -q "MinIO setup completed successfully"; then
            print_success "MinIO setup completed successfully (detected from logs)"
        else
            print_error "MinIO setup failed or timed out"
            exit 1
        fi
    fi
}

start_minio_services() {
    print_step "Starting MinIO services..."
    
    # Export IMAGE_TAG for docker compose
    export IMAGE_TAG="${IMAGE_TAG:-latest}"
    
    # Start MinIO services first
    print_info "Starting MinIO and setup containers..."
    docker compose up -d minio minio-mc
    
    # Wait for setup completion
    wait_for_minio_setup
    
    # Verify MinIO is healthy
    print_info "Checking MinIO health..."
    minio_health_timeout=30
    minio_elapsed=0
    
    while [ $minio_elapsed -lt $minio_health_timeout ]; do
        if docker compose ps minio --format "{{.State}}" | grep -q "running"; then
            if docker compose exec -T minio curl -f http://localhost:9000/minio/health/live >/dev/null 2>&1; then
                print_success "MinIO is healthy and responding"
                break
            fi
        fi
        
        echo -n "."
        sleep 3
        minio_elapsed=$((minio_elapsed + 3))
    done
    
    if [ $minio_elapsed -ge $minio_health_timeout ]; then
        print_warning "MinIO health check timeout, but continuing..."
    fi
    
    print_success "MinIO services are ready"
    print_info "MinIO Console: http://localhost:${MINIO_CONSOLE_PORT:-9001}"
    print_info "MinIO API: http://localhost:${MINIO_API_PORT:-9000}"
}

# HA Controller functions
start_ha_controller() {
    print_step "Starting HA Controller..."
    
    # Start Redis first
    print_info "Starting Redis..."
    docker compose up -d redis
    
    # Build and start HA Controller
    print_info "Building and starting HA Controller..."
    docker compose build ov-recorder-ha-controller
    docker compose --profile ha-controller up -d ov-recorder-ha-controller
    
    # Wait for HA Controller to be ready
    print_info "Waiting for HA Controller to be ready..."
    timeout=90
    elapsed=0
    ha_port="${HA_CONTROLLER_PORT:-8080}"
    
    while [ $elapsed -lt $timeout ]; do
        if curl -s -f "http://localhost:${ha_port}/actuator/health" >/dev/null 2>&1; then
            print_success "HA Controller is ready"
            
            # Test HA Controller API
            print_info "Testing HA Controller API..."
            username="${HA_CONTROLLER_USERNAME:-recorder}"
            password="${HA_CONTROLLER_PASSWORD:-rec0rd3r_2024!}"
            
            if curl -s -u "${username}:${password}" \
                    "http://localhost:${ha_port}/api/sessions/health" | grep -q "healthy"; then
                print_success "HA Controller API is working"
            else
                print_warning "HA Controller API test failed"
            fi
            
            return 0
        fi
        
        echo -n "."
        sleep 3
        elapsed=$((elapsed + 3))
    done
    
    echo ""
    print_error "HA Controller failed to start within $timeout seconds"
    print_info "Checking logs..."
    docker compose logs ov-recorder-ha-controller
    exit 1
}

# Testing functions
test_ha_controller_api() {
    print_step "Testing HA Controller API..."
    
    ha_port="${HA_CONTROLLER_PORT:-8080}"
    username="${HA_CONTROLLER_USERNAME:-recorder}"
    password="${HA_CONTROLLER_PASSWORD:-rec0rd3r_2024!}"
    
    # Check if HA Controller is running
    if ! docker compose ps ov-recorder-ha-controller | grep -q "Up"; then
        print_error "HA Controller is not running"
        print_info "Start it first with: ./manage-environment.sh start"
        exit 1
    fi
    
    # Test health endpoint
    print_info "Testing health endpoint..."
    if curl -s -f "http://localhost:${ha_port}/actuator/health" >/dev/null 2>&1; then
        print_success "Health endpoint is accessible"
    else
        print_error "Health endpoint is not accessible"
        exit 1
    fi
    
    # Test authenticated health endpoint
    print_info "Testing authenticated health endpoint..."
    if curl -s -u "${username}:${password}" "http://localhost:${ha_port}/api/sessions/health" | grep -q "healthy"; then
        print_success "Authenticated health endpoint is working"
    else
        print_error "Authenticated health endpoint failed"
        exit 1
    fi
    
    # Test session creation
    print_info "Testing session creation..."
    session_id="test-$(date +%s)"
    session_response=$(curl -s -u "${username}:${password}" -X POST \
        "http://localhost:${ha_port}/api/sessions" \
        -H "Content-Type: application/json" \
        -d "{\"sessionId\":\"${session_id}\",\"clientId\":\"test-client\",\"clientHost\":\"127.0.0.1\"}")
    
    if echo "$session_response" | grep -q "$session_id"; then
        print_success "Session creation test passed"
        
        # Test heartbeat
        print_info "Testing heartbeat..."
        if curl -s -u "${username}:${password}" -X PUT "http://localhost:${ha_port}/api/sessions/${session_id}/heartbeat" | grep -q "Heartbeat updated"; then
            print_success "Heartbeat test passed"
        else
            print_warning "Heartbeat test failed"
        fi
        
        # Clean up test session
        curl -s -u "${username}:${password}" -X DELETE "http://localhost:${ha_port}/api/sessions/${session_id}" >/dev/null
        print_info "Test session cleaned up"
        
    else
        print_error "Session creation test failed"
        echo "Response: $session_response"
        exit 1
    fi
    
    print_success "All HA Controller tests passed!"
}

# Status display functions
show_service_status() {
    print_step "System Status"
    
    echo ""
    print_info "Docker Compose Services:"
    if docker compose ps 2>/dev/null | grep -q "openvidu\|minio\|redis\|ov-recorder"; then
        docker compose ps
    else
        echo "   No services running"
    fi
    
    echo ""
    print_info "Service URLs:"
    ha_port="${HA_CONTROLLER_PORT:-8080}"
    echo "  • HA Controller API:  http://localhost:${ha_port}/api/sessions"
    echo "  • HA Controller Health: http://localhost:${ha_port}/actuator/health"
    echo "  • MinIO Console:      http://localhost:${MINIO_CONSOLE_PORT:-9001}"
    echo "  • MinIO API:          http://localhost:${MINIO_API_PORT:-9000}"
    echo "  • Redis:              internal only (no external access)"
    
    echo ""
    print_info "Authentication:"
    username="${HA_CONTROLLER_USERNAME:-recorder}"
    password="${HA_CONTROLLER_PASSWORD:-rec0rd3r_2024!}"
    echo "  • HA Controller: ${username} / [password hidden]"
    echo "  • MinIO: ${HA_AWS_ACCESS_KEY:-naeva_minio} / [password hidden]"
    
    echo ""
    print_info "Quick Commands:"
    echo "  • Health: curl -u ${username}:${password} http://localhost:${ha_port}/api/sessions/health"
    echo "  • Logs: docker compose logs ov-recorder-ha-controller"
}

# OpenVidu image replacement functions
replace_openvidu_image() {
    print_step "Performing OpenVidu image replacement..."
    
    # Image configuration variables
    IMAGE_NAME="openvidu/openvidu-recording"
    FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
    OLD_MAINTAINER="OpenVidu info@openvidu.io"
    NEW_MAINTAINER="NaevaTec-OpenVidu eiglesia@openvidu.io"
    
    # Check and remove old image
    print_info "Checking for existing image: ${FULL_IMAGE_NAME}"
    
    if docker images "${FULL_IMAGE_NAME}" --format "table {{.Repository}}:{{.Tag}}" | grep -q "${FULL_IMAGE_NAME}"; then
        print_info "Image ${FULL_IMAGE_NAME} found"
        
        # Check maintainer label
        MAINTAINER=$(docker inspect "${FULL_IMAGE_NAME}" --format='{{index .Config.Labels "maintainer"}}' 2>/dev/null || echo "")
        
        if [ "$MAINTAINER" = "$OLD_MAINTAINER" ]; then
            print_info "Found image with old maintainer label: $MAINTAINER"
            print_info "Removing old image..."
            docker rmi "${FULL_IMAGE_NAME}"
            print_success "Old image removed successfully"
        elif [ "$MAINTAINER" = "$NEW_MAINTAINER" ]; then
            print_info "Image already has the new maintainer label: $MAINTAINER"
            print_info "Skipping removal, but will rebuild to ensure latest version"
        else
            print_warning "Image has different maintainer label: $MAINTAINER"
            print_warning "Removing anyway to ensure clean replacement..."
            docker rmi "${FULL_IMAGE_NAME}"
        fi
    else
        print_info "Image ${FULL_IMAGE_NAME} not found locally"
    fi
    
    # Build new image
    print_info "Building new image with docker compose: ${FULL_IMAGE_NAME}"
    export IMAGE_TAG="$TAG"
    export IMAGE_NAME="$IMAGE_NAME"
    docker compose build openvidu-recording
    
    # Verify the new image has correct label
    NEW_MAINTAINER_CHECK=$(docker inspect "${FULL_IMAGE_NAME}" --format='{{index .Config.Labels "maintainer"}}' 2>/dev/null || echo "")
    
    if [ "$NEW_MAINTAINER_CHECK" = "$NEW_MAINTAINER" ]; then
        print_success "New image built successfully with correct maintainer label: $NEW_MAINTAINER_CHECK"
    else
        print_error "Error: New image has incorrect maintainer label: $NEW_MAINTAINER_CHECK"
        exit 1
    fi
}
