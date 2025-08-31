#!/bin/bash

# ov2-ha-recorder-install.sh - OpenVidu2 HA Recorder Installation Script
# One-time installation and setup with interactive configuration
# Usage: ./ov2-ha-recorder-install.sh [--auto] [OPENVIDU_PATH]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$SCRIPT_DIR/docker"
DEFAULT_OPENVIDU_PATH="/opt/openvidu"

# Check for auto mode (non-interactive)
AUTO_MODE=false
if [ "$1" = "--auto" ]; then
    AUTO_MODE=true
    shift
fi

OPENVIDU_PATH="${1:-$DEFAULT_OPENVIDU_PATH}"

# Version and branding
OV2_HA_VERSION="1.0.0"
OV2_HA_NAME="OpenVidu2 HA Recorder"

echo "========================================================"
echo "  $OV2_HA_NAME v$OV2_HA_VERSION - Installation"
echo "  High Availability Recorder for OpenVidu"
echo "========================================================"

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

# Centralized validation function
validate_requirements() {
    local validation_type="$1"

    case "$validation_type" in
        "openvidu")
            if [ ! -d "$OPENVIDU_PATH" ]; then
                print_error "OpenVidu installation not found at: $OPENVIDU_PATH"
                echo ""
                echo "Please provide the correct OpenVidu installation path or install OpenVidu first:"
                echo "   https://docs.openvidu.io/en/stable/deployment/ce/on-premises/"
                exit 1
            fi

            for file in "docker-compose.yml" ".env"; do
                if [ ! -f "$OPENVIDU_PATH/$file" ]; then
                    print_error "OpenVidu $file not found in: $OPENVIDU_PATH"
                    exit 1
                fi
            done
            ;;
        "environment")
            if [ -f "$DOCKER_DIR/validate-env.sh" ]; then
                cd "$DOCKER_DIR"
                chmod +x "validate-env.sh"
                if ! "./validate-env.sh"; then
                    print_error "Environment validation failed"
                    cd "$SCRIPT_DIR"
                    exit 1
                fi
                cd "$SCRIPT_DIR"
            fi
            ;;
        "docker")
            if [ ! -f "$DOCKER_DIR/server/Dockerfile" ]; then
                print_error "server/Dockerfile not found in docker directory"
                exit 1
            fi
            ;;
    esac
}

# Centralized directory creation
create_all_directories() {
    print_step "Creating required directories"

    local directories=(
        "data/minio/data"
        "data/recorder/data"
        "data/redis/data"
        "data/controller/logs"
        "server"
        "recorder/scripts"
        "recorder/utils"
    )

    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
    done

    print_success "Directories created successfully"
}

