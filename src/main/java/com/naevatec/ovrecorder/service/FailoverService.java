package com.naevatec.ovrecorder.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import com.naevatec.ovrecorder.model.RecordingSession;
import com.naevatec.ovrecorder.repository.SessionRepository;
import lombok.RequiredArgsConstructor;

// Fixed Docker imports with HttpClient5
import com.github.dockerjava.api.DockerClient;
import com.github.dockerjava.api.command.CreateContainerResponse;
import com.github.dockerjava.api.model.*;
import com.github.dockerjava.core.DefaultDockerClientConfig;
import com.github.dockerjava.core.DockerClientBuilder;
import com.github.dockerjava.httpclient5.ApacheDockerHttpClient;  // NEW: HttpClient5 import

@Service
@RequiredArgsConstructor
@Slf4j
public class FailoverService {

    private final SessionRepository sessionRepository;
    private final SessionService sessionService;

    // Configuration properties
    @Value("${app.failover.enabled:true}")
    private boolean failoverEnabled;

	@Value("${app.session.heartbeat:300}")
    private long heartbeatTimeSeconds;

	@Value("${app.failover.heartbeat-max-lost:3}")
	private long maxLostHeartbeats;

	private long heartbeatTimeoutSeconds;

    @Value("${app.failover.chunk.time:10}")
	private long chunkTimeSeconds;

    private long stuckChunkTimeoutSeconds;

    @Value("${app.failover.check-interval:60000}")
    private long checkIntervalMs;

    @Value("${app.docker.openvidu-image:openvidu/openvidu-record}")
    private String openviduRecordImage;

    @Value("${app.docker.image-tag:2.31.0}")
    private String imageTag;

    @Value("${app.docker.network:bridge}")
    private String dockerNetwork;

    @Value("${app.docker.socket-path:/var/run/docker.sock}")
    private String dockerSocketPath;

    @Value("${app.failover.backup-container-prefix:backup-recorder}")
    private String backupContainerPrefix;

    // Environment variables for backup containers
    @Value("${RECORDING_BASE_URL:}")
    private String recordingBaseUrl;

    @Value("${HA_CONTROLLER_HOST:ov-recorder}")
    private String controllerHost;

    @Value("${HA_CONTROLLER_PORT:8080}")
    private String controllerPort;

    @Value("${HA_CONTROLLER_USERNAME:recorder}")
    private String securityUsername;

    @Value("${HA_CONTROLLER_PASSWORD:rec0rd3r_2024!}")
    private String securityPassword;

    private DockerClient dockerClient;
    private volatile boolean dockerInitialized = false;
    private volatile boolean dockerInitializationFailed = false;
    private final Map<String, String> activeBackupContainers = new ConcurrentHashMap<>();

    @PostConstruct
    public void postConstruct() {
        if (!failoverEnabled) {
            log.info("Failover service is disabled");
            return;
        }
		heartbeatTimeoutSeconds = heartbeatTimeSeconds * maxLostHeartbeats;
		stuckChunkTimeoutSeconds = chunkTimeSeconds * maxLostHeartbeats; // 3 times chunk duration
        log.info("✅ Failover service initialized (Docker client will be created on first use)");
        log.info("Docker socket path: {}", dockerSocketPath);
        log.info("OpenVidu image: {}:{}", openviduRecordImage, imageTag);
        log.info("Docker network: {}", dockerNetwork);
		log.info("Heartbeat timeout: {} seconds", heartbeatTimeoutSeconds);
		log.info("Stuck chunk timeout: {} seconds", stuckChunkTimeoutSeconds);
    }

