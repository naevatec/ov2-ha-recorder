# OV Recorder Project Structure

This document shows the complete folder structure for the OV Recorder HA Controller project.

## 📁 Complete Project Structure

```
BaseFolder/
├── src/                                          # Source code directory
│   ├── main/
│   │   ├── java/
│   │   │   └── com/
│   │   │       └── naevatec/
│   │   │           └── ovrecorder/
│   │   │               ├── OvRecorderApplication.java           # Main application class (@EnableScheduling @EnableRetry)
│   │   │               ├── config/
│   │   │               │   ├── AsyncConfig.java               # Async configuration for webhook threads
│   │   │               │   ├── RedisConfig.java               # Redis configuration
│   │   │               │   ├── SecurityConfig.java            # Security configuration (Basic Auth)
│   │   │               │   └── SwaggerConfig.java             # OpenAPI documentation config
│   │   │               ├── controller/
│   │   │               │   ├── FailoverController.java        # Failover management API
│   │   │               │   ├── SessionController.java         # Session management REST API
│   │   │               │   └── WebhookController.java         # OpenVidu webhook relay endpoint
│   │   │               ├── model/
│   │   │               │   └── RecordingSession.java          # Session data model (Lombok + backup container fields)
│   │   │               ├── repository/
│   │   │               │   └── SessionRepository.java         # Redis operations (Lombok)
│   │   │               └── service/
│   │   │                   ├── DockerTestService.java         # Docker connection testing
│   │   │                   ├── FailoverService.java           # Docker-in-Docker failover system
│   │   │                   ├── S3CleanupService.java          # S3 chunk cleanup service
│   │   │                   ├── SessionService.java            # Business logic (Lombok + S3 integration)
│   │   │                   └── WebhookRelayService.java       # High-performance async webhook relay
│   │   └── resources/
│   │       └── application.properties                        # Configuration file
│   └── test/                                                 # Test directory (if needed)
├── docker/                                      # Docker deployment directory
│   ├── docker-compose.yml                      # Docker Compose configuration (MinIO + Redis + HA Controller)
│   ├── .env                                    # Environment variables file
│   ├── start.sh                                # Startup script
│   ├── server/                                 # Docker build context for HA Controller
│   │   └── Dockerfile                          # Container build instructions
│   └── recorder/                               # Docker build context for OpenVidu recorder
│       ├── Dockerfile                          # Container build instructions (custom OpenVidu image)
│       ├── scripts/
│       │   ├── composed.sh                     # Enhanced recording script (HA + S3 integration)
│       │   ├── session-register.sh             # Session registration with HA Controller
│       │   └── recorder-session-manager.sh     # Heartbeat and session management
│       └── utils/                              # Other utility scripts used by the recorder app
├── data/                                       # Persistent data directory (created at runtime)
│   ├── controller/
│   │   └── logs/                               # HA Controller application logs
│   ├── minio/
│   │   └── data/                               # MinIO S3 storage data
│   ├── redis/
│   │   └── data/                               # Redis persistent data
│   └── recorder/
│       └── data/                               # Recording output data
├── pom.xml                                     # Maven configuration (Java 21, Lombok, Docker Java, Security fixes)
├── README.md                                   # Project documentation
└── example-scripts.sh                         # Shell script examples
```

## 📋 File Placement Guide

### 1. **Source Code** (`src/` directory)
Place all Java source files in the `src/main/java/com/naevatec/ovrecorder/` hierarchy:

- **Main Application**: `src/main/java/com/naevatec/ovrecorder/OvRecorderApplication.java`
- **Configuration**: `src/main/java/com/naevatec/ovrecorder/config/`
  - `AsyncConfig.java` - Webhook thread pool configuration
  - `RedisConfig.java` - Redis template configuration
  - `SecurityConfig.java` - HTTP Basic Auth + endpoint security
  - `SwaggerConfig.java` - OpenAPI documentation (dev/test only)
- **Controllers**: `src/main/java/com/naevatec/ovrecorder/controller/`
  - `SessionController.java` - Session lifecycle management API
  - `FailoverController.java` - Failover system management API
  - `WebhookController.java` - OpenVidu webhook relay endpoint
- **Models**: `src/main/java/com/naevatec/ovrecorder/model/`
  - `RecordingSession.java` - Session entity with backup container support
- **Repositories**: `src/main/java/com/naevatec/ovrecorder/repository/`
  - `SessionRepository.java` - Redis CRUD operations
- **Services**: `src/main/java/com/naevatec/ovrecorder/service/`
  - `SessionService.java` - Core session management + S3 integration
  - `FailoverService.java` - Docker container failover management
  - `WebhookRelayService.java` - Async webhook forwarding with retry logic
  - `S3CleanupService.java` - S3 chunk cleanup on session removal
  - `DockerTestService.java` - Docker connectivity testing

### 2. **Resources** (`src/main/resources/`)
- **Configuration**: `src/main/resources/application.properties`

### 3. **Docker Setup** (`docker/` directory)
- **Compose File**: `docker/docker-compose.yml` - Multi-service setup (MinIO, Redis, HA Controller, Recorder)
- **Environment**: `docker/.env` - Environment variables configuration
- **Start Script**: `docker/manage-environment.sh`
- **Server Dockerfile**: `docker/server/Dockerfile` - HA Controller container
- **Recorder Dockerfile**: `docker/recorder/Dockerfile` - Custom OpenVidu recorder container

