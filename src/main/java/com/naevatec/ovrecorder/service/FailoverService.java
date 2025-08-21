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

// Step 2: Uncomment basic Docker imports
import com.github.dockerjava.api.DockerClient;
import com.github.dockerjava.api.command.CreateContainerResponse;
import com.github.dockerjava.api.model.*;
import com.github.dockerjava.core.DefaultDockerClientConfig;
import com.github.dockerjava.core.DockerClientBuilder;

@Service
@RequiredArgsConstructor
@Slf4j
public class FailoverService {

    private final SessionRepository sessionRepository;
    private final SessionService sessionService;

    // Configuration properties
    @Value("${app.failover.enabled:true}")  // Step 2: Enable by default
    private boolean failoverEnabled;

    @Value("${app.failover.heartbeat-timeout:300}")
    private long heartbeatTimeoutSeconds;

    @Value("${app.failover.stuck-chunk-timeout:180}")
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

    @Value("${CONTROLLER_HOST:ov-recorder}")
    private String controllerHost;

    @Value("${CONTROLLER_PORT:8080}")
    private String controllerPort;

    @Value("${APP_SECURITY_USERNAME:recorder}")
    private String securityUsername;

    @Value("${APP_SECURITY_PASSWORD:rec0rd3r_2024!}")
    private String securityPassword;

    // Step 2: Uncomment Docker client variable
    private DockerClient dockerClient;
    private final Map<String, String> activeBackupContainers = new ConcurrentHashMap<>();

    @PostConstruct
    public void initializeDockerClient() {
        if (!failoverEnabled) {
            log.info("Failover service is disabled");
            return;
        }

        try {
            // Step 2: Uncomment basic Docker client creation
            dockerClient = DockerClientBuilder.getInstance().build();

            // Test connection
            dockerClient.pingCmd().exec();
            log.info("Successfully connected to Docker daemon");

            // Step 3: Add image pulling
            pullOpenViduImageIfNeeded();

        } catch (Exception e) {
            log.error("Failed to initialize Docker client: {}", e.getMessage(), e);
            if (failoverEnabled) {
                throw new RuntimeException("Cannot initialize Docker client for failover service", e);
            }

            // Step 3: Clean up completed backup containers
            cleanupCompletedBackupContainers();
        }
    }

    @PreDestroy
    public void cleanup() {
        log.info("Cleaning up failover service");

        // Step 2: Add basic Docker client cleanup
        if (dockerClient != null) {
            try {
                dockerClient.close();
            } catch (Exception e) {
                log.warn("Error closing Docker client: {}", e.getMessage());
            }
        }
    }

    /**
     * Scheduled task to detect failed sessions (Docker launching disabled for now)
     */
    @Scheduled(fixedDelayString = "${app.failover.check-interval:60000}")
    public void detectAndHandleFailedSessions() {
        if (!failoverEnabled) {
            return;
        }

        log.debug("Starting failover detection scan...");

        try {
            var allSessions = sessionRepository.findAllActiveSessions();
            LocalDateTime now = LocalDateTime.now();

            for (RecordingSession session : allSessions) {
                if (shouldStartBackupRecording(session, now)) {
                    // Step 3: Uncomment container launching
                    startBackupRecording(session);
                }
            }

        } catch (Exception e) {
            log.error("Error during failover detection: {}", e.getMessage(), e);
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
                log.warn("Session {} heartbeat timeout: {} seconds > {} threshold",
                    sessionId, secondsSinceLastHeartbeat, heartbeatTimeoutSeconds);
                return true;
            }
        }