    /**
     * Lazy initialization of Docker client - only connects when actually needed
     */
    private synchronized DockerClient getDockerClient() {
        if (!failoverEnabled) {
            throw new IllegalStateException("Failover service is disabled");
        }

        if (dockerInitializationFailed) {
            throw new IllegalStateException("Docker client initialization previously failed");
        }

        if (dockerClient != null && dockerInitialized) {
            return dockerClient;
        }

        try {
            log.info("🐳 Lazy initializing Docker client with HttpClient5 transport...");

            // Use Docker context configuration (respects remote contexts)
            DefaultDockerClientConfig config = DefaultDockerClientConfig.createDefaultConfigBuilder()
                // Don't specify dockerHost - let it use the current Docker context
                .build();

            ApacheDockerHttpClient httpClient = new ApacheDockerHttpClient.Builder()
                .dockerHost(config.getDockerHost())
                .sslConfig(config.getSSLConfig())
                .maxConnections(100)
                .connectionTimeout(Duration.ofSeconds(30))
                .responseTimeout(Duration.ofSeconds(45))
                .build();

            dockerClient = DockerClientBuilder.getInstance(config)
                .withDockerHttpClient(httpClient)
                .build();

            // Test connection
            dockerClient.pingCmd().exec();
            log.info("✅ Successfully connected to Docker daemon with HttpClient5");

            dockerInitialized = true;

            // Pull OpenVidu image if needed (in background)
            try {
                pullOpenViduImageIfNeeded();
            } catch (Exception e) {
                log.warn("⚠️ Failed to pull OpenVidu image (non-critical): {}", e.getMessage());
            }

            // Clean up any existing backup containers (in background)
            try {
                cleanupCompletedBackupContainers();
            } catch (Exception e) {
                log.warn("⚠️ Failed to cleanup existing containers (non-critical): {}", e.getMessage());
            }

            return dockerClient;

        } catch (Exception e) {
            log.error("❌ Failed to initialize Docker client: {}", e.getMessage(), e);
            dockerInitializationFailed = true;
            throw new RuntimeException("Cannot initialize Docker client for failover service", e);
        }
    }

    @PreDestroy
    public void cleanup() {
        log.info("🧹 Cleaning up failover service");

        // Stop all active backup containers
        for (String sessionId : activeBackupContainers.keySet()) {
            try {
                stopBackupContainer(sessionId);
            } catch (Exception e) {
                log.warn("Error stopping backup container during cleanup: {}", e.getMessage());
            }
        }

        // Close Docker client
        if (dockerClient != null) {
            try {
                dockerClient.close();
                log.info("✅ Docker client closed successfully");
            } catch (Exception e) {
                log.warn("⚠️ Error closing Docker client: {}", e.getMessage());
            }
        }
    }

    /**
     * Scheduled task to detect failed sessions
     */
	@Scheduled(fixedDelayString = "#{${app.failover.check-interval:30} * 1000}", initialDelay = 15000)
    public void detectAndHandleFailedSessions() {
        if (!failoverEnabled) {
			log.debug("⚠️ Failover service is disabled");
            return;
        }

        log.debug("🔍 Starting failover detection scan...");

        try {
            var allSessions = sessionRepository.findAllActiveSessions();
            LocalDateTime now = LocalDateTime.now();

            for (RecordingSession session : allSessions) {
                if (shouldStartBackupRecording(session, now)) {
                    startBackupRecording(session);
                }
            }

        } catch (Exception e) {
            // Don't log Docker connection errors during scheduled checks
            if (e.getMessage().contains("Docker") || e.getMessage().contains("Unsupported protocol")) {
                log.debug("⚠️ Docker not available for failover detection: {}", e.getMessage());
            } else {
                log.error("❌ Error during failover detection: {}", e.getMessage(), e);
            }
        }
    }

    /**
     * Determine if a backup recording should be started for a session
     */
    private boolean shouldStartBackupRecording(RecordingSession session, LocalDateTime now) {
        String sessionId = session.getSessionId();

        // Skip if backup already running
        if (activeBackupContainers.containsKey(sessionId)) {
            log.debug("Backup already running for session: {}", sessionId);
            return false;
        }

        // Skip inactive sessions
        if (!session.isActive()) {
            log.debug("Session {} is inactive, skipping failover check", sessionId);
            return false;
        }

        // Check heartbeat timeout
        if (session.getLastHeartbeat() != null) {
            long secondsSinceLastHeartbeat = Duration.between(session.getLastHeartbeat(), now).getSeconds();

            if (secondsSinceLastHeartbeat > heartbeatTimeoutSeconds) {
                log.warn("⚠️ Session {} heartbeat timeout: {} seconds > {} threshold",
                    sessionId, secondsSinceLastHeartbeat, heartbeatTimeoutSeconds);
                return true;
            }
        }

        // Check stuck chunk detection (same chunk for too long)
        if (session.getLastChunk() != null && session.getLastHeartbeat() != null) {
            long secondsSinceLastChunk = Duration.between(session.getLastHeartbeat(), now).getSeconds();

            if (secondsSinceLastChunk > stuckChunkTimeoutSeconds) {
                log.warn("⚠️ Session {} stuck chunk detected: chunk '{}' for {} seconds > {} threshold",
                    sessionId, session.getLastChunk(), secondsSinceLastChunk, stuckChunkTimeoutSeconds);
                return true;
            }
        }

        return false;
    }