### 4. **Project Root**
- **Maven Config**: `pom.xml` - Java 21, Lombok, Docker Java client, AWS S3 SDK v2
- **Documentation**: `README.md`
- **Helper Scripts**: `example-scripts.sh`

## 🚀 Build & Deployment Process

### Step 1: Build the Application
```bash
# From project root (BaseFolder/)
mvn clean package -DskipTests
```

### Step 2: Copy JAR to Docker Context
```bash
# Copy built JAR to docker build context
cp target/recorder-ha-controller-1.0.0.jar docker/server/
```

### Step 3: Start with Docker
```bash
# Go to docker directory
cd docker/

# Make start script executable
chmod +x start.sh

# Start everything (builds + deploys)
./start.sh start
```

## 🔧 Quick Commands

### Using Modern Docker Compose
```bash
cd docker/

# Build and start everything
docker compose up -d

# Start specific profiles
docker compose --profile ha-controller up -d          # HA Controller only
docker compose --profile test up -d                   # Full test environment

# View logs
docker compose logs -f ov-recorder-ha-controller
docker compose logs -f minio
docker compose logs -f redis

# Stop services
docker compose down

# Clean up everything (including volumes)
docker compose down -v
```

### Using the Start Script
```bash
cd docker/

# Build and start everything
./start.sh start

# Just build the application
./start.sh build

# Stop services
./start.sh stop

# View logs
./start.sh logs

# Show status
./start.sh status

# Clean up everything
./start.sh clean
```

### Direct API Testing
```bash
# Health check (includes S3 status)
curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions/health

# Create session
curl -u recorder:rec0rd3r_2024! -X POST \
  http://localhost:8080/api/sessions \
  -H "Content-Type: application/json" \
  -d '{"sessionId":"test_session_001","clientId":"test-client","clientHost":"localhost"}'

# Send heartbeat with chunk info
curl -u recorder:rec0rd3r_2024! -X PUT \
  http://localhost:8080/api/sessions/test_session_001/heartbeat \
  -H "Content-Type: application/json" \
  -d '{"lastChunk":"0003.mp4"}'

# List active sessions
curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions

# Check failover status
curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/failover/status

# Test webhook endpoint
curl -X POST http://localhost:8080/openvidu/webhook \
  -H "Content-Type: application/json" \
  -d '{"event":"test","sessionId":"test_session_001","status":"stopped"}'

# Get webhook relay status
curl http://localhost:8080/openvidu/webhook/status

# Remove session (triggers S3 cleanup)
curl -u recorder:rec0rd3r_2024! -X DELETE http://localhost:8080/api/sessions/test_session_001
```

## 🌐 Service Endpoints

### HA Controller (Port 8080)
- **Health**: `GET /api/sessions/health`
- **Session API**: `/api/sessions/*` (Basic Auth required)
- **Failover API**: `/api/failover/*` (Basic Auth required)
- **Webhook Relay**: `/openvidu/webhook` (No auth - OpenVidu integration)
- **Swagger UI**: `/swagger-ui.html` (dev/test profiles only)

### MinIO (Development)
- **S3 API**: `http://localhost:9000` (AWS S3 compatible)
- **Console**: `http://localhost:9001` (Web UI - credentials: naeva_minio/N43v4t3c_M1n10)

### Redis (Development)
- **Port**: `15336` (for testing - remove in production)

## 📝 Important Notes

1. **Package Structure**: All Java classes use `com.naevatec.ovrecorder` as the base package
2. **Artifact ID**: Maven artifact is `com.naevatec:ov-recorder`
3. **Container Names**: Docker containers use `ov-recorder-*` or `ov-recorder-ha-controller` prefix
4. **Build Context**: The Dockerfile expects the JAR file to be copied to `docker/server/`
5. **Ports**: 
   - HA Controller: 8080
   - MinIO API: 9000
   - MinIO Console: 9001
   - Redis: 6379 (internal), 15336 (dev testing)
6. **Networks**: All containers run on `ov-ha-recorder` network
7. **Data Persistence**: All data stored in `./data/` directory (bind mounts)

## 🔄 Development Workflow

1. **Code Changes**: Edit files in `src/` directory
2. **Build**: Run `mvn clean package` from project root
3. **Deploy**: Copy JAR to `docker/server/` and run `docker compose up -d`
4. **Test**: Use provided shell scripts or curl commands
5. **Debug**: Check logs with `docker compose logs -f ov-recorder-ha-controller`
6. **S3 Testing**: Use MinIO console at http://localhost:9001
7. **Monitoring**: Check health endpoint for S3 and service status

## 🎯 Key Features

### ✅ **Completed Systems:**
- **Session Management**: Registration, heartbeat tracking, lifecycle management
- **Webhook Relay**: High-performance OpenVidu webhook forwarding with retry logic
- **Failover System**: Docker-in-Docker automatic backup container launching
- **S3 Integration**: Chunk cleanup on session removal with MinIO compatibility
- **Security**: HTTP Basic Auth with configurable credentials
- **Monitoring**: Health checks, metrics, and comprehensive logging
- **API Documentation**: Swagger UI for development and testing

### 🔧 **Configuration:**
- **Environment-driven**: All settings configurable via environment variables
- **Profile-based**: Different configurations for dev/test/prod environments
- **Resource optimization**: Configurable thread pools, memory limits, timeouts
- **S3 compatibility**: Works with both AWS S3 and MinIO

This structure provides a clean separation between source code and deployment configuration, making it easy to manage both development and production environments with advanced HA recording capabilities.
