# OpenVidu2 HA Recorder

[![Java](https://img.shields.io/badge/Java-21-orange.svg)](https://openjdk.java.net/projects/jdk/21/)
[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-3.5.4-brightgreen.svg)](https://spring.io/projects/spring-boot)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue.svg)](https://docs.docker.com/compose/)
[![Redis](https://img.shields.io/badge/Redis-7-red.svg)](https://redis.io/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A production-ready **High Availability Recorder** for OpenVidu that provides intelligent failover, real-time monitoring, and centralized session management. Built with SpringBoot 3.5.4 and Java 21, this solution enhances OpenVidu's recording capabilities with Docker-in-Docker container management and comprehensive observability.

## 📋 Table of Contents

- [Features](#-features)
- [Architecture](#-architecture)
- [Quick Start](#-quick-start)
- [Installation](#-installation)
- [Configuration](#-configuration)
- [API Reference](#-api-reference)
- [Monitoring & Observability](#-monitoring--observability)
- [Troubleshooting](#-troubleshooting)
- [Production Deployment](#-production-deployment)
- [Security](#-security)
- [Performance Tuning](#-performance-tuning)
- [Contributing](#-contributing)
- [License](#-license)

## 🚀 Features

### Core Capabilities
- **🔄 Intelligent Failover**: Automatic backup container deployment when recordings fail
- **📊 Real-time Monitoring**: Chunk-level progress tracking with heartbeat monitoring
- **🎛️ Centralized Management**: SpringBoot REST API with Redis persistence
- **🔗 Webhook Relay**: High-performance async webhook forwarding
- **🐳 Docker-in-Docker**: Seamless container lifecycle management
- **📈 Production Features**: Comprehensive metrics, health checks, and observability

### Technical Highlights
- **Session Management**: Complete CRUD operations with Redis storage
- **Heartbeat Monitoring**: 30-second intervals with chunk tracking
- **Failover Detection**: Timeout-based and stuck-chunk detection
- **Container Management**: Full Docker-in-Docker lifecycle
- **Graceful Shutdown**: OpenVidu-compatible container termination
- **S3 Integration**: Chunk upload/download and cleanup
- **Security**: HTTP Basic Auth with profile-based configurations

## 🏗️ Architecture

```mermaid
graph TB
    subgraph "OpenVidu HA Recorder System"
        subgraph "HA Controller"
            API[REST API<br/>SpringBoot 3.5.4]
            SessionMgr[Session Manager]
            FailoverMgr[Failover Manager]
            WebhookRelay[Webhook Relay]
            ContainerMgr[Container Manager]
        end
        
        subgraph "Storage Layer"
            Redis[(Redis<br/>Session Data)]
            S3[(MinIO/S3<br/>Recordings)]
        end
        
        subgraph "Recording Containers"
            Primary[Primary Container<br/>OpenVidu Recorder]
            Backup[Backup Container<br/>Failover Instance]
        end
        
        subgraph "External Systems"
            OpenVidu[OpenVidu Server]
            Client[Client Application]
        end
    end
    
    Client -->|Start/Stop Recording| API
    API --> SessionMgr
    SessionMgr --> Redis
    API --> FailoverMgr
    FailoverMgr --> ContainerMgr
    ContainerMgr -->|Docker API| Primary
    ContainerMgr -->|Failover| Backup
    Primary -->|Heartbeat| API
    Backup -->|Heartbeat| API
    Primary --> S3
    Backup --> S3
    OpenVidu -->|Webhooks| WebhookRelay
    WebhookRelay --> Client
```

### Component Architecture

#### 1. HA Controller (SpringBoot Application)
- **REST API**: Session management endpoints (`/api/sessions/*`)
- **Failover Management**: Automatic container recovery (`/api/failover/*`)
- **Webhook Relay**: High-performance async forwarding (`/openvidu/webhook`)
- **Docker Integration**: Container lifecycle management
- **Data Persistence**: Redis-backed session storage

#### 2. Enhanced Recording Container
- **Custom Image**: OpenVidu recorder with HA integration
- **Registration Scripts**: Automatic session registration
- **Heartbeat System**: Progress monitoring and health reporting
- **Recovery Mode**: Failover container capabilities
- **Chunk Tracking**: Real-time recording progress

#### 3. Supporting Infrastructure
- **Redis**: Session data persistence and caching
- **MinIO/S3**: Scalable recording storage
- **Docker Compose**: Development orchestration

## ⚡ Quick Start

### Prerequisites
```bash
# Required software
- Docker 20.10+
- Docker Compose 2.0+
- Java 21 (for development)
- Existing OpenVidu installation
- Git
```

### 1. Clone and Install
```bash
git clone https://github.com/naevatec/ov2-ha-recorder.git
cd ov2-ha-recorder

# Run interactive installation
./ov2-ha-recorder-install.sh

# Or non-interactive with defaults
./ov2-ha-recorder-install.sh --auto
```

The installer will:
- Auto-detect your OpenVidu installation and version
- Prompt for network configuration (private IP, ports)
- Generate configuration from template
- Build and start all services
- Copy configuration to recording path
- Provide OpenVidu webhook setup instructions

### 2. Configure OpenVidu Webhook (Required)
Edit your OpenVidu `.env` file:
```bash
# Add these lines to your OpenVidu .env
OPENVIDU_WEBHOOK=true  
OPENVIDU_WEBHOOK_ENDPOINT=http://YOUR_PRIVATE_IP:15443/openvidu/webhook

# Restart OpenVidu services
cd /opt/openvidu && docker-compose restart
```

### 3. Verify Installation
```bash
# Change to operations directory
cd docker

# Check service status
./ov2-ha-recorder.sh status

# Test API connectivity
./ov2-ha-recorder.sh test-api
```

### 4. Daily Operations
```bash
# All operations run from docker directory
cd docker

# Service management
./ov2-ha-recorder.sh start    # Start services
./ov2-ha-recorder.sh stop     # Stop services  
./ov2-ha-recorder.sh restart  # Restart services
./ov2-ha-recorder.sh status   # Show detailed status

# Monitoring and logs
./ov2-ha-recorder.sh logs              # View all logs
./ov2-ha-recorder.sh logs ha-controller # Specific service logs
./ov2-ha-recorder.sh monitor           # Real-time monitoring

# Testing and maintenance
./ov2-ha-recorder.sh test-recording    # Test complete workflow
./ov2-ha-recorder.sh backup           # Backup configuration
./ov2-ha-recorder.sh clean            # Cleanup old resources
```

## 📦 Installation

### Automated Installation (Recommended)

The automated installer handles the complete setup process:

#### 1. Interactive Installation
```bash
git clone https://github.com/naevatec/ov2-ha-recorder.git
cd ov2-ha-recorder

# Run interactive installer
./ov2-ha-recorder-install.sh

# Or with custom OpenVidu path
./ov2-ha-recorder-install.sh /custom/openvidu/path
```

The installer will:
- Detect your OpenVidu installation and extract configuration
- Prompt for private IP and port settings
- Generate `.env` from `.env_template` with your specific values
- Build Docker images (HA Controller and enhanced OpenVidu recorder)
- Copy configuration to OpenVidu recording path
- Start all services
- Provide OpenVidu webhook configuration guidance

#### 2. Non-Interactive Installation
```bash
# Use defaults with auto-detected settings
./ov2-ha-recorder-install.sh --auto

# Non-interactive with custom OpenVidu path
./ov2-ha-recorder-install.sh --auto /custom/openvidu/path
```

### Configuration Template System

The system uses `.env_template` to generate environment-specific configuration:

#### Template Structure
```bash
# .env_template (included in repository)
HA_AWS_S3_SERVICE_ENDPOINT=http://localhost:9000    # Auto-filled during install
HA_CONTROLLER_HOST=localhost                        # Auto-filled with private IP
HA_CONTROLLER_PORT=15443                            # Configurable during install
IMAGE_TAG=2.31.0                                    # Auto-detected from OpenVidu
OPENVIDU_RECORDING_PATH=/opt/openvidu/recordings    # Auto-detected from OpenVidu
```

#### Generated Configuration
During installation, the system:
1. **Calculates private IP** using multiple detection methods
2. **Extracts OpenVidu settings** from existing installation
3. **Prompts for ports** (MinIO, HA Controller)
4. **Generates .env** with environment-specific values
5. **Copies to recording path** for container access

### Manual Installation (Advanced)

For development or custom deployments:

#### 1. Prepare Configuration
```bash
# Copy template and customize
cp .env_template .env

# Edit .env with your settings
vi .env
```

Key settings to configure:
```bash
# Network configuration
HA_CONTROLLER_HOST=YOUR_PRIVATE_IP
HA_CONTROLLER_PORT=15443
HA_AWS_S3_SERVICE_ENDPOINT=http://YOUR_PRIVATE_IP:9000

# OpenVidu integration
IMAGE_TAG=2.31.0  # Match your OpenVidu version
OPENVIDU_RECORDING_PATH=/opt/openvidu/recordings
OPENVIDU_WEBHOOK_ENDPOINT=http://YOUR_PRIVATE_IP:15443/openvidu/webhook
```

Basic configuration for working:
```bash 
# Storage Configuration
HA_RECORDING_STORAGE=local           # 'local' or 's3'
CHUNK_FOLDER=/local-chunks           # Chunk storage folder
CHUNK_TIME_SIZE=20                   # Chunk duration in seconds

# S3/MinIO Configuration
HA_AWS_S3_SERVICE_ENDPOINT=http://172.31.0.96:9000  # MinIO endpoint
HA_AWS_S3_BUCKET=ov-recordings                      # S3 bucket name
HA_AWS_ACCESS_KEY=naeva_minio                       # MinIO credentials
HA_AWS_SECRET_KEY=N43v4t3c_M1n10                    # MinIO credentials
MINIO_API_PORT=9000                                 # MinIO API port
MINIO_CONSOLE_PORT=9001                             # MinIO console port

# HA Controller Configuration
HA_CONTROLLER_HOST=172.31.22.206        # HA Controller IP
HA_CONTROLLER_PORT=15443                # HA Controller external port
HA_CONTROLLER_USERNAME=naeva_admin      # HA Controller username
HA_CONTROLLER_PASSWORD=N43v4t3c_M4n4g3r # HA Controller password
HEARTBEAT_INTERVAL=10                   # The time the HA will use in seconds for checking heartbeats
HA_MAX_MISSED_HEARTBEATS=3              # For Failover, the maximum heartbeats missed until consider the recorder node as down
HA_FAILOVER_CHECK_INTERVAL=15           # Interval in seconds to check the status of recorder nodes
HA_SESSION_CLEANUP_INTERVAL=30          # Session review frequency in seconds
HA_SESSION_MAX_INACTIVE_TIME=600        # Max time before session cleanup in seconds

# Webhook relay configuration. Necessary if you already have a webhook configuration in your OpenVidu installation
OPENVIDU_WEBHOOK=true                                 # Enable/disable OpenVidu webhook relay functionality. When true, the controller will accept webhook notifications from OpenVidu
OPENVIDU_WEBHOOK_ENDPOINT=https://{your-web-hook-url} # Target endpoint URL for webhook relay. All incoming OpenVidu webhook notifications will be forwarded to this URL

# Docker Configuration
IMAGE_TAG=2.31.0                                  # OpenVidu image tag
IMAGE_NAME=openvidu/openvidu-recording            # OpenVidu recording image name
OPENVIDU_RECORDING_PATH=/opt/openvidu/recordings  # OpenVidu recordings path. MUST POINT TO YOUR OPENVIDU INSTALLATION

# Swagger Configuration (Profile-based)
SPRING_PROFILES_ACTIVE=dev          # 'dev', 'test', or 'prod'
SWAGGER_ENABLED=true                # Enable/disable Swagger (auto-disabled in prod)
SWAGGER_UI_ENABLED=true             # Enable/disable Swagger UI
```

#### 2. Build Services
```bash
cd docker
export IMAGE_TAG=2.31.0  # Match your OpenVidu version

# Build HA Controller
docker compose build ov-recorder-ha-controller

# Build Enhanced Recording Container
docker compose build openvidu-recording
```

#### 3. Start Infrastructure
```bash
cd docker

# Start storage and database
docker compose up -d minio minio-mc redis

# Wait for MinIO setup to complete
docker compose logs -f minio-mc  # Wait for "exited" status

# Start HA Controller
docker compose --profile ha-controller up -d ov-recorder-ha-controller
```

#### 4. Copy Configuration
```bash
# Copy .env to recording path (required for containers)
sudo cp .env /opt/openvidu/recordings/.env
sudo chown openvidu:openvidu /opt/openvidu/recordings/.env
```

## ⚙️ Configuration

### Configuration System

OpenVidu2 HA Recorder uses a template-based configuration system:

#### Configuration Files
- **`.env_template`**: Template file included in repository (main directory)
- **`.env`**: Generated during installation (main directory) 
- **`{OPENVIDU_RECORDING_PATH}/.env`**: Copy for recording containers (auto-created)

#### Template-Based Generation

The installer automatically generates `.env` from `.env_template` with environment-specific values:

```bash
# Auto-detected from OpenVidu installation
IMAGE_TAG=2.31.0                                    # From docker-compose.yml
OPENVIDU_RECORDING_PATH=/opt/openvidu/recordings    # From .env

# User-configured during installation
HA_CONTROLLER_HOST=192.168.1.100                   # Private IP
HA_CONTROLLER_PORT=15443                            # HA Controller port
MINIO_API_PORT=9000                                 # MinIO port

# Auto-calculated values  
HA_AWS_S3_SERVICE_ENDPOINT=http://192.168.1.100:9000
OPENVIDU_WEBHOOK_ENDPOINT=http://192.168.1.100:15443/openvidu/webhook
```

### Key Configuration Sections

#### Application Configuration
```yaml
# Core settings
HA_RECORDING_STORAGE=s3              # Storage mode: 'local' or 's3'
CHUNK_FOLDER=/chunks                 # Chunk storage path
CHUNK_TIME_SIZE=10                   # Chunk duration in seconds

# Docker configuration
IMAGE_TAG=2.31.0                     # OpenVidu version (auto-detected)
IMAGE_NAME=openvidu/openvidu-recording
OPENVIDU_RECORDING_PATH=/opt/openvidu/recordings    # Auto-detected
```

#### Network Configuration  
```yaml
# HA Controller (auto-configured)
HA_CONTROLLER_HOST=192.168.1.100     # Private IP (user-provided)
HA_CONTROLLER_PORT=15443             # API port (user-configurable)

# Authentication
HA_CONTROLLER_USERNAME=naeva_admin
HA_CONTROLLER_PASSWORD=N43v4t3c_M4n4g3r
```

#### S3/MinIO Configuration
```yaml
# Storage endpoint (auto-calculated)
HA_AWS_S3_SERVICE_ENDPOINT=http://192.168.1.100:9000
HA_AWS_S3_BUCKET=ov-recordings

# MinIO credentials
HA_AWS_ACCESS_KEY=naeva_minio
HA_AWS_SECRET_KEY=N43v4t3c_M1n10

# Ports (user-configurable)
MINIO_API_PORT=9000
MINIO_CONSOLE_PORT=9001
```

#### Timing Configuration
```yaml
# Heartbeat and monitoring intervals (seconds)
HEARTBEAT_INTERVAL=10                    # Recording container heartbeat frequency
HA_SESSION_CLEANUP_INTERVAL=30          # Session cleanup frequency  
HA_FAILOVER_CHECK_INTERVAL=15           # Failover detection frequency
HA_SESSION_MAX_INACTIVE_TIME=600        # Session timeout (10 minutes)
HA_MAX_MISSED_HEARTBEATS=3              # Failover trigger threshold
```

#### Webhook Configuration
```yaml
# Webhook relay (auto-configured)
OPENVIDU_WEBHOOK=true
OPENVIDU_WEBHOOK_ENDPOINT=http://192.168.1.100:15443/openvidu/webhook
```

### Configuration Synchronization

**Critical Requirement**: Recording containers read configuration from `{OPENVIDU_RECORDING_PATH}/.env`

#### Automatic Synchronization (Installation)
The installer automatically copies `.env` to the recording path:
```bash
cp .env /opt/openvidu/recordings/.env
chmod 644 /opt/openvidu/recordings/.env
```

#### Manual Synchronization (Required After Changes)
When you modify `.env`, you must copy it to the recording path:
```bash
# After editing .env
cp .env /opt/openvidu/recordings/.env

# Or using the operations script
cd docker
./ov2-ha-recorder.sh reconfigure
```

**Why This Is Required**: 
- Recording containers run with OpenVidu's recording path mounted
- They need access to HA Controller endpoints and credentials
- Configuration must be readable from the mounted volume

### Environment Variables Reference

| Variable | Description | Auto-Configured | Default |
|----------|-------------|-----------------|---------|
| `IMAGE_TAG` | OpenVidu version | ✅ (from OpenVidu) | `2.31.0` |
| `OPENVIDU_RECORDING_PATH` | Recording storage path | ✅ (from OpenVidu) | `/opt/openvidu/recordings` |
| `HA_CONTROLLER_HOST` | Controller private IP | ✅ (detected/prompted) | `localhost` |
| `HA_CONTROLLER_PORT` | Controller API port | ❌ (user prompt) | `15443` |
| `MINIO_API_PORT` | MinIO API port | ❌ (user prompt) | `9000` |
| `HA_AWS_S3_SERVICE_ENDPOINT` | S3 endpoint URL | ✅ (calculated) | - |
| `OPENVIDU_WEBHOOK_ENDPOINT` | Webhook URL | ✅ (calculated) | - |
| `OPENVIDU_WEBHOOK` | Enable webhooks | ✅ | `true` |
| `HA_RECORDING_STORAGE` | Storage backend | ❌ | `s3` |
| `HEARTBEAT_INTERVAL` | Heartbeat frequency | ❌ | `10` |
| `HA_FAILOVER_CHECK_INTERVAL` | Failover check frequency | ❌ | `15` |

## 📡 API Reference

### Authentication
All API endpoints require HTTP Basic Authentication:
```bash
Authorization: Basic base64(username:password)
```

Default credentials (configurable in .env):
- Username: `naeva_admin`
- Password: `N43v4t3c_M4n4g3r`

### Base URLs
```bash
# HA Controller API
http://YOUR_PRIVATE_IP:15443/api

# Health and metrics
http://YOUR_PRIVATE_IP:15443/actuator

# Webhook endpoint (OpenVidu)
http://YOUR_PRIVATE_IP:15443/openvidu/webhook
```

### Session Management

#### Create Recording Session
```http
POST /api/sessions
Content-Type: application/json
Authorization: Basic {credentials}

{
  "sessionId": "session-001",
  "recordingName": "meeting-recording",
  "outputMode": "COMPOSED",
  "recordingLayout": "BEST_FIT",
  "resolution": "1920x1080",
  "frameRate": 25,
  "shmSize": 2147483648,
  "customLayout": "",
  "recordingProperties": {
    "hasAudio": true,
    "hasVideo": true
  }
}
```

**Response:**
```json
{
  "sessionId": "session-001",
  "status": "STARTING",
  "containerId": "abc123def456",
  "createdAt": "2025-08-27T10:30:00Z",
  "recordingName": "meeting-recording",
  "outputMode": "COMPOSED",
  "recordingLayout": "BEST_FIT",
  "heartbeatData": {
    "lastHeartbeat": "2025-08-27T10:30:00Z",
    "chunksUploaded": 0,
    "currentChunkSize": 0,
    "isStuck": false
  }
}
```

#### Get Session Status
```http
GET /api/sessions/{sessionId}
Authorization: Basic {credentials}
```

**Response:**
```json
{
  "sessionId": "session-001",
  "status": "RECORDING",
  "containerId": "abc123def456",
  "createdAt": "2025-08-27T10:30:00Z",
  "lastModified": "2025-08-27T10:35:00Z",
  "recordingName": "meeting-recording",
  "outputMode": "COMPOSED",
  "recordingLayout": "BEST_FIT",
  "heartbeatData": {
    "lastHeartbeat": "2025-08-27T10:34:45Z",
    "chunksUploaded": 12,
    "currentChunkSize": 1048576,
    "isStuck": false,
    "failoverAttempts": 0
  },
  "containerInfo": {
    "containerId": "abc123def456",
    "containerName": "ovr_session-001_1724756200",
    "status": "RUNNING",
    "created": "2025-08-27T10:30:00Z"
  }
}
```

#### Stop Recording Session
```http
DELETE /api/sessions/{sessionId}
Authorization: Basic {credentials}
```

**Response:**
```json
{
  "sessionId": "session-001",
  "status": "STOPPING",
  "stoppedAt": "2025-08-27T10:45:00Z",
  "totalChunks": 15,
  "finalFileSize": 157286400
}
```

#### List All Sessions
```http
GET /api/sessions?status={status}&limit={limit}&offset={offset}
Authorization: Basic {credentials}
```

**Parameters:**
- `status` (optional): Filter by session status (`STARTING`, `RECORDING`, `STOPPING`, `FAILED`)
- `limit` (optional): Number of results to return (default: 50, max: 500)
- `offset` (optional): Number of results to skip (default: 0)

### Failover Management

#### Trigger Manual Failover
```http
POST /api/failover/{sessionId}
Authorization: Basic {credentials}
Content-Type: application/json

{
  "reason": "MANUAL_TRIGGER",
  "preserveProgress": true
}
```

#### Get Failover History
```http
GET /api/failover/{sessionId}/history
Authorization: Basic {credentials}
```

**Response:**
```json
{
  "sessionId": "session-001",
  "failoverEvents": [
    {
      "timestamp": "2025-08-27T10:32:15Z",
      "reason": "HEARTBEAT_TIMEOUT",
      "oldContainerId": "abc123def456",
      "newContainerId": "def456ghi789",
      "chunksRecovered": 8,
      "recoveryTimeMs": 15000
    }
  ],
  "totalFailovers": 1,
  "successfulRecoveries": 1
}
```

### Monitoring Endpoints

#### Health Check
```http
GET /actuator/health
```

**Response:**
```json
{
  "status": "UP",
  "components": {
    "redis": {
      "status": "UP",
      "details": {
        "version": "7.0.12"
      }
    },
    "docker": {
      "status": "UP",
      "details": {
        "version": "24.0.7"
      }
    },
    "s3": {
      "status": "UP",
      "details": {
        "endpoint": "http://192.168.1.100:9000",
        "bucket": "ov-recordings"
      }
    }
  }
}
```

#### Metrics
```http
GET /actuator/metrics
GET /actuator/prometheus
```

### API Testing Examples

#### Using curl
```bash
# Set variables
HA_HOST="192.168.1.100"
HA_PORT="15443"
AUTH="naeva_admin:N43v4t3c_M4n4g3r"

# Test health
curl -f "http://$HA_HOST:$HA_PORT/actuator/health"

# List sessions
curl -u "$AUTH" "http://$HA_HOST:$HA_PORT/api/sessions"

# Create test session
curl -u "$AUTH" -X POST "http://$HA_HOST:$HA_PORT/api/sessions" \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "test-session-001",
    "recordingName": "api-test",
    "outputMode": "COMPOSED",
    "recordingLayout": "BEST_FIT"
  }'

# Check session status
curl -u "$AUTH" "http://$HA_HOST:$HA_PORT/api/sessions/test-session-001"

# Stop session
curl -u "$AUTH" -X DELETE "http://$HA_HOST:$HA_PORT/api/sessions/test-session-001"
```

#### Using Operations Script
```bash
cd docker

# Comprehensive API testing
./ov2-ha-recorder.sh test-api

# Test complete recording workflow
./ov2-ha-recorder.sh test-recording

# Test S3 connectivity
./ov2-ha-recorder.sh test-s3
```

### Error Responses

All API endpoints return standardized error responses:

```json
{
  "timestamp": "2025-08-27T10:30:00Z",
  "status": 400,
  "error": "Bad Request",
  "message": "Session with ID 'invalid-session' not found",
  "path": "/api/sessions/invalid-session",
  "requestId": "req-12345"
}
```

**Common HTTP Status Codes:**
- `200 OK` - Successful request
- `201 Created` - Resource created successfully
- `400 Bad Request` - Invalid request parameters
- `401 Unauthorized` - Authentication required
- `404 Not Found` - Resource not found
- `409 Conflict` - Resource already exists
- `500 Internal Server Error` - Server error

### Webhook Integration

#### OpenVidu Webhook Configuration
Add to your OpenVidu `.env` file:
```bash
OPENVIDU_WEBHOOK=true
OPENVIDU_WEBHOOK_ENDPOINT=http://YOUR_PRIVATE_IP:15443/openvidu/webhook
```

#### Webhook Events Processed
- `recordingStatusChanged` - Recording state changes
- `sessionCreated` - New session started
- `sessionDestroyed` - Session ended
- `participantJoined` - User joined session
- `participantLeft` - User left session

The webhook relay forwards all events to your application's configured endpoint.

## 📊 Monitoring & Observability

### Health Checks

The application provides comprehensive health checks:

```bash
# Overall application health
curl http://localhost:8080/actuator/health

# Detailed health (requires authentication)
curl -u admin:password http://localhost:8080/actuator/health \
  -H "Accept: application/json"

# Specific component health
curl http://localhost:8080/actuator/health/redis
curl http://localhost:8080/actuator/health/docker
curl http://localhost:8080/actuator/health/s3
```

### Metrics Collection

#### Prometheus Integration
```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'ha-recorder'
    static_configs:
      - targets: ['ha-controller:8080']
    metrics_path: /actuator/prometheus
    scrape_interval: 10s
```

#### Key Metrics
```bash
# Recording session metrics
ha_recorder_sessions_active_total
ha_recorder_sessions_created_total
ha_recorder_sessions_failed_total
ha_recorder_failover_events_total

# Container metrics
ha_recorder_containers_running_total
ha_recorder_containers_failed_total
ha_recorder_container_lifecycle_duration_seconds

# Performance metrics
ha_recorder_api_request_duration_seconds
ha_recorder_webhook_processing_duration_seconds
ha_recorder_heartbeat_processing_duration_seconds

# Resource metrics
redis_connected_clients
docker_containers_running
jvm_memory_used_bytes
```

### Logging Configuration

#### Log Levels
```yaml
logging:
  level:
    com.openvidu.ha.controller: INFO
    com.openvidu.ha.service: INFO
    com.openvidu.ha.docker: DEBUG
    org.springframework.web: WARN
    org.springframework.security: WARN
```

#### Log Format
```bash
# Console output (development)
2025-08-27 10:30:15.123 INFO  [main] c.o.h.c.SessionController - Starting recording session: session-001

# File output (production)
2025-08-27T10:30:15.123Z [http-nio-8080-exec-1] INFO c.o.h.c.SessionController - Recording session created successfully [sessionId=session-001, containerId=abc123]
```

#### Structured Logging (JSON)
```json
{
  "timestamp": "2025-08-27T10:30:15.123Z",
  "level": "INFO",
  "thread": "http-nio-8080-exec-1",
  "logger": "com.openvidu.ha.controller.SessionController",
  "message": "Recording session created successfully",
  "sessionId": "session-001",
  "containerId": "abc123def456",
  "duration": 1250
}
```

### Grafana Dashboard

#### Panel Configuration
```json
{
  "dashboard": {
    "title": "OpenVidu HA Recorder",
    "panels": [
      {
        "title": "Active Recording Sessions",
        "type": "stat",
        "targets": [
          {
            "expr": "ha_recorder_sessions_active_total",
            "legendFormat": "Active Sessions"
          }
        ]
      },
      {
        "title": "Failover Events",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(ha_recorder_failover_events_total[5m])",
            "legendFormat": "Failovers per minute"
          }
        ]
      }
    ]
  }
}
```

### Alerting Rules

#### Prometheus Alerts
```yaml
groups:
  - name: ha-recorder
    rules:
      - alert: HighFailoverRate
        expr: rate(ha_recorder_failover_events_total[5m]) > 0.1
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High failover rate detected"
          description: "Failover rate is {{ $value }} events per second"

      - alert: RecordingSessionStuck
        expr: ha_recorder_stuck_sessions_total > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Recording session stuck"
          description: "{{ $value }} recording sessions are stuck"

      - alert: ContainerCreationFailed
        expr: rate(ha_recorder_containers_failed_total[5m]) > 0.05
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Container creation failures"
          description: "Container creation failure rate: {{ $value }}"
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Installation Problems

**Symptoms:**
- Installation script fails to detect OpenVidu
- Configuration generation errors
- Permission denied errors

**Diagnosis:**
```bash
# Check OpenVidu installation
ls -la /opt/openvidu/
ls -la /opt/openvidu/.env
ls -la /opt/openvidu/docker-compose.yml

# Check permissions
whoami
groups
```

**Solutions:**
```bash
# Ensure OpenVidu directory exists and is accessible
sudo chown -R $USER:$USER /opt/openvidu/ 

# Run installation with correct OpenVidu path
./ov2-ha-recorder-install.sh /correct/openvidu/path

# Run with sudo if permission issues persist
sudo ./ov2-ha-recorder-install.sh
```

#### 2. Container Creation Failures

**Symptoms:**
- Sessions stuck in `STARTING` status
- Docker API errors in logs
- Containers not appearing in `docker ps`

**Diagnosis:**
```bash
cd docker

# Check Docker daemon
sudo systemctl status docker

# Verify Docker socket permissions
ls -la /var/run/docker.sock

# Check available resources
docker system df

# Check service logs
./ov2-ha-recorder.sh logs ha-controller
```

**Solutions:**
```bash
# Fix Docker socket permissions
sudo chmod 666 /var/run/docker.sock

# Restart Docker service
sudo systemctl restart docker

# Clean up Docker resources
docker system prune -a

# Restart HA Recorder services
cd docker
./ov2-ha-recorder.sh restart
```

#### 3. Configuration Synchronization Issues

**Symptoms:**
- Recording containers can't connect to HA Controller
- Authentication failures from recording containers
- Environment variable errors in container logs

**Diagnosis:**
```bash
# Check if .env exists in recording path
ls -la /opt/openvidu/recordings/.env

# Compare configurations
diff .env /opt/openvidu/recordings/.env

# Check recording path permissions
ls -la /opt/openvidu/recordings/
```

**Solutions:**
```bash
# Copy configuration to recording path
cp .env /opt/openvidu/recordings/.env
sudo chown openvidu:openvidu /opt/openvidu/recordings/.env

# Or use operations script
cd docker
./ov2-ha-recorder.sh reconfigure

# Verify configuration
cd docker
./ov2-ha-recorder.sh config
```

#### 4. Redis Connection Issues

**Symptoms:**
- Session data not persisting
- `RedisConnectionException` in logs
- Authentication failures

**Diagnosis:**
```bash
cd docker

# Check Redis container
docker ps | grep redis
./ov2-ha-recorder.sh logs redis

# Test Redis connectivity
docker exec redis redis-cli ping

# Check Redis configuration
./ov2-ha-recorder.sh config | grep -i redis
```

**Solutions:**
```bash
cd docker

# Restart Redis
./ov2-ha-recorder.sh stop
./ov2-ha-recorder.sh start

# Check Redis logs for errors
./ov2-ha-recorder.sh logs redis

# Test Redis manually
docker exec -it redis redis-cli
> ping
> exit
```

#### 5. Failover Not Triggering

**Symptoms:**
- Stuck recording sessions
- No failover events in logs
- Heartbeat timeouts ignored

**Diagnosis:**
```bash
cd docker

# Check specific session status
./ov2-ha-recorder.sh test-api

# Review failover configuration
./ov2-ha-recorder.sh config | grep -i failover

# Check heartbeat logs
./ov2-ha-recorder.sh logs ha-controller | grep -i heartbeat
```

**Solutions:**
```bash
# Edit .env to adjust heartbeat sensitivity
HEARTBEAT_INTERVAL=10                    # More frequent checks
HA_FAILOVER_CHECK_INTERVAL=15           # More frequent failover checks
HA_MAX_MISSED_HEARTBEATS=2              # Trigger faster

# Copy updated config to recording path
cp .env /opt/openvidu/recordings/.env

# Restart services
cd docker
./ov2-ha-recorder.sh restart
```

#### 6. S3/MinIO Upload Failures

**Symptoms:**
- Chunks not uploaded
- S3 connection errors
- Recording files missing

**Diagnosis:**
```bash
cd docker

# Test S3 connectivity
./ov2-ha-recorder.sh test-s3

# Check MinIO logs
./ov2-ha-recorder.sh logs minio

# Check MinIO console
./ov2-ha-recorder.sh status
# Look for MinIO Console URL
```

**Solutions:**
```bash
cd docker

# Restart MinIO services
./ov2-ha-recorder.sh stop
./ov2-ha-recorder.sh start

# Check MinIO setup logs
./ov2-ha-recorder.sh logs minio-mc

# Verify S3 configuration in .env
./ov2-ha-recorder.sh config | grep -i s3
```

#### 7. OpenVidu Webhook Integration Issues

**Symptoms:**
- Webhook errors in OpenVidu logs
- Events not being relayed
- Connection refused errors

**Diagnosis:**
```bash
# Check OpenVidu .env configuration
grep -i webhook /opt/openvidu/.env

# Check HA Controller webhook endpoint
cd docker
./ov2-ha-recorder.sh test-api | grep -i webhook

# Check network connectivity
curl -f http://YOUR_PRIVATE_IP:15443/openvidu/webhook
```

**Solutions:**
```bash
# Update OpenVidu .env with correct endpoint
echo "OPENVIDU_WEBHOOK=true" >> /opt/openvidu/.env
echo "OPENVIDU_WEBHOOK_ENDPOINT=http://YOUR_PRIVATE_IP:15443/openvidu/webhook" >> /opt/openvidu/.env

# Restart OpenVidu
cd /opt/openvidu
docker-compose restart

# Verify HA Controller is accessible
cd docker
./ov2-ha-recorder.sh status
```

### Performance Issues

#### High CPU Usage
```bash
cd docker

# Monitor service resources
./ov2-ha-recorder.sh monitor

# Check specific container resources
docker stats $(docker ps -q)

# Review service logs for errors
./ov2-ha-recorder.sh logs
```

#### Memory Issues
```bash
cd docker

# Check memory usage
./ov2-ha-recorder.sh status

# Free up system resources
./ov2-ha-recorder.sh clean

# Restart services with fresh resources
./ov2-ha-recorder.sh restart
```

#### Network Connectivity Issues
```bash
# Test internal connectivity between containers
cd docker
docker exec ha-controller curl -I http://redis:6379
docker exec ha-controller curl -I http://minio:9000

# Check external connectivity
./ov2-ha-recorder.sh test-api
./ov2-ha-recorder.sh test-s3
```

### Debug Mode

#### Enable Detailed Logging
```bash
# Edit .env file
LOGGING_LEVEL_COM_OPENVIDU_HA=DEBUG
LOGGING_LEVEL_ROOT=DEBUG

# Copy to recording path
cp .env /opt/openvidu/recordings/.env

# Restart services
cd docker
./ov2-ha-recorder.sh restart

# Follow logs in real-time
./ov2-ha-recorder.sh logs-follow ha-controller
```

#### Diagnostic Commands
```bash
cd docker

# Comprehensive system check
./ov2-ha-recorder.sh validate

# Test all components
./ov2-ha-recorder.sh test-api
./ov2-ha-recorder.sh test-recording
./ov2-ha-recorder.sh test-s3

# Generate diagnostic report
./ov2-ha-recorder.sh status > diagnostic-report.txt
./ov2-ha-recorder.sh config >> diagnostic-report.txt
./ov2-ha-recorder.sh logs ha-controller >> diagnostic-report.txt
```

### Recovery Procedures

#### Complete System Recovery
```bash
# Stop all services
cd docker
./ov2-ha-recorder.sh stop

# Clean up resources
./ov2-ha-recorder.sh clean

# Regenerate configuration (if needed)
cd ..
./ov2-ha-recorder-install.sh --auto

# Or restart existing installation
cd docker
./ov2-ha-recorder.sh start
```

#### Session Recovery
```bash
cd docker

# Check stuck sessions
./ov2-ha-recorder.sh status

# Manually trigger failover for specific session
curl -u naeva_admin:N43v4t3c_M4n4g3r -X POST \
  "http://YOUR_PRIVATE_IP:15443/api/failover/SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{"reason": "MANUAL_RECOVERY", "preserveProgress": true}'
```

### Log Analysis

#### Important Log Patterns

**Successful Operations:**
```log
INFO c.o.h.s.SessionService - Creating recording session [sessionId=session-001]
INFO c.o.h.d.DockerService - Container created successfully [containerId=abc123]
INFO c.o.h.c.SessionController - Recording session started [sessionId=session-001]
```

**Failover Events:**
```log
WARN c.o.h.s.HeartbeatService - Heartbeat timeout [sessionId=session-001, timeout=120s]
INFO c.o.h.s.FailoverService - Initiating failover [sessionId=session-001, reason=TIMEOUT]
INFO c.o.h.d.DockerService - Creating backup container [sessionId=session-001]
```

**Critical Errors:**
```log
ERROR c.o.h.d.DockerService - Failed to create container [error=No space left on device]
ERROR c.o.h.s.SessionService - Session creation failed [sessionId=session-001, attempts=3]
FATAL c.o.h.s.FailoverService - Failover exhausted [maxRetries=3]
```

#### Log Commands
```bash
cd docker

# View recent errors
./ov2-ha-recorder.sh logs ha-controller | grep -i error | tail -20

# Monitor heartbeat activity
./ov2-ha-recorder.sh logs-follow ha-controller | grep -i heartbeat

# Check failover events
./ov2-ha-recorder.sh logs ha-controller | grep -i failover
```

## 🚀 Production Deployment

### Infrastructure Requirements

#### System Requirements
```yaml
Minimum:
  CPU: 4 cores
  RAM: 8 GB
  Storage: 100 GB SSD
  Network: 1 Gbps

Recommended:
  CPU: 8 cores
  RAM: 16 GB
  Storage: 500 GB NVMe SSD
  Network: 10 Gbps

Production Scale:
  CPU: 16+ cores
  RAM: 32+ GB
  Storage: 1+ TB NVMe SSD
  Network: 10+ Gbps
```

#### Docker Host Configuration
```bash
# Increase Docker daemon limits
# /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  },
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 5,
  "storage-driver": "overlay2"
}

# System limits
# /etc/security/limits.conf
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768

# Kernel parameters
# /etc/sysctl.conf
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
vm.max_map_count = 262144
fs.file-max = 2097152
```

### High Availability Setup

#### Multi-Node Deployment
```yaml
# docker/docker-compose.ha.yml
version: '3.8'
services:
  ha-controller:
    image: ov2-ha-recorder/ha-controller:latest
    deploy:
      replicas: 3
      placement:
        max_replicas_per_node: 1
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
      resources:
        limits:
          memory: 4G
          cpus: '2.0'
        reservations:
          memory: 2G
          cpus: '1.0'
    environment:
      - SPRING_PROFILES_ACTIVE=prod,ha
      - SPRING_REDIS_CLUSTER_NODES=redis-1:6379,redis-2:6379,redis-3:6379
      - SPRING_REDIS_PASSWORD=${REDIS_PASSWORD}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - ha-network
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:15443/actuator/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  redis-1:
    image: redis:7-alpine
    command: >
      redis-server
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --appendonly yes
      --requirepass ${REDIS_PASSWORD}
    deploy:
      placement:
        constraints: [node.labels.redis-node == 1]
    volumes:
      - redis-1-data:/data
    networks:
      - ha-network

  redis-2:
    image: redis:7-alpine
    command: >
      redis-server
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --appendonly yes
      --requirepass ${REDIS_PASSWORD}
    deploy:
      placement:
        constraints: [node.labels.redis-node == 2]
    volumes:
      - redis-2-data:/data
    networks:
      - ha-network

  redis-3:
    image: redis:7-alpine
    command: >
      redis-server
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --appendonly yes
      --requirepass ${REDIS_PASSWORD}
    deploy:
      placement:
        constraints: [node.labels.redis-node == 3]
    volumes:
      - redis-3-data:/data
    networks:
      - ha-network

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./nginx/ssl:/etc/nginx/ssl
    deploy:
      replicas: 2
      placement:
        max_replicas_per_node: 1
    networks:
      - ha-network
    depends_on:
      - ha-controller

networks:
  ha-network:
    driver: overlay
    attachable: true

volumes:
  redis-1-data:
  redis-2-data:
  redis-3-data:
```

#### Load Balancer Configuration
```nginx
# nginx/nginx.conf
upstream ha_controller {
    least_conn;
    server ha-controller-1:15443 max_fails=3 fail_timeout=30s;
    server ha-controller-2:15443 max_fails=3 fail_timeout=30s;
    server ha-controller-3:15443 max_fails=3 fail_timeout=30s;
}

server {
    listen 80;
    server_name ov2-ha-recorder.yourdomain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ov2-ha-recorder.yourdomain.com;
    
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location / {
        proxy_pass http://ha_controller;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
        
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
    }
    
    location /actuator/health {
        proxy_pass http://ha_controller;
        access_log off;
    }
}
```

### Backup and Recovery

#### Automated Backup Script
```bash
#!/bin/bash
# backup-system.sh

BACKUP_DIR="/backup/ov2-ha-recorder"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p $BACKUP_DIR

echo "Starting ov2-ha-recorder backup: $TIMESTAMP"

# Backup configuration
cd /path/to/ov2-ha-recorder
cp .env $BACKUP_DIR/env_${TIMESTAMP}
cp docker/.env $BACKUP_DIR/docker_env_${TIMESTAMP} 2>/dev/null || true

# Backup Redis data
cd docker
for container in $(docker ps --format "{{.Names}}" | grep redis); do
    echo "Backing up Redis: $container"
    docker exec $container redis-cli -a $REDIS_PASSWORD BGSAVE
    
    # Wait for background save
    while [ $(docker exec $container redis-cli -a $REDIS_PASSWORD LASTSAVE) -eq $(docker exec $container redis-cli -a $REDIS_PASSWORD LASTSAVE) ]; do
        sleep 1
    done
    
    # Copy dump file
    docker cp $container:/data/dump.rdb $BACKUP_DIR/${container}_${TIMESTAMP}.rdb
    gzip $BACKUP_DIR/${container}_${TIMESTAMP}.rdb
done

# Backup application logs
./ov2-ha-recorder.sh logs > $BACKUP_DIR/logs_${TIMESTAMP}.txt

# Create restore script
cat > $BACKUP_DIR/restore_${TIMESTAMP}.sh << EOF
#!/bin/bash
echo "Restoring ov2-ha-recorder backup from $TIMESTAMP"

# Stop services
cd /path/to/ov2-ha-recorder/docker
./ov2-ha-recorder.sh stop

# Restore configuration
cp $BACKUP_DIR/env_${TIMESTAMP} /path/to/ov2-ha-recorder/.env
cp $BACKUP_DIR/docker_env_${TIMESTAMP} /path/to/ov2-ha-recorder/docker/.env 2>/dev/null || true

# Restore Redis data (manual step - requires container recreation)
echo "Redis data available in: $BACKUP_DIR/*_${TIMESTAMP}.rdb.gz"

# Start services
./ov2-ha-recorder.sh start

echo "Restore completed. Check service status with: ./ov2-ha-recorder.sh status"
EOF

chmod +x $BACKUP_DIR/restore_${TIMESTAMP}.sh

# Cleanup old backups (keep last 14 days)
find $BACKUP_DIR -name "*" -mtime +14 -delete

echo "Backup completed: $BACKUP_DIR"
echo "To restore: $BACKUP_DIR/restore_${TIMESTAMP}.sh"
```

### Security Hardening

#### Container Security
```dockerfile
# Enhanced security Dockerfile for HA Controller
FROM openjdk:21-jre-slim

# Create non-root user
RUN groupadd -r harecorder && useradd -r -g harecorder harecorder

# Install security updates
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set security-focused JVM options
ENV JAVA_OPTS="-Xms2g -Xmx4g \
    -Djava.security.egd=file:/dev/./urandom \
    -Dfile.encoding=UTF-8 \
    -Djava.awt.headless=true \
    -XX:+UseG1GC \
    -XX:+DisableExplicitGC \
    -Djava.security.properties=/app/security.properties"

# Copy application with proper ownership
COPY --chown=harecorder:harecorder ha-controller.jar /app/
COPY --chown=harecorder:harecorder config/ /app/config/
COPY --chown=harecorder:harecorder security.properties /app/

# Switch to non-root user
USER harecorder

# Expose only necessary port
EXPOSE 15443

ENTRYPOINT ["java", "-jar", "/app/ha-controller.jar"]
```

#### Network Security
```bash
# Production firewall rules
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (restrict to specific IPs in production)
sudo ufw allow ssh

# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow HA Controller (internal networks only)
sudo ufw allow from 10.0.0.0/8 to any port 15443
sudo ufw allow from 172.16.0.0/12 to any port 15443
sudo ufw allow from 192.168.0.0/16 to any port 15443

# Allow Redis cluster (internal only)
sudo ufw allow from 10.0.0.0/8 to any port 6379
sudo ufw allow from 172.16.0.0/12 to any port 6379
sudo ufw allow from 192.168.0.0/16 to any port 6379

# Allow MinIO (internal only)
sudo ufw allow from 10.0.0.0/8 to any port 9000
sudo ufw allow from 172.16.0.0/12 to any port 9000
sudo ufw allow from 192.168.0.0/16 to any port 9000

sudo ufw enable
```

### Maintenance Procedures

#### Regular Maintenance Script
```bash
#!/bin/bash
# maintenance.sh - Run weekly

cd /path/to/ov2-ha-recorder/docker

echo "Starting weekly maintenance: $(date)"

# Update and restart services
./ov2-ha-recorder.sh update

# Clean up old resources
./ov2-ha-recorder.sh clean

# Run comprehensive tests
./ov2-ha-recorder.sh test-api
./ov2-ha-recorder.sh test-s3

# Generate health report
./ov2-ha-recorder.sh status > /var/log/ov2-ha-recorder-health.log

# Backup system
/backup/scripts/backup-system.sh

echo "Weekly maintenance completed: $(date)"
```

#### Monitoring Integration
```bash
# Add to crontab for automated monitoring
# crontab -e

# Health check every 5 minutes
*/5 * * * * /path/to/ov2-ha-recorder/docker/ov2-ha-recorder.sh status | grep -q "HEALTHY" || echo "HA Recorder health check failed" | mail -s "Alert: ov2-ha-recorder" admin@yourdomain.com

# Weekly maintenance
0 2 * * 0 /path/to/maintenance.sh

# Daily backup
0 1 * * * /backup/scripts/backup-system.sh
```

## 🔒 Security

### Authentication and Authorization

#### HTTP Basic Authentication
```yaml
# Security configuration
spring:
  security:
    user:
      name: ${HA_CONTROLLER_USERNAME}
      password: ${HA_CONTROLLER_PASSWORD}
      roles: ADMIN

ha:
  security:
    basic-auth:
      enabled: true
      realm: "HA Recorder API"
    rate-limiting:
      enabled: true
      requests-per-minute: 100
      burst-capacity: 20
```

#### JWT Token Authentication (Advanced)
```java
// JWTAuthenticationFilter.java
@Component
public class JWTAuthenticationFilter extends OncePerRequestFilter {
    
    @Override
    protected void doFilterInternal(HttpServletRequest request, 
                                    HttpServletResponse response, 
                                    FilterChain filterChain) throws ServletException, IOException {
        
        String token = extractToken(request);
        if (token != null && validateToken(token)) {
            Authentication auth = getAuthentication(token);
            SecurityContextHolder.getContext().setAuthentication(auth);
        }
        
        filterChain.doFilter(request, response);
    }
}
```

#### API Key Authentication
```yaml
# API Key configuration
ha:
  security:
    api-key:
      enabled: true
      header-name: "X-API-Key"
      keys:
        - key: "prod-key-123456789"
          name: "production-client"
          permissions: ["READ", "WRITE"]
        - key: "readonly-key-987654321"
          name: "monitoring-client"
          permissions: ["READ"]
```

### Network Security

#### SSL/TLS Configuration
```yaml
# application-prod.yml
server:
  port: 8443
  ssl:
    enabled: true
    key-store: classpath:keystore.p12
    key-store-password: ${SSL_KEYSTORE_PASSWORD}
    key-store-type: PKCS12
    key-alias: ha-recorder
    protocol: TLS
    enabled-protocols: TLSv1.2,TLSv1.3
    ciphers: TLS_AES_256_GCM_SHA384,TLS_CHACHA20_POLY1305_SHA256,TLS_AES_128_GCM_SHA256
```

#### Firewall Rules
```bash
# UFW configuration
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH
sudo ufw allow ssh

# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow application ports (internal only)
sudo ufw allow from 10.0.0.0/8 to any port 8080
sudo ufw allow from 172.16.0.0/12 to any port 8080
sudo ufw allow from 192.168.0.0/16 to any port 8080

# Redis cluster (internal only)
sudo ufw allow from 10.0.0.0/8 to any port 6379
sudo ufw allow from 172.16.0.0/12 to any port 6379
sudo ufw allow from 192.168.0.0/16 to any port 6379

# Enable firewall
sudo ufw enable
```

### Data Protection

#### Encryption at Rest
```yaml
# Redis encryption
redis:
  encryption:
    enabled: true
    key-file: /etc/redis/encryption.key
    algorithm: AES-256-GCM

# S3 encryption
ha:
  s3:
    encryption:
      enabled: true
      kms-key-id: ${AWS_KMS_KEY_ID}
      algorithm: "aws:kms"
```

#### Secrets Management
```yaml
# Using Docker Secrets
version: '3.8'
services:
  ha-controller:
    image: openvidu/ha-recorder:latest
    secrets:
      - redis_password
      - s3_secret_key
      - jwt_secret
    environment:
      - REDIS_PASSWORD_FILE=/run/secrets/redis_password
      - S3_SECRET_KEY_FILE=/run/secrets/s3_secret_key
      - JWT_SECRET_FILE=/run/secrets/jwt_secret

secrets:
  redis_password:
    file: ./secrets/redis_password.txt
  s3_secret_key:
    file: ./secrets/s3_secret_key.txt
  jwt_secret:
    file: ./secrets/jwt_secret.txt
```

### Security Hardening

#### Container Security
```dockerfile
# Security-focused Dockerfile
FROM openjdk:21-jre-slim

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Install security updates
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set security-focused JVM options
ENV JAVA_OPTS="-Xms1g -Xmx2g \
    -Djava.security.egd=file:/dev/./urandom \
    -Dfile.encoding=UTF-8 \
    -Djava.awt.headless=true \
    -XX:+UseG1GC \
    -XX:+DisableExplicitGC"

# Copy application
COPY --chown=appuser:appuser ha-recorder.jar /app/
COPY --chown=appuser:appuser config/ /app/config/

# Switch to non-root user
USER appuser

# Expose only necessary port
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/ha-recorder.jar"]
```

#### Security Scanning
```bash
#!/bin/bash
# security-scan.sh

echo "Running security scans..."

# Container vulnerability scan
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy image openvidu/ha-recorder:latest

# Dependency vulnerability scan
./mvnw org.owasp:dependency-check-maven:check

# Static code analysis
./mvnw sonar:sonar \
    -Dsonar.projectKey=ha-recorder \
    -Dsonar.host.url=http://sonarqube:9000

# Network security scan
nmap -sV -sC localhost

echo "Security scans completed"
```

### Audit Logging

#### Security Event Logging
```java
// SecurityAuditLogger.java
@Component
@Slf4j
public class SecurityAuditLogger {
    
    @EventListener
    public void handleAuthenticationSuccess(AuthenticationSuccessEvent event) {
        log.info("Authentication successful [user={}, ip={}, timestamp={}]",
            event.getAuthentication().getName(),
            getCurrentIP(),
            Instant.now());
    }
    
    @EventListener
    public void handleAuthenticationFailure(AbstractAuthenticationFailureEvent event) {
        log.warn("Authentication failed [user={}, ip={}, reason={}, timestamp={}]",
            event.getAuthentication().getName(),
            getCurrentIP(),
            event.getException().getMessage(),
            Instant.now());
    }
}
```

#### Compliance Logging
```yaml
# Audit logging configuration
logging:
  level:
    org.springframework.security: INFO
    com.openvidu.ha.security: INFO
  pattern:
    console: "%d{ISO8601} [%thread] %-5level %logger{36} [%X{requestId}] - %msg%n"
    file: "%d{ISO8601} [%thread] %-5level %logger{36} [%X{requestId}] [%X{userId}] [%X{clientIP}] - %msg%n"
```

## ⚡ Performance Tuning

### JVM Optimization

#### Memory Configuration
```bash
# Production JVM settings
JAVA_OPTS="-Xms4g -Xmx8g \
    -XX:+UseG1GC \
    -XX:MaxGCPauseMillis=200 \
    -XX:G1HeapRegionSize=16m \
    -XX:+UseStringDeduplication \
    -XX:+OptimizeStringConcat \
    -XX:+UseCompressedOops \
    -XX:+UseCompressedClassPointers"

# GC logging
GC_OPTS="-Xlog:gc*:gc.log:time,level,tags \
    -XX:+UseGCLogFileRotation \
    -XX:NumberOfGCLogFiles=5 \
    -XX:GCLogFileSize=100M"

# Monitoring and debugging
DEBUG_OPTS="-XX:+PrintGCDetails \
    -XX:+PrintGCTimeStamps \
    -XX:+HeapDumpOnOutOfMemoryError \
    -XX:HeapDumpPath=/var/log/heapdumps/"

export JAVA_OPTS="$JAVA_OPTS $GC_OPTS $DEBUG_OPTS"
```

#### GC Tuning for Different Workloads
```bash
# Low latency (frequent small requests)
LOW_LATENCY_OPTS="-XX:+UseZGC \
    -XX:+UnlockExperimentalVMOptions \
    -XX:+UseTransparentHugePages"

# High throughput (batch processing)
HIGH_THROUGHPUT_OPTS="-XX:+UseParallelGC \
    -XX:ParallelGCThreads=8 \
    -XX:+UseAdaptiveSizePolicy"

# Balanced (mixed workload)
BALANCED_OPTS="-XX:+UseG1GC \
    -XX:MaxGCPauseMillis=100 \
    -XX:G1MixedGCCountTarget=8"
```

### Database Optimization

#### Redis Performance Tuning
```bash
# redis.conf optimizations
# Memory management
maxmemory 4gb
maxmemory-policy allkeys-lru
maxmemory-samples 10

# Persistence optimization
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes

# Network optimization
tcp-keepalive 300
tcp-backlog 511
timeout 0

# Performance settings
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64

# Threading (Redis 6.0+)
io-threads 4
io-threads-do-reads yes
```

#### Redis Cluster Optimization
```bash
# Cluster-specific settings
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 15000
cluster-slave-validity-factor 10
cluster-migration-barrier 1
cluster-require-full-coverage yes
```

### Application Performance

#### Spring Boot Optimization
```yaml
# application-prod.yml
spring:
  jpa:
    show-sql: false
    properties:
      hibernate:
        jdbc:
          batch_size: 50
          order_inserts: true
          order_updates: true
        cache:
          use_second_level_cache: true
          region:
            factory_class: org.hibernate.cache.ehcache.EhCacheRegionFactory

  task:
    execution:
      pool:
        core-size: 10
        max-size: 50
        queue-capacity: 100
    scheduling:
      pool:
        size: 5

  redis:
    lettuce:
      pool:
        max-active: 20
        max-idle: 10
        min-idle: 5
        max-wait: 1000ms
      cluster:
        refresh:
          adaptive: true
          period: 30s

server:
  tomcat:
    threads:
      max: 200
      min-spare: 10
    max-connections: 8192
    accept-count: 100
    connection-timeout: 20s
    keep-alive-timeout: 60s
    max-keep-alive-requests: 100
```

#### Async Processing Optimization
```java
// AsyncConfiguration.java
@Configuration
@EnableAsync
public class AsyncConfiguration implements AsyncConfigurer {
    
    @Bean
    @Override
    public Executor getAsyncExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(10);
        executor.setMaxPoolSize(50);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("HA-Async-");
        executor.setKeepAliveSeconds(60);
        executor.setAllowCoreThreadTimeOut(true);
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.initialize();
        return executor;
    }
}
```

### Network Optimization

#### Connection Pooling
```yaml
# HTTP client configuration
ha:
  http-client:
    connection-pool:
      max-total: 200
      max-per-route: 50
      connection-timeout: 5000
      socket-timeout: 30000
      connection-request-timeout: 5000
    retry:
      max-attempts: 3
      backoff-delay: 1000
```

#### Load Balancing
```nginx
# nginx optimization
worker_processes auto;
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 100;
    
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript;
    
    upstream ha_controller {
        least_conn;
        keepalive 32;
        
        server ha-controller-1:8080 max_fails=3 fail_timeout=30s;
        server ha-controller-2:8080 max_fails=3 fail_timeout=30s;
        server ha-controller-3:8080 max_fails=3 fail_timeout=30s;
    }
}
```

### Monitoring Performance

#### JVM Metrics
```bash
# Enable JMX monitoring
JMX_OPTS="-Dcom.sun.management.jmxremote \
    -Dcom.sun.management.jmxremote.port=9999 \
    -Dcom.sun.management.jmxremote.authenticate=false \
    -Dcom.sun.management.jmxremote.ssl=false"

# Flight Recorder (for detailed profiling)
JFR_OPTS="-XX:+FlightRecorder \
    -XX:StartFlightRecording=duration=60s,filename=app-profile.jfr"
```

#### Performance Testing
```bash
#!/bin/bash
# load-test.sh

# API load test
wrk -t12 -c400 -d30s -H "Authorization: Basic YWRtaW46cGFzc3dvcmQ=" \
    --script=load-test.lua http://localhost:8080/api/sessions

# Database performance test
redis-benchmark -h localhost -p 6379 -a password -n 100000 -d 1024

# File I/O test
fio --name=randwrite --ioengine=libaio --iodepth=16 --rw=randwrite \
    --bs=4k --direct=0 --size=1G --numjobs=4 --runtime=60 --group_reporting
```

## 🤝 Contributing

### Development Setup

#### Local Environment
```bash
# Clone and setup
git clone https://github.com/your-org/openvidu-ha-recorder.git
cd openvidu-ha-recorder

# Setup development environment
./scripts/setup-dev.sh

# Start development dependencies
docker-compose -f docker-compose.dev.yml up -d

# Run tests
./mvnw test

# Run application
./mvnw spring-boot:run -Dspring-boot.run.profiles=dev
```

#### Code Style
```bash
# Install pre-commit hooks
./scripts/install-hooks.sh

# Format code
./mvnw spotless:apply

# Check code style
./mvnw spotless:check

# Run static analysis
./mvnw checkstyle:check
./mvnw pmd:check
./mvnw spotbugs:check
```

### Testing Guidelines

#### Unit Tests
```java
// SessionServiceTest.java
@ExtendWith(MockitoExtension.class)
class SessionServiceTest {
    
    @Mock
    private SessionRepository sessionRepository;
    
    @Mock
    private DockerService dockerService;
    
    @InjectMocks
    private SessionService sessionService;
    
    @Test
    void shouldCreateSession() {
        // Given
        CreateSessionRequest request = CreateSessionRequest.builder()
            .sessionId("test-session")
            .recordingName("test-recording")
            .build();
        
        when(dockerService.createContainer(any())).thenReturn("container-id");
        
        // When
        SessionDto result = sessionService.createSession(request);
        
        // Then
        assertThat(result.getSessionId()).isEqualTo("test-session");
        assertThat(result.getStatus()).isEqualTo(SessionStatus.STARTING);
        verify(sessionRepository).save(any(Session.class));
    }
}
```

#### Integration Tests
```java
// SessionControllerIntegrationTest.java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
class SessionControllerIntegrationTest {
    
    @Container
    static RedisContainer redis = new RedisContainer("redis:7-alpine");
    
    @Autowired
    private TestRestTemplate restTemplate;
    
    @Test
    void shouldCreateAndRetrieveSession() {
        // Given
        CreateSessionRequest request = new CreateSessionRequest();
        request.setSessionId("integration-test");
        
        // When
        ResponseEntity<SessionDto> createResponse = restTemplate
            .withBasicAuth("admin", "password")
            .postForEntity("/api/sessions", request, SessionDto.class);
        
        // Then
        assertThat(createResponse.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(createResponse.getBody().getSessionId()).isEqualTo("integration-test");
    }
}
```

### Pull Request Process

#### Checklist
- [ ] Code follows style guidelines
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Documentation updated
- [ ] Changelog updated
- [ ] Performance impact assessed
- [ ] Security review completed

#### PR Template
```markdown
## Description
Brief description of the changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing completed

## Performance Impact
Describe any performance implications

## Security Considerations
Describe any security implications

## Checklist
- [ ] Code review completed
- [ ] Documentation updated
- [ ] Changelog updated
```

### Release Process

#### Versioning Strategy
```bash
# Semantic versioning: MAJOR.MINOR.PATCH
# MAJOR: Breaking changes
# MINOR: New features (backward compatible)
# PATCH: Bug fixes (backward compatible)

# Example release flow
git checkout main
git pull origin main
./mvnw versions:set -DnewVersion=1.2.0
git commit -am "Release version 1.2.0"
git tag -a v1.2.0 -m "Release version 1.2.0"
git push origin main --tags
```

#### Release Checklist
- [ ] All tests pass
- [ ] Documentation updated
- [ ] Changelog updated
- [ ] Version bumped
- [ ] Docker images built
- [ ] Security scan completed
- [ ] Performance benchmarks run
- [ ] Release notes prepared

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

```text
Apache License 2.0

Copyright 2025 OpenVidu2 HA Recorder Contributors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

---

## 🔗 Additional Resources

### Documentation Links
- [OpenVidu Documentation](https://docs.openvidu.io/)
- [Spring Boot Reference](https://docs.spring.io/spring-boot/docs/current/reference/html/)
- [Redis Documentation](https://redis.io/documentation)
- [Docker Documentation](https://docs.docker.com/)

### Community Support
- **GitHub Issues**: [Report bugs and request features](https://github.com/your-org/openvidu-ha-recorder/issues)
- **Discussions**: [Community discussions and Q&A](https://github.com/your-org/openvidu-ha-recorder/discussions)
- **Stack Overflow**: Tag questions with `openvidu-ha-recorder`
- **Slack Channel**: [Join our Slack workspace](https://slack.openvidu.io)

### Related Projects
- [OpenVidu](https://github.com/OpenVidu/openvidu) - WebRTC videoconferencing platform
- [OpenVidu Recording](https://github.com/OpenVidu/openvidu/tree/master/openvidu-server/docker/openvidu-recording) - Official recording service
- [Kurento Media Server](https://github.com/Kurento/kurento-media-server) - WebRTC media server

---

## 📊 Appendices

### Appendix A: Configuration Reference

#### Complete Environment Variables
```bash
# Application Configuration
SPRING_PROFILES_ACTIVE=prod
SERVER_PORT=8080
MANAGEMENT_SERVER_PORT=8081

# Security Configuration
HA_CONTROLLER_USERNAME=admin
HA_CONTROLLER_PASSWORD=secure_password_here
OPENVIDU_SECRET=MY_SECRET

# Database Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=redis_password_here
REDIS_DATABASE=0
REDIS_TIMEOUT=5000
REDIS_CLUSTER_NODES=redis-1:6379,redis-2:6379,redis-3:6379

# Storage Configuration
S3_ENDPOINT=https://s3.amazonaws.com
S3_ACCESS_KEY=your_access_key
S3_SECRET_KEY=your_secret_key
S3_BUCKET=openvidu-recordings
S3_REGION=us-east-1

# Docker Configuration
DOCKER_HOST=unix:///var/run/docker.sock
DOCKER_NETWORK=openvidu_network
RECORDER_IMAGE=openvidu/openvidu-recording:2.30.0

# Recording Configuration
RECORDING_HEARTBEAT_INTERVAL=30s
RECORDING_HEARTBEAT_TIMEOUT=120s
RECORDING_FAILOVER_ENABLED=true
RECORDING_FAILOVER_MAX_RETRIES=3
RECORDING_FAILOVER_RETRY_DELAY=10s

# Monitoring Configuration
MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE=health,info,metrics,prometheus
MANAGEMENT_ENDPOINT_HEALTH_SHOW_DETAILS=when-authorized

# Logging Configuration
LOGGING_LEVEL_ROOT=INFO
LOGGING_LEVEL_COM_OPENVIDU_HA=INFO
LOGGING_FILE_NAME=/var/log/ha-recorder.log
LOGGING_PATTERN_FILE=%d{ISO8601} [%thread] %-5level %logger{36} - %msg%n
```

### Appendix B: API Response Schemas

#### Session Response Schema
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "sessionId": {
      "type": "string",
      "description": "Unique identifier for the recording session"
    },
    "status": {
      "type": "string",
      "enum": ["STARTING", "RECORDING", "STOPPING", "STOPPED", "FAILED"],
      "description": "Current status of the recording session"
    },
    "containerId": {
      "type": "string",
      "description": "Docker container ID running the recording"
    },
    "createdAt": {
      "type": "string",
      "format": "date-time",
      "description": "Timestamp when the session was created"
    },
    "lastModified": {
      "type": "string",
      "format": "date-time",
      "description": "Timestamp when the session was last updated"
    },
    "recordingName": {
      "type": "string",
      "description": "Name of the recording file"
    },
    "outputMode": {
      "type": "string",
      "enum": ["COMPOSED", "COMPOSED_QUICK_START", "INDIVIDUAL"],
      "description": "Recording output mode"
    },
    "recordingLayout": {
      "type": "string",
      "enum": ["BEST_FIT", "PICTURE_IN_PICTURE", "VERTICAL_PRESENTATION", "HORIZONTAL_PRESENTATION", "CUSTOM"],
      "description": "Layout for composed recordings"
    },
    "heartbeatData": {
      "type": "object",
      "properties": {
        "lastHeartbeat": {
          "type": "string",
          "format": "date-time",
          "description": "Timestamp of the last received heartbeat"
        },
        "chunksUploaded": {
          "type": "integer",
          "description": "Number of chunks uploaded to storage"
        },
        "currentChunkSize": {
          "type": "integer",
          "description": "Size of the current chunk in bytes"
        },
        "isStuck": {
          "type": "boolean",
          "description": "Whether the recording appears to be stuck"
        },
        "failoverAttempts": {
          "type": "integer",
          "description": "Number of failover attempts for this session"
        }
      }
    },
    "containerInfo": {
      "type": "object",
      "properties": {
        "containerId": {
          "type": "string",
          "description": "Docker container ID"
        },
        "containerName": {
          "type": "string",
          "description": "Docker container name"
        },
        "status": {
          "type": "string",
          "enum": ["RUNNING", "EXITED", "CREATED", "RESTARTING", "REMOVING", "PAUSED", "DEAD"],
          "description": "Docker container status"
        },
        "created": {
          "type": "string",
          "format": "date-time",
          "description": "Container creation timestamp"
        }
      }
    }
  },
  "required": ["sessionId", "status", "createdAt"]
}
```

### Appendix C: Docker Compose Examples

#### Development Environment
```yaml
# docker-compose.dev.yml
version: '3.8'

services:
  ha-controller:
    build: .
    ports:
      - "8080:8080"
      - "8081:8081"
    environment:
      - SPRING_PROFILES_ACTIVE=dev,swagger
      - SPRING_REDIS_HOST=redis
      - SPRING_REDIS_PASSWORD=devpassword
      - HA_CONTROLLER_USERNAME=admin
      - HA_CONTROLLER_PASSWORD=admin
      - S3_ENDPOINT=http://minio:9000
      - S3_ACCESS_KEY=minioadmin
      - S3_SECRET_KEY=minioadmin123
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./logs:/var/log
    depends_on:
      - redis
      - minio
    networks:
      - dev-network

  redis:
    image: redis:7-alpine
    command: redis-server --requirepass devpassword
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    networks:
      - dev-network

  minio:
    image: minio/minio:latest
    command: server /data --console-address ":9001"
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      - MINIO_ACCESS_KEY=minioadmin
      - MINIO_SECRET_KEY=minioadmin123
    volumes:
      - minio-data:/data
    networks:
      - dev-network

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    networks:
      - dev-network

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana
      - ./monitoring/grafana/dashboards:/var/lib/grafana/dashboards
    networks:
      - dev-network

networks:
  dev-network:
    driver: bridge

volumes:
  redis-data:
  minio-data:
  prometheus-data:
  grafana-data:
```

#### Testing Environment
```yaml
# docker-compose.test.yml
version: '3.8'

services:
  ha-controller-test:
    build: .
    environment:
      - SPRING_PROFILES_ACTIVE=test
      - SPRING_REDIS_HOST=redis-test
      - SPRING_REDIS_PASSWORD=testpassword
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      - redis-test
    networks:
      - test-network

  redis-test:
    image: redis:7-alpine
    command: redis-server --requirepass testpassword
    networks:
      - test-network

  integration-tests:
    build:
      context: .
      dockerfile: Dockerfile.test
    command: ./mvnw test -Dspring.profiles.active=test
    depends_on:
      - ha-controller-test
    volumes:
      - .:/app
      - ~/.m2:/root/.m2
    networks:
      - test-network

networks:
  test-network:
    driver: bridge
```

### Appendix D: Kubernetes Manifests

#### Namespace and ConfigMap
```yaml
# k8s/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openvidu-ha

---
# k8s/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ha-recorder-config
  namespace: openvidu-ha
data:
  application.yml: |
    spring:
      profiles:
        active: prod
      redis:
        host: redis-service
        port: 6379
    ha:
      recorder:
        heartbeat:
          interval: 15s
          timeout: 60s
      s3:
        endpoint: ${S3_ENDPOINT}
        bucket: ${S3_BUCKET}
    management:
      endpoints:
        web:
          exposure:
            include: health,info,metrics,prometheus
```

#### Secrets
```yaml
# k8s/secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: ha-recorder-secrets
  namespace: openvidu-ha
type: Opaque
data:
  redis-password: <base64-encoded-password>
  ha-controller-username: <base64-encoded-username>
  ha-controller-password: <base64-encoded-password>
  s3-access-key: <base64-encoded-access-key>
  s3-secret-key: <base64-encoded-secret-key>
```

#### Services
```yaml
# k8s/services.yaml
apiVersion: v1
kind: Service
metadata:
  name: ha-recorder-service
  namespace: openvidu-ha
spec:
  selector:
    app: ha-recorder
  ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: management
      port: 8081
      targetPort: 8081
  type: ClusterIP

---
apiVersion: v1
kind: Service
metadata:
  name: redis-service
  namespace: openvidu-ha
spec:
  selector:
    app: redis
  ports:
    - port: 6379
      targetPort: 6379
  type: ClusterIP
```

#### Ingress
```yaml
# k8s/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ha-recorder-ingress
  namespace: openvidu-ha
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: ha-recorder-basic-auth
spec:
  tls:
    - hosts:
        - ha-recorder.yourdomain.com
      secretName: ha-recorder-tls
  rules:
    - host: ha-recorder.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ha-recorder-service
                port:
                  number: 8080
```

### Appendix E: Monitoring Dashboards

#### Grafana Dashboard JSON
```json
{
  "dashboard": {
    "id": null,
    "title": "OpenVidu HA Recorder",
    "tags": ["openvidu", "recording", "ha"],
    "style": "dark",
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Active Sessions",
        "type": "stat",
        "targets": [
          {
            "expr": "ha_recorder_sessions_active_total",
            "legendFormat": "Active Sessions"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "thresholds"
            },
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 50},
                {"color": "red", "value": 100}
              ]
            }
          }
        }
      },
      {
        "id": 2,
        "title": "Session Status Distribution",
        "type": "piechart",
        "targets": [
          {
            "expr": "ha_recorder_sessions_by_status_total",
            "legendFormat": "{{status}}"
          }
        ]
      },
      {
        "id": 3,
        "title": "Failover Events",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(ha_recorder_failover_events_total[5m]) * 60",
            "legendFormat": "Failovers per minute"
          }
        ],
        "yAxes": [
          {
            "label": "Events/min",
            "min": 0
          }
        ]
      },
      {
        "id": 4,
        "title": "Container Lifecycle",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(ha_recorder_containers_created_total[5m]) * 60",
            "legendFormat": "Created/min"
          },
          {
            "expr": "rate(ha_recorder_containers_failed_total[5m]) * 60",
            "legendFormat": "Failed/min"
          }
        ]
      },
      {
        "id": 5,
        "title": "API Response Times",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(ha_recorder_api_request_duration_seconds_bucket[5m]))",
            "legendFormat": "95th percentile"
          },
          {
            "expr": "histogram_quantile(0.50, rate(ha_recorder_api_request_duration_seconds_bucket[5m]))",
            "legendFormat": "50th percentile"
          }
        ]
      },
      {
        "id": 6,
        "title": "JVM Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "jvm_memory_used_bytes{area=\"heap\"}",
            "legendFormat": "Heap Used"
          },
          {
            "expr": "jvm_memory_max_bytes{area=\"heap\"}",
            "legendFormat": "Heap Max"
          }
        ]
      }
    ],
    "refresh": "30s",
    "schemaVersion": 27,
    "version": 1
  }
}
```

### Appendix F: Troubleshooting Scripts

#### Health Check Script
```bash
#!/bin/bash
# health-check.sh

set -e

CONTROLLER_URL="${CONTROLLER_URL:-http://localhost:8080}"
USERNAME="${USERNAME:-admin}"
PASSWORD="${PASSWORD:-admin}"

echo "=== OpenVidu HA Recorder Health Check ==="
echo "Controller URL: $CONTROLLER_URL"
echo "Timestamp: $(date)"
echo

# Check application health
echo "1. Checking application health..."
if curl -f -s -u "$USERNAME:$PASSWORD" "$CONTROLLER_URL/actuator/health" > /dev/null; then
    echo "   ✓ Application is healthy"
else
    echo "   ✗ Application health check failed"
    exit 1
fi

# Check Redis connectivity
echo "2. Checking Redis connectivity..."
if curl -f -s -u "$USERNAME:$PASSWORD" "$CONTROLLER_URL/actuator/health/redis" > /dev/null; then
    echo "   ✓ Redis is accessible"
else
    echo "   ✗ Redis connectivity failed"
    exit 1
fi

# Check Docker connectivity
echo "3. Checking Docker connectivity..."
if curl -f -s -u "$USERNAME:$PASSWORD" "$CONTROLLER_URL/actuator/health/docker" > /dev/null; then
    echo "   ✓ Docker is accessible"
else
    echo "   ✗ Docker connectivity failed"
    exit 1
fi

# Check S3 connectivity
echo "4. Checking S3 connectivity..."
if curl -f -s -u "$USERNAME:$PASSWORD" "$CONTROLLER_URL/actuator/health/s3" > /dev/null; then
    echo "   ✓ S3 is accessible"
else
    echo "   ✓ S3 connectivity failed (may be optional)"
fi

# Check active sessions
echo "5. Checking active sessions..."
SESSION_COUNT=$(curl -s -u "$USERNAME:$PASSWORD" "$CONTROLLER_URL/api/sessions" | jq '.sessions | length' 2>/dev/null || echo "0")
echo "   ✓ Active sessions: $SESSION_COUNT"

echo
echo "=== Health Check Completed ==="
```

#### Log Analysis Script
```bash
#!/bin/bash
# analyze-logs.sh

LOG_FILE="${1:-/var/log/ha-recorder.log}"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Log file not found: $LOG_FILE"
    exit 1
fi

echo "=== Log Analysis Report ==="
echo "Log file: $LOG_FILE"
echo "Analysis time: $(date)"
echo "Log size: $(du -h "$LOG_FILE" | cut -f1)"
echo

# Error summary
echo "1. Error Summary (last 24 hours):"
grep -i error "$LOG_FILE" | grep "$(date -d '24 hours ago' '+%Y-%m-%d')\|$(date '+%Y-%m-%d')" | wc -l | xargs echo "   Total errors:"
echo

# Most common errors
echo "2. Most Common Errors:"
grep -i error "$LOG_FILE" | grep "$(date '+%Y-%m-%d')" | awk '{print $5}' | sort | uniq -c | sort -nr | head -5 | sed 's/^/   /'
echo

# Session statistics
echo "3. Session Statistics (today):"
grep "Recording session created" "$LOG_FILE" | grep "$(date '+%Y-%m-%d')" | wc -l | xargs echo "   Sessions created:"
grep "Recording session stopped" "$LOG_FILE" | grep "$(date '+%Y-%m-%d')" | wc -l | xargs echo "   Sessions stopped:"
grep "Failover completed" "$LOG_FILE" | grep "$(date '+%Y-%m-%d')" | wc -l | xargs echo "   Failovers:"
echo

# Performance indicators
echo "4. Performance Indicators:"
grep "duration=" "$LOG_FILE" | grep "$(date '+%Y-%m-%d')" | grep -o "duration=[0-9]*" | sed 's/duration=//' | awk '{sum+=$1; count++} END {if(count>0) print "   Average request duration: " sum/count "ms"}'
echo

# Recent critical events
echo "5. Recent Critical Events (last 100 lines):"
tail -100 "$LOG_FILE" | grep -E "(ERROR|FATAL|WARN)" | tail -10 | sed 's/^/   /'

echo
echo "=== Analysis Completed ==="
```

---

## 🎯 Final Notes

This comprehensive documentation provides everything needed to successfully deploy, configure, and maintain the OpenVidu HA Recorder system in production environments. The system has been designed with enterprise-grade reliability, scalability, and observability in mind.

**Key Success Factors:**
- Follow the security hardening guidelines for production deployments
- Implement comprehensive monitoring and alerting from day one
- Regular backup and disaster recovery testing
- Performance baseline establishment and continuous monitoring
- Keep dependencies and base images updated for security

**Community Contribution:**
We welcome contributions from the community! Whether it's bug reports, feature requests, documentation improvements, or code contributions, your input helps make this project better for everyone.

**Support:**
For technical support, please use the GitHub issues tracker. For enterprise support and professional services, contact the maintainers directly.

Remember to star ⭐ this repository if you find it useful, and consider contributing back to the open-source community!

---

*Last updated: August 27, 2025*
*Version: 1.0.0*