    /**
     * Stop a backup container for a session
     */
    public boolean stopBackupContainer(String sessionId) {
        String containerId = activeBackupContainers.get(sessionId);
        if (containerId == null) {
            log.warn("No backup container found for session: {}", sessionId);
            return false;
        }

        try {
            log.info("🛑 Stopping backup container {} for session {}", containerId, sessionId);

            DockerClient client = getDockerClient(); // Lazy initialization

            // Stop container (with timeout)
            client.stopContainerCmd(containerId)
                .withTimeout(30)
                .exec();

            // Remove container
            client.removeContainerCmd(containerId)
                .withForce(true)
                .exec();

            // Remove from tracking
            activeBackupContainers.remove(sessionId);

            // Update session record
            var sessionOpt = sessionRepository.findById(sessionId);
            if (sessionOpt.isPresent()) {
                RecordingSession session = sessionOpt.get();
                session.setBackupContainerId(null);
                session.setBackupContainerName(null);
                sessionRepository.update(session);
            }

            log.info("✅ Successfully stopped backup container for session: {}", sessionId);
            return true;

        } catch (Exception e) {
            log.error("❌ Failed to stop backup container {} for session {}: {}", containerId, sessionId, e.getMessage(), e);
            return false;
        }
    }

    /**
     * Start a backup recording container for a failed session
     */
    private void startBackupRecording(RecordingSession session) {
        String sessionId = session.getSessionId();

        try {
            log.info("🚀 Starting backup recording for session: {}", sessionId);

            DockerClient client = getDockerClient(); // Lazy initialization

            // Generate container name
            String containerName = String.format("%s-%s-%d",
                backupContainerPrefix, sessionId, System.currentTimeMillis());

            // Determine starting chunk
            String startChunk = determineStartChunk(session);

            // Prepare environment variables
            var envVars = buildEnvironmentVariables(session, startChunk);

            // Create container
            CreateContainerResponse container = client.createContainerCmd(openviduRecordImage + ":" + imageTag)
                .withName(containerName)
                .withEnv(envVars.toArray(new String[0]))
                .withNetworkMode(dockerNetwork)
                .withHostConfig(HostConfig.newHostConfig()
                    .withAutoRemove(false)  // Don't auto-remove for debugging
                    .withRestartPolicy(RestartPolicy.noRestart())
                    .withShmSize(2L * 1024 * 1024 * 1024)  // 2GB shared memory
                    .withMemory(4L * 1024 * 1024 * 1024)   // 4GB memory limit
                    .withCpuCount(2L))                      // 2 CPU cores
                .withLabels(Map.of(
                    "session.id", sessionId,
                    "container.type", "backup-recorder",
                    "created.by", "ha-controller",
                    "start.chunk", startChunk))
                .exec();

            String containerId = container.getId();

            // Start container
            client.startContainerCmd(containerId).exec();

            // Update session with backup container info
            session.setBackupContainerId(containerId);
            session.setBackupContainerName(containerName);
            sessionRepository.update(session);

            // Track active backup container
            activeBackupContainers.put(sessionId, containerId);

            log.info("✅ Successfully started backup container {} for session {} (starting from chunk {})",
                containerId, sessionId, startChunk);

        } catch (Exception e) {
            log.error("❌ Failed to start backup recording for session {}: {}", sessionId, e.getMessage(), e);
        }
    }

    /**
     * Determine the starting chunk number for backup container
     */
    private String determineStartChunk(RecordingSession session) {
        String lastChunk = session.getLastChunk();

        if (lastChunk != null && !lastChunk.isEmpty()) {
            try {
                // Extract chunk number from filename (e.g., "0003.mp4" -> "0003")
                String chunkNumber = lastChunk.replaceAll("[^0-9]", "");
                if (!chunkNumber.isEmpty()) {
                    int nextChunk = Integer.parseInt(chunkNumber) + 1;
                    return String.format("%04d", nextChunk);
                }
            } catch (NumberFormatException e) {
                log.warn("Failed to parse chunk number from: {}", lastChunk);
            }
        }

        // Default to chunk 0001 if we can't determine
        return "0001";
    }