# Centralized configuration management
manage_configuration() {
    local action="$1"

    case "$action" in
        "extract")
            print_step "Extracting OpenVidu configuration"

            # Extract IMAGE_TAG
            if grep -q "openvidu/openvidu-server:" "$OPENVIDU_PATH/docker-compose.yml"; then
                DETECTED_IMAGE_TAG=$(grep "openvidu/openvidu-server:" "$OPENVIDU_PATH/docker-compose.yml" | head -1 | sed -n 's/.*openvidu\/openvidu-server:\([^[:space:]]*\).*/\1/p')
                if [ -n "$DETECTED_IMAGE_TAG" ]; then
                    print_info "Detected IMAGE_TAG: $DETECTED_IMAGE_TAG"
                else
                    DETECTED_IMAGE_TAG="2.31.0"
                    print_info "Could not extract IMAGE_TAG, using default: $DETECTED_IMAGE_TAG"
                fi
            else
                DETECTED_IMAGE_TAG="2.31.0"
                print_info "OpenVidu server image not found, using default: $DETECTED_IMAGE_TAG"
            fi

            # Extract OPENVIDU_RECORDING_PATH
            if grep -q "^OPENVIDU_RECORDING_PATH=" "$OPENVIDU_PATH/.env"; then
                DETECTED_RECORDING_PATH=$(grep "^OPENVIDU_RECORDING_PATH=" "$OPENVIDU_PATH/.env" | cut -d'=' -f2)
                print_info "Detected OPENVIDU_RECORDING_PATH: $DETECTED_RECORDING_PATH"
            else
                DETECTED_RECORDING_PATH="/opt/openvidu/recordings"
                print_info "OPENVIDU_RECORDING_PATH not found, using default: $DETECTED_RECORDING_PATH"
            fi

            # Extract domain for webhook configuration
            if grep -q "^DOMAIN_OR_PUBLIC_IP=" "$OPENVIDU_PATH/.env"; then
                OPENVIDU_DOMAIN=$(grep "^DOMAIN_OR_PUBLIC_IP=" "$OPENVIDU_PATH/.env" | cut -d'=' -f2)
                print_info "OpenVidu Domain: $OPENVIDU_DOMAIN"
            fi
            ;;
        "generate")
            print_step "Generating .env configuration"

            cd "$SCRIPT_DIR"

            if [ ! -f ".env_template" ]; then
                print_error ".env_template not found"
                create_default_template
            fi

            if [ -f ".env" ]; then
                print_info "Backing up existing .env file"
                cp ".env" ".env.backup.$(date +%Y%m%d_%H%M%S)"
            fi

            cp ".env_template" ".env"

            # Calculate derived values
            local s3_endpoint="http://${PRIVATE_IP}:${MINIO_PORT}"
            local webhook_endpoint="http://${PRIVATE_IP}:${CONTROLLER_PORT}/openvidu/webhook"

            # Update configuration values
            update_env_value "HA_AWS_S3_SERVICE_ENDPOINT" "$s3_endpoint"
            update_env_value "HA_CONTROLLER_HOST" "$PRIVATE_IP"
            update_env_value "HA_CONTROLLER_PORT" "$CONTROLLER_PORT"
            update_env_value "MINIO_API_PORT" "$MINIO_PORT"
            update_env_value "IMAGE_TAG" "$DETECTED_IMAGE_TAG"
            update_env_value "OPENVIDU_RECORDING_PATH" "$DETECTED_RECORDING_PATH"
            update_env_value "OPENVIDU_WEBHOOK_ENDPOINT" "$webhook_endpoint"

            print_success "Configuration file generated successfully"
            ;;
        "copy")
            print_step "Copying .env to recording path"

            if [ ! -d "$DETECTED_RECORDING_PATH" ]; then
                print_info "Creating recording path: $DETECTED_RECORDING_PATH"
                sudo mkdir -p "$DETECTED_RECORDING_PATH" 2>/dev/null || mkdir -p "$DETECTED_RECORDING_PATH" 2>/dev/null || {
                    print_error "Cannot create recording path: $DETECTED_RECORDING_PATH"
                    return 1
                }
            fi

            if sudo cp ".env" "$DETECTED_RECORDING_PATH/.env" 2>/dev/null || cp ".env" "$DETECTED_RECORDING_PATH/.env" 2>/dev/null; then
                print_success "Configuration copied to: $DETECTED_RECORDING_PATH/.env"
                sudo chmod 644 "$DETECTED_RECORDING_PATH/.env" 2>/dev/null || chmod 644 "$DETECTED_RECORDING_PATH/.env" 2>/dev/null
            else
                print_error "Failed to copy .env to recording path"
                return 1
            fi
            ;;
    esac
}

