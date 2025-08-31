# OpenVidu2 HA Recorder

High Availability Recorder for OpenVidu with intelligent failover, real-time monitoring, and centralized session management.


## Overview
This project integrates a high available recorder for [OpenVidu 2](https://openvidu.io) into your current installation. The idea behind the scenes is to store little consecutive pieces of the recording in an external storage compatible with S3, joining them when the recording finish.

This project is a substitute of the recording container provided by default by OpenVidu, but with the advantage of not losing the video already recorded in the event of a server crash.  This is done keeping the chunks in S3 linked to the session name in OpenVidu. So for this recorder all pieces of session with the same name will be handled as the same session.

⚠ __Note__ ⚠:  This recorder requires that your recording is using COMPOSED as your recording output mode. For example, if you are using Java for starting your recording, you have to configure your recording as:
```
RecordingProperties properties = new RecordingProperties.Builder().outputMode(Recording.OutputMode.COMPOSED)
					.build();
Recording recording = openVidu.startRecording(openViduSessionId, properties);
```

OpenVidu2 HA Recorder enhances OpenVidu's recording capabilities by providing:

- **Intelligent Failover**: Automatic backup container deployment when recordings fail
- **Real-time Monitoring**: Chunk-level progress tracking with heartbeat monitoring  
- **Centralized Management**: SpringBoot REST API with Redis persistence
- **Docker-in-Docker**: Seamless container lifecycle management
- **S3 Integration**: Compatible with MinIO and AWS S3 for scalable storage

## Quick Setup

### Prerequisites
- Docker 20.10+ and Docker Compose 2.0+
- Existing OpenVidu installation
- Sufficient disk space and network connectivity

### Installation

1. **Clone the repository:**
```bash
git clone https://github.com/naevatec/ov2-ha-recorder.git
cd ov2-ha-recorder
```

2. **Run the installation script:**
```bash
./ov2-ha-recorder-install.sh
```

The installer will:
- Auto-detect your OpenVidu installation and configuration
- Prompt for network settings (private IP, ports)
- Build and start all required services
- Guide you through OpenVidu webhook configuration

3. **Configure OpenVidu webhook (required):**
Edit your OpenVidu `.env` file and add:
```bash
OPENVIDU_WEBHOOK=true
OPENVIDU_WEBHOOK_ENDPOINT=http://YOUR_PRIVATE_IP:15443/openvidu/webhook
```

Then restart OpenVidu:
```bash
cd /opt/openvidu && docker-compose restart
```

### Where will be my recordings placed?
Your recordings will be placed in the same folder where they currently live. After all chunk operations are made, a joined full version of the video will be placed in the same folder where OpenVidu expects all video to be located.

### Daily Operations

All operations are managed from the `docker` directory:

```bash
# Change to operations directory
cd docker

# Start services
./ov2-ha-recorder.sh start

# Check status
./ov2-ha-recorder.sh status

# View logs
./ov2-ha-recorder.sh logs

# Test API
./ov2-ha-recorder.sh test-api

# Stop services
./ov2-ha-recorder.sh stop
```

## Project Structure

```
ov2-ha-recorder/
├── ov2-ha-recorder-install.sh    # Installation script (run from here)
├── .env_template                  # Configuration template
├── README.md                     # This file
├── README.complete.md            # Comprehensive documentation
└── docker/                      # Docker environment
    ├── ov2-ha-recorder.sh        # Operations management (run from here)
    ├── docker-compose.yml        # Service definitions
    ├── server/                   # HA Controller source code
    └── recorder/                 # Enhanced recording container
```

## ⚙️ Environment Configuration

The project uses a comprehensive `.env` file for both recording and HA Controller configuration:

### Required Variables

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

### Critical Requirements

⚠️ **Important**: 
- `HA_AWS_S3_SERVICE_ENDPOINT` must match `http://YOUR_PRIVATE_IP:MINIO_API_PORT`
- `HA_CONTROLLER_HOST` should match the Docker service name (`ov-recorder`)
- `HA_CONTROLLER_USERNAME` and `HA_CONTROLLER_PASSWORD` must match between recorder and HA Controller

## Manual Build (Advanced)

If you need to build components separately:

### 1. Build HA Controller
```bash
cd docker
export IMAGE_TAG=2.31.0  # Match your OpenVidu version
docker compose build ov-recorder-ha-controller
```

### 2. Build Recording Container
```bash
cd docker  
export IMAGE_TAG=2.31.0  # Match your OpenVidu version
docker compose build openvidu-recording
```

### 3. Start Infrastructure
```bash
cd docker
docker compose up -d minio minio-mc redis
```

### 4. Start HA Controller
```bash
cd docker
docker compose --profile ha-controller up -d ov-recorder-ha-controller
```

## Configuration

The system uses two configuration files:
- **Main config**: `.env` (generated during installation)
- **Recording config**: `{OPENVIDU_RECORDING_PATH}/.env` (automatically copied)

**Important**: When you modify `.env`, always copy it to the OpenVidu recording path:
```bash
cp .env /opt/openvidu/recordings/.env
```

## FAQ

**Q: Is this project part of the OpenVidu official distribution?**  
A: No, it's an enhancement made by the company that provides the official support for OpenVidu. We are close related with the OpenVidu development but we are not the official development team.

**Q: Do I have to change my OpenVidu server installation?**
A: No, just add the webhook configuration and restart OpenVidu.

**Q: How does failover work?**  
A: The system monitors recording containers via heartbeats. If a container stops responding or gets stuck, it automatically deploys a backup container and recovers the session.

**Q: Where are the chunks of the recordings stored?**  
A: By default in S3-compatible storage (MinIO). The system supports both local and S3 storage modes.

**Q: Can I use AWS S3 instead of MinIO?**  
A: Yes, configure the S3 endpoints and credentials in the `.env` file during installation.

**Q: Do I need an S3 account?**
A: No, the solution provides a substitute for S3 using MinIO, which is installed as part of the solution.

**Q: How do I check if the system is working?**  
A: Use `cd docker && ./ov2-ha-recorder.sh test-api` to test all components.

**Q: What OpenVidu versions are supported?**  
A: Currently only OpenVidu 2.xx.x are supported. The system automatically detects and matches your OpenVidu installation version.

**Q: How do I backup my configuration?**  
A: Use `cd docker && ./ov2-ha-recorder.sh backup` to create a complete backup.

**Q: I'm getting webhook errors in OpenVidu logs**  
A: Ensure your OpenVidu `.env` has the correct `OPENVIDU_WEBHOOK_ENDPOINT` URL and the HA Controller is running.

## Service URLs

After installation, access these endpoints:
- **HA Controller API**: `http://YOUR_IP:15443/api/sessions`
- **HA Controller Health**: `http://YOUR_IP:15443/actuator/health`  
- **MinIO Console**: `http://YOUR_IP:9001`

## Support

- **Documentation**: [README.full.md](README.full.md)
- **API Reference**: Available at `/swagger-ui.html` when running. Also, a postman collection is included.

## License

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