    /**
     * Build environment variables for backup recording container
     */
    private java.util.List<String> buildEnvironmentVariables(RecordingSession session, String startChunk) {
        return java.util.List.of(
            "VIDEO_ID=" + session.getSessionId(),
            "VIDEO_NAME=" + session.getSessionId(),
            "START_CHUNK=" + startChunk,
            "SESSION_ID=" + session.getSessionId(),
            "CLIENT_ID=" + session.getClientId() + "-backup",
            "RECORDING_BASE_URL=" + recordingBaseUrl,
            "CONTROLLER_HOST=" + controllerHost,
            "CONTROLLER_PORT=" + controllerPort,
            "APP_SECURITY_USERNAME=" + securityUsername,
            "APP_SECURITY_PASSWORD=" + securityPassword,
            "HEARTBEAT_INTERVAL=10",
            "IS_BACKUP_CONTAINER=true",
            "ORIGINAL_CLIENT_HOST=" + (session.getClientHost() != null ? session.getClientHost() : "unknown"),
            "RECORDING_JSON=" + (session.getMetadata() != null ? session.getMetadata() : "{}"),
            "RECORDING_PATH=" + (session.getRecordingPath() != null ? session.getRecordingPath() : "")
        );
    }

    /**
     * Pull OpenVidu recording image if not present locally
     */
    private void pullOpenViduImageIfNeeded() {
        try {
            DockerClient client = getDockerClient(); // Lazy initialization
            String fullImageName = openviduRecordImage + ":" + imageTag;

            // Check if image exists locally
            try {
                client.inspectImageCmd(fullImageName).exec();
                log.info("✅ OpenVidu recording image {} already exists locally", fullImageName);
                return;
            } catch (Exception e) {
                log.info("🐳 OpenVidu recording image {} not found locally, pulling...", fullImageName);
            }

            // Pull the image
            client.pullImageCmd(openviduRecordImage)
                .withTag(imageTag)
                .start()
                .awaitCompletion();

            log.info("✅ Successfully pulled OpenVidu recording image: {}", fullImageName);

        } catch (Exception e) {
            log.error("❌ Failed to pull OpenVidu recording image: {}", e.getMessage(), e);
        }
    }

    /**
     * Clean up containers for completed sessions
     */
    private void cleanupCompletedBackupContainers() {
        var sessionsToClean = activeBackupContainers.keySet().stream()
            .filter(sessionId -> {
                var sessionOpt = sessionRepository.findById(sessionId);
                return sessionOpt.isEmpty() || !sessionOpt.get().isActive();
            })
            .collect(java.util.stream.Collectors.toList());

        for (String sessionId : sessionsToClean) {
            stopBackupContainer(sessionId);
        }
    }

    /**
     * Get failover status and statistics
     */
    public Map<String, Object> getFailoverStatus() {
        Map<String, Object> status = new java.util.HashMap<>();
        status.put("enabled", failoverEnabled);
        status.put("heartbeatTimeoutSeconds", heartbeatTimeoutSeconds);
        status.put("stuckChunkTimeoutSeconds", stuckChunkTimeoutSeconds);
        status.put("checkIntervalMs", checkIntervalMs);
        status.put("activeBackupContainers", activeBackupContainers.size());
        status.put("backupContainerDetails", activeBackupContainers);
        status.put("dockerInitialized", dockerInitialized);
        status.put("dockerInitializationFailed", dockerInitializationFailed);
        status.put("openviduImage", openviduRecordImage + ":" + imageTag);

        // Test Docker connection only if already initialized
        if (dockerInitialized && dockerClient != null) {
            try {
                dockerClient.pingCmd().exec();
                status.put("dockerStatus", "connected");
            } catch (Exception e) {
                status.put("dockerStatus", "error: " + e.getMessage());
            }
        } else if (dockerInitializationFailed) {
            status.put("dockerStatus", "initialization failed");
        } else {
            status.put("dockerStatus", "not initialized (lazy mode)");
        }

        return status;
    }

    /**
     * Manual trigger for failover detection (for testing/debugging)
     */
    public Map<String, Object> triggerManualFailoverCheck() {
        log.info("🔍 Manual failover check triggered");

        if (!failoverEnabled) {
            return Map.of("error", "Failover is disabled");
        }

        try {
            detectAndHandleFailedSessions();
            return Map.of(
                "message", "Manual failover check completed",
                "timestamp", LocalDateTime.now(),
                "activeBackupContainers", activeBackupContainers.size(),
                "dockerInitialized", dockerInitialized
            );
        } catch (Exception e) {
            log.error("❌ Manual failover check failed: {}", e.getMessage(), e);
            return Map.of(
                "error", "Manual failover check failed: " + e.getMessage(),
                "timestamp", LocalDateTime.now(),
                "dockerInitialized", dockerInitialized
            );
        }
    }
}