        // Check stuck chunk detection (same chunk for too long)
        if (session.getLastChunk() != null && session.getLastHeartbeat() != null) {
            long secondsSinceLastChunk = Duration.between(session.getLastHeartbeat(), now).getSeconds();

            if (secondsSinceLastChunk > stuckChunkTimeoutSeconds) {
                log.warn("Session {} stuck chunk detected: chunk '{}' for {} seconds > {} threshold",
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
            log.info("Stopping backup container {} for session {}", containerId, sessionId);

            // Stop container (with timeout)
            dockerClient.stopContainerCmd(containerId)
                .withTimeout(30)
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

            log.info("Successfully stopped backup container for session: {}", sessionId);
            return true;

        } catch (Exception e) {
            log.error("Failed to stop backup container {} for session {}: {}", containerId, sessionId, e.getMessage(), e);
            return false;
        }
    }

    /**
     * Start a backup recording container for a failed session
     */
    private void startBackupRecording(RecordingSession session) {
        String sessionId = session.getSessionId();

        try {
            log.info("Starting backup recording for session: {}", sessionId);

            // Generate container name
            String containerName = String.format("%s-%s-%d",
                backupContainerPrefix, sessionId, System.currentTimeMillis());

            // Prepare environment variables
            var envVars = buildEnvironmentVariables(session);

            // Create container
            CreateContainerResponse container = dockerClient.createContainerCmd(openviduRecordImage + ":" + imageTag)
                .withName(containerName)
                .withEnv(envVars.toArray(new String[0]))
                .withNetworkMode(dockerNetwork)
                .withHostConfig(HostConfig.newHostConfig()
                    .withAutoRemove(true)
                    .withRestartPolicy(RestartPolicy.noRestart()))
                .withLabels(Map.of(
                    "session.id", sessionId,
                    "container.type", "backup-recorder",
                    "created.by", "ha-controller"))
                .exec();

            String containerId = container.getId();

            // Start container
            dockerClient.startContainerCmd(containerId).exec();

            // Update session with backup container info
            session.setBackupContainerId(containerId);
            session.setBackupContainerName(containerName);
            sessionRepository.update(session);

            // Track active backup container
            activeBackupContainers.put(sessionId, containerId);

            log.info("Successfully started backup container {} for session {}", containerId, sessionId);

        } catch (Exception e) {
            log.error("Failed to start backup recording for session {}: {}", sessionId, e.getMessage(), e);
        }
    }

    /**
     * Build environment variables for backup recording container
     */
    private java.util.List<String> buildEnvironmentVariables(RecordingSession session) {
        return java.util.List.of(
            "SESSION_ID=" + session.getSessionId(),
            "CLIENT_ID=" + session.getClientId() + "-backup",
            "RECORDING_BASE_URL=" + recordingBaseUrl,
            "CONTROLLER_HOST=" + controllerHost,
            "CONTROLLER_PORT=" + controllerPort,
            "APP_SECURITY_USERNAME=" + securityUsername,
            "APP_SECURITY_PASSWORD=" + securityPassword,
            "HEARTBEAT_INTERVAL=30",
            "BACKUP_MODE=true",
            "ORIGINAL_CLIENT_HOST=" + (session.getClientHost() != null ? session.getClientHost() : "unknown"),
            "METADATA=" + (session.getMetadata() != null ? session.getMetadata() : "{}"),
            "RECORDING_PATH=" + (session.getRecordingPath() != null ? session.getRecordingPath() : "")
        );
    }

    /**
     * Pull OpenVidu recording image if not present locally
     */
    private void pullOpenViduImageIfNeeded() {
        try {
            String fullImageName = openviduRecordImage + ":" + imageTag;

            // Check if image exists locally
            try {
                dockerClient.inspectImageCmd(fullImageName).exec();
                log.info("OpenVidu recording image {} already exists locally", fullImageName);
                return;
            } catch (Exception e) {
                log.info("OpenVidu recording image {} not found locally, pulling...", fullImageName);
            }

            // Pull the image
            dockerClient.pullImageCmd(openviduRecordImage)
                .withTag(imageTag)
                .start()
                .awaitCompletion();

            log.info("Successfully pulled OpenVidu recording image: {}", fullImageName);

        } catch (Exception e) {
            log.error("Failed to pull OpenVidu recording image: {}", e.getMessage(), e);
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
        return Map.of(
            "enabled", failoverEnabled,
            "heartbeatTimeoutSeconds", heartbeatTimeoutSeconds,
            "stuckChunkTimeoutSeconds", stuckChunkTimeoutSeconds,
            "checkIntervalMs", checkIntervalMs,
            "activeBackupContainers", activeBackupContainers.size(),
            "backupContainerDetails", activeBackupContainers,
            "dockerConnected", dockerClient != null,  // Step 2: Update status
            "openviduImage", openviduRecordImage + ":" + imageTag
        );
    }

    /**
     * Manual trigger for failover detection (for testing/debugging)
     */
    public Map<String, Object> triggerManualFailoverCheck() {
        log.info("Manual failover check triggered");

        if (!failoverEnabled) {
            return Map.of("error", "Failover is disabled");
        }

        try {
            detectAndHandleFailedSessions();
            return Map.of(
                "message", "Manual failover check completed",
                "timestamp", LocalDateTime.now(),
                "activeBackupContainers", activeBackupContainers.size()
            );
        } catch (Exception e) {
            log.error("Manual failover check failed: {}", e.getMessage(), e);
            return Map.of(
                "error", "Manual failover check failed: " + e.getMessage(),
                "timestamp", LocalDateTime.now()
            );
        }
    }
}