# Centralized Docker operations
manage_docker() {
    local action="$1"
    local target="${2:-all}"

    export IMAGE_TAG="$DETECTED_IMAGE_TAG"

    case "$action" in
        "build")
            case "$target" in
                "ha-controller")
                    print_step "Building HA Controller"
                    cd "$DOCKER_DIR"
                    docker compose build ov-recorder-ha-controller
                    cd "$SCRIPT_DIR"
                    print_success "HA Controller built successfully"
                    ;;
                "recording")
                    print_step "Building OpenVidu recording image"

                    local image_name="openvidu/openvidu-recording"
                    local full_image_name="${image_name}:${DETECTED_IMAGE_TAG}"
                    local old_maintainer="OpenVidu info@openvidu.io"
                    local new_maintainer="NaevaTec-OpenVidu eiglesia@openvidu.io"

                    # Check and remove old image if needed
                    if docker images "${full_image_name}" --format "table {{.Repository}}:{{.Tag}}" | grep -q "${full_image_name}"; then
                        local maintainer=$(docker inspect "${full_image_name}" --format='{{index .Config.Labels "maintainer"}}' 2>/dev/null || echo "")

                        if [ "$maintainer" = "$old_maintainer" ] || [ "$maintainer" != "$new_maintainer" ]; then
                            print_info "Removing old image..."
                            docker rmi "${full_image_name}"
                        fi
                    fi

                    cd "$DOCKER_DIR"
                    docker compose build openvidu-recording
                    cd "$SCRIPT_DIR"

                    # Verify maintainer label
                    local new_maintainer_check=$(docker inspect "${full_image_name}" --format='{{index .Config.Labels "maintainer"}}' 2>/dev/null || echo "")
                    if [ "$new_maintainer_check" = "$new_maintainer" ]; then
                        print_success "New image built successfully"
                    else
                        print_error "New image has incorrect maintainer label"
                        exit 1
                    fi
                    ;;
                "all")
                    manage_docker "build" "ha-controller"
                    manage_docker "build" "recording"
                    ;;
            esac
            ;;
        "start")
            case "$target" in
                "infrastructure")
                    print_step "Starting infrastructure services"
                    cd "$DOCKER_DIR"
                    docker compose up -d minio minio-mc redis

                    # Wait for MinIO setup
                    print_info "Waiting for MinIO setup..."
                    wait_for_service_completion "minio-mc" 120
                    cd "$SCRIPT_DIR"
                    ;;
                "ha-controller")
                    print_step "Starting HA Controller"
                    cd "$DOCKER_DIR"
                    docker compose --profile ha-controller up -d ov-recorder-ha-controller
                    cd "$SCRIPT_DIR"

                    if wait_for_service_health "ov-recorder-ha-controller" 90; then
                        print_success "HA Controller started successfully"
                    else
                        print_error "HA Controller failed to start"
                        exit 1
                    fi
                    ;;
                "all")
                    manage_docker "start" "infrastructure"
                    manage_docker "start" "ha-controller"
                    ;;
            esac
            ;;
    esac
}

# Centralized service monitoring
wait_for_service_completion() {
    local container_name="$1"
    local timeout="${2:-60}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if mc_status=$(docker compose ps -a "$container_name" --format "{{.State}}" 2>/dev/null); then
            case "$mc_status" in
                "exited")
                    local exit_code=$(docker compose ps -a "$container_name" --format "{{.ExitCode}}" 2>/dev/null || echo "1")
                    return $exit_code
                    ;;
            esac
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    return 1
}

wait_for_service_health() {
    local container_name="$1"
    local timeout="${2:-60}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "no-healthcheck")

            if [ "$health_status" = "healthy" ] || [ "$health_status" = "no-healthcheck" ]; then
                return 0
            fi
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    return 1
}

# Network configuration
configure_network() {
    print_step "Interactive Configuration"

    echo ""
    echo "Please provide configuration details (Press Enter for defaults):"
    echo ""

    # OpenVidu installation path
    if [ "$AUTO_MODE" = "false" ]; then
        echo -n "OpenVidu installation path [$OPENVIDU_PATH]: "
        read -r input_path
        if [ -n "$input_path" ]; then
            OPENVIDU_PATH="$input_path"
        fi
    fi
    print_info "Using OpenVidu path: $OPENVIDU_PATH"

    # Private IP detection and configuration
    local calculated_ip=$(get_private_ip)
    print_info "Detected private IP: $calculated_ip"

    if [ "$AUTO_MODE" = "false" ]; then
        echo -n "Private IP address [$calculated_ip]: "
        read -r input_ip
        PRIVATE_IP="${input_ip:-$calculated_ip}"
    else
        PRIVATE_IP="$calculated_ip"
    fi
    print_info "Using private IP: $PRIVATE_IP"

    # Port configuration
    local default_minio_port="9000"
    local default_controller_port="15443"

    if [ "$AUTO_MODE" = "false" ]; then
        echo -n "MinIO API port [$default_minio_port]: "
        read -r input_minio_port
        MINIO_PORT="${input_minio_port:-$default_minio_port}"

        echo -n "HA Controller port [$default_controller_port]: "
        read -r input_controller_port
        CONTROLLER_PORT="${input_controller_port:-$default_controller_port}"
    else
        MINIO_PORT="$default_minio_port"
        CONTROLLER_PORT="$default_controller_port"
    fi

    print_info "Using MinIO port: $MINIO_PORT"
    print_info "Using Controller port: $CONTROLLER_PORT"
    print_success "Configuration completed"
}

