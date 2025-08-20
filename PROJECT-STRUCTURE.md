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
│   │   │               ├── OvRecorderApplication.java           # Main application class
│   │   │               ├── config/
│   │   │               │   ├── RedisConfig.java               # Redis configuration
│   │   │               │   └── SecurityConfig.java            # Security configuration
│   │   │               ├── controller/
│   │   │               │   └── SessionController.java         # REST API endpoints
│   │   │               ├── model/
│   │   │               │   └── RecordingSession.java         # Session data model
│   │   │               ├── repository/
│   │   │               │   └── SessionRepository.java        # Redis operations
│   │   │               └── service/
│   │   │                   └── SessionService.java           # Business logic
│   │   └── resources/
│   │       └── application.properties                        # Configuration file
│   └── test/                                                 # Test directory (if needed)
├── docker/                                      # Docker deployment directory
│   ├── docker-compose.yml                      # Docker Compose configuration
│   ├── start.sh                                # Startup script
│   ├── server/                                 # Docker build context for app
│   │   └── Dockerfile                          # Container build instructions
│   └── recorder/                               # Docker build context for the ov substitute recorder
│       └── Dockerfile                          # Container build instructions
│       └── scripts/                            # Scripts used by the recorder app
│       └── utils/                              # Other utility scripts used by the recorder app
├── pom.xml                                     # Maven configuration
├── README.md                                   # Project documentation
└── example-scripts.sh                         # Shell script examples
```

## 📋 File Placement Guide

### 1. **Source Code** (`src/` directory)
Place all Java source files in the `src/main/java/com/naevatec/ovrecorder/` hierarchy:

- **Main Application**: `src/main/java/com/naevatec/ovrecorder/OvRecorderApplication.java`
- **Configuration**: `src/main/java/com/naevatec/ovrecorder/config/`
- **Controllers**: `src/main/java/com/naevatec/ovrecorder/controller/`
- **Models**: `src/main/java/com/naevatec/ovrecorder/model/`
- **Repositories**: `src/main/java/com/naevatec/ovrecorder/repository/`
- **Services**: `src/main/java/com/naevatec/ovrecorder/service/`

### 2. **Resources** (`src/main/resources/`)
- **Configuration**: `src/main/resources/application.properties`

### 3. **Docker Setup** (`docker/` directory)
- **Compose File**: `docker/docker-compose.yml`
- **Start Script**: `docker/manage-environment.sh`
- **Server Dockerfile**: `docker/server/Dockerfile`
- **Recorder Dockerfile**: `docker/recorder/Dockerfile`

### 4. **Project Root**
- **Maven Config**: `pom.xml`
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

### Manual Docker Commands
```bash
cd docker/

# Build and start
docker compose up -d

# View logs
docker compose logs -f ov-recorder

# Stop
docker compose down

# Restart
docker compose restart
```

### Direct API Testing
```bash
# Health check
curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions/health

# Create session
curl -u recorder:rec0rd3r_2024! -X POST \
  http://localhost:8080/api/sessions \
  -H "Content-Type: application/json" \
  -d '{"sessionId":"rec-001","clientId":"client-01"}'

# List sessions
curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions
```

## 📝 Important Notes

1. **Package Structure**: All Java classes use `com.naevatec.ovrecorder` as the base package
2. **Artifact ID**: Maven artifact is `com.naevatec:ov-recorder`
3. **Container Names**: Docker containers use `ov-recorder` prefix
4. **Build Context**: The Dockerfile expects the JAR file to be copied to `docker/server/`
5. **Ports**: Application runs on port 8080, Redis on 6379
6. **Networks**: All containers run on `ov-recorder-network`

## 🔄 Development Workflow

1. **Code Changes**: Edit files in `src/` directory
2. **Build**: Run `mvn clean package` from project root
3. **Deploy**: Copy JAR to `docker/server/` and run `docker compose up -d`
4. **Test**: Use provided shell scripts or curl commands
5. **Debug**: Check logs with `docker compose logs -f ov-recorder`

This structure provides a clean separation between source code and deployment configuration, making it easy to manage both development and production environments.