# Private IP detection
get_private_ip() {
    local private_ip=""

    if command -v hostname >/dev/null 2>&1; then
        private_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    if [ -z "$private_ip" ] && command -v ip >/dev/null 2>&1; then
        private_ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    fi

    if [ -z "$private_ip" ] && command -v ifconfig >/dev/null 2>&1; then
        private_ip=$(ifconfig | grep -E "inet.*broadcast" | awk '{print $2}' | head -1)
    fi

    echo "${private_ip:-localhost}"
}

# Utility functions
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

create_default_template() {
    cat > ".env_template" << 'EOF'
# ov2-ha-recorder configuration template
HA_RECORDING_STORAGE=s3
CHUNK_FOLDER=/chunks
CHUNK_TIME_SIZE=10
HA_AWS_S3_SERVICE_ENDPOINT=http://localhost:9000
HA_AWS_S3_BUCKET=ov-recordings
HA_AWS_ACCESS_KEY=naeva_minio
HA_AWS_SECRET_KEY=N43v4t3c_M1n10
MINIO_API_PORT=9000
MINIO_CONSOLE_PORT=9001
HA_CONTROLLER_HOST=localhost
HA_CONTROLLER_PORT=15443
HA_CONTROLLER_USERNAME=naeva_admin
HA_CONTROLLER_PASSWORD=N43v4t3c_M4n4g3r
HEARTBEAT_INTERVAL=10
HA_SESSION_CLEANUP_INTERVAL=30
HA_FAILOVER_CHECK_INTERVAL=15
HA_SESSION_MAX_INACTIVE_TIME=600
HA_MAX_MISSED_HEARTBEATS=3
OPENVIDU_WEBHOOK=true
OPENVIDU_WEBHOOK_ENDPOINT=
IMAGE_TAG=2.31.0
IMAGE_NAME=openvidu/openvidu-recording
OPENVIDU_RECORDING_PATH=/opt/openvidu/recordings
EOF
}

# OpenVidu webhook configuration
configure_openvidu_integration() {
    print_step "Configuring OpenVidu webhook integration"

    local webhook_url="http://${PRIVATE_IP}:${CONTROLLER_PORT}/openvidu/webhook"

    echo ""
    print_info "OpenVidu Integration Configuration Required:"
    echo "   Edit your OpenVidu .env file: $OPENVIDU_PATH/.env"
    echo "   Add these lines:"
    echo ""
    echo "      OPENVIDU_WEBHOOK=true"
    echo "      OPENVIDU_WEBHOOK_ENDPOINT=$webhook_url"
    echo ""
    echo "   Then restart OpenVidu: cd $OPENVIDU_PATH && docker-compose restart"
    echo ""

    if [ "$AUTO_MODE" = "false" ]; then
        echo "Would you like me to automatically configure OpenVidu? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            configure_openvidu_automatically "$webhook_url"
        fi
    fi
}

configure_openvidu_automatically() {
    local webhook_url="$1"

    cp "$OPENVIDU_PATH/.env" "$OPENVIDU_PATH/.env.backup.$(date +%Y%m%d_%H%M%S)"

    if grep -q "^OPENVIDU_WEBHOOK=" "$OPENVIDU_PATH/.env"; then
        sed -i.bak "s|^OPENVIDU_WEBHOOK=.*|OPENVIDU_WEBHOOK=true|" "$OPENVIDU_PATH/.env"
    else
        echo "OPENVIDU_WEBHOOK=true" >> "$OPENVIDU_PATH/.env"
    fi

    if grep -q "^OPENVIDU_WEBHOOK_ENDPOINT=" "$OPENVIDU_PATH/.env"; then
        sed -i.bak "s|^OPENVIDU_WEBHOOK_ENDPOINT=.*|OPENVIDU_WEBHOOK_ENDPOINT=$webhook_url|" "$OPENVIDU_PATH/.env"
    else
        echo "OPENVIDU_WEBHOOK_ENDPOINT=$webhook_url" >> "$OPENVIDU_PATH/.env"
    fi

    print_success "OpenVidu configuration updated"
}

# Summary and reminders
show_installation_summary() {
    print_step "Installation Summary"

    echo ""
    echo "Installation completed successfully!"
    echo "====================================="
    echo "   OpenVidu Path: $OPENVIDU_PATH"
    echo "   Image Tag: $DETECTED_IMAGE_TAG"
    echo "   Recording Path: $DETECTED_RECORDING_PATH"
    echo "   Private IP: $PRIVATE_IP"
    echo ""
    echo "Service URLs:"
    echo "   HA Controller API: http://${PRIVATE_IP}:${CONTROLLER_PORT}/api/sessions"
    echo "   HA Controller Health: http://${PRIVATE_IP}:${CONTROLLER_PORT}/actuator/health"
    echo "   MinIO Console: http://${PRIVATE_IP}:9001"
    echo ""
    echo "Management Commands:"
    echo "   Check services: cd docker && ./ov2-ha-recorder.sh status"
    echo "   View logs: cd docker && ./ov2-ha-recorder.sh logs"
    echo "   Test API: cd docker && ./ov2-ha-recorder.sh test-api"
}

show_configuration_reminders() {
    echo ""
    echo "============================================================="
    echo "                    IMPORTANT REMINDERS"
    echo "============================================================="
    echo ""
    echo "1. CONFIGURE OPENVIDU WEBHOOK INTEGRATION:"
    echo "   Edit: $OPENVIDU_PATH/.env"
    echo "   Add: OPENVIDU_WEBHOOK=true"
    echo "   Add: OPENVIDU_WEBHOOK_ENDPOINT=http://${PRIVATE_IP}:${CONTROLLER_PORT}/openvidu/webhook"
    echo "   Restart: cd $OPENVIDU_PATH && docker-compose restart"
    echo ""
    echo "2. CONFIGURATION SYNCHRONIZATION:"
    echo "   When modifying .env, always copy to: $DETECTED_RECORDING_PATH/.env"
    echo "   Command: cp .env $DETECTED_RECORDING_PATH/.env"
    echo ""
    echo "   WHY? Recording containers read from the recording path."
    echo ""
}

# Main installation workflow
main() {
    print_header "$OV2_HA_NAME Installation"
    print_info "Working directory: $SCRIPT_DIR"

    cd "$SCRIPT_DIR"

    # Step 1: Network and path configuration
    configure_network

    # Step 2: Validate OpenVidu installation
    validate_requirements "openvidu"

    # Step 3: Extract OpenVidu configuration
    manage_configuration "extract"

    # Step 4: Generate HA configuration
    manage_configuration "generate"

    # Step 5: Copy configuration to recording path
    manage_configuration "copy"

    # Step 6: Create directories and validate environment
    create_all_directories
    validate_requirements "environment"
    validate_requirements "docker"

    # Step 7: Build Docker images
    manage_docker "build" "all"

    # Step 8: Start services
    manage_docker "start" "all"

    # Step 9: Configure OpenVidu integration
    configure_openvidu_integration

    # Step 10: Show summary and reminders
    show_installation_summary
    show_configuration_reminders

    echo ""
    print_success "Installation process completed successfully!"
    print_info "Services are running. Use 'cd docker && ./ov2-ha-recorder.sh stop' to stop."
}

# Show usage if help requested
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: $0 [--auto] [OPENVIDU_PATH]"
    echo ""
    echo "Options:"
    echo "  --auto           Run in non-interactive mode with defaults"
    echo "  OPENVIDU_PATH    Path to OpenVidu installation (default: $DEFAULT_OPENVIDU_PATH)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Interactive installation"
    echo "  $0 /opt/openvidu             # Interactive with custom path"
    echo "  $0 --auto                    # Non-interactive with defaults"
    echo "  $0 --auto /custom/openvidu   # Non-interactive with custom path"
    exit 0
fi

# Execute main function
main
