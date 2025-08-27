package com.naevatec.ovrecorder.service;

import com.github.dockerjava.api.async.ResultCallback;
import com.github.dockerjava.api.command.*;
import java.util.*;
import java.util.regex.*;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.concurrent.ConcurrentHashMap;

import com.naevatec.ovrecorder.model.RecordingSession;
import com.naevatec.ovrecorder.repository.SessionRepository;
import lombok.RequiredArgsConstructor;

// Fixed Docker imports with HttpClient5
import com.github.dockerjava.api.DockerClient;
import com.github.dockerjava.api.model.*;
import com.github.dockerjava.core.DefaultDockerClientConfig;
import com.github.dockerjava.core.DockerClientBuilder;
import com.github.dockerjava.httpclient5.ApacheDockerHttpClient;  // NEW: HttpClient5 import

@Service
@RequiredArgsConstructor
@Slf4j
public class FailoverService {

    private final SessionRepository sessionRepository;

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

    @Value("${app.docker.image.name:openvidu/openvidu-record}")
    private String openviduRecordImage;

    @Value("${app.docker.image.tag:2.31.0}")
    private String imageTag;

    @Value("${app.docker.network:bridge}")
    private String dockerNetwork;

    @Value("${app.docker.socket-path:/var/run/docker.sock}")
    private String dockerSocketPath;

    @Value("${app.failover.backup-container-prefix:backup-recorder}")
    private String backupContainerPrefix;

	@Value ("${app.openvidu.recording.path:/opt/openvidu/recordings}")
	private String recordingPath;

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

	@Value("${app.docker.shm-size:536870912}")
	private long shmSize; // Default 512MB in bytes

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
        log.info("🔗 Failover service initialized (Docker client will be created on first use)");
        log.info("   🐳 Docker socket path: {}", dockerSocketPath);
        log.info("   \uD83D\uDCF8 OpenVidu image: {}:{}", openviduRecordImage, imageTag);
        log.info("   \uD83D\uDEDC Docker network: {}", dockerNetwork);
		log.info("   \uD83D\uDC93 Heartbeat timeout: {} seconds", heartbeatTimeoutSeconds);
		log.info("   \uD83D\uDE35 Stuck chunk timeout: {} seconds", stuckChunkTimeoutSeconds);
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

			// Build Docker client configuration with explicit socket path
			DefaultDockerClientConfig.Builder configBuilder = DefaultDockerClientConfig.createDefaultConfigBuilder();

			// Always use the mounted Docker socket when running in container
			String dockerHost = "unix://" + dockerSocketPath;
			log.info("🔗 Using Docker socket: {}", dockerHost);

			DefaultDockerClientConfig config = configBuilder
				.withDockerHost(dockerHost)  // <-- NEW: Explicit docker host
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
	        log.info("🧪 Testing Docker connection...");  // <-- NEW: Better logging
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

			// NEW: Additional debugging information
			log.error("🔍 Docker client debug info:");
			log.error("   - Docker socket path: {}", dockerSocketPath);
			log.error("   - File exists: {}", java.nio.file.Files.exists(java.nio.file.Paths.get(dockerSocketPath)));
			log.error("   - File readable: {}", java.nio.file.Files.isReadable(java.nio.file.Paths.get(dockerSocketPath)));

			// Check if docker.sock is mounted correctly
			try {
				java.nio.file.Path socketPath = java.nio.file.Paths.get(dockerSocketPath);
				if (java.nio.file.Files.exists(socketPath)) {
					log.error("   - Socket permissions: {}", java.nio.file.Files.getPosixFilePermissions(socketPath));
				} else {
					log.error("   - Socket file does not exist - check Docker socket mount in docker-compose.yml");
				}
			} catch (Exception permException) {
				log.error("   - Cannot check socket permissions: {}", permException.getMessage());
			}

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
                forceStopBackupContainer(sessionId);
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

		if (dockerClient == null) {
			log.info("🔗 Docker client not initialized yet, initializing now...");
			try {
				getDockerClient();
			} catch (Exception e) {
				log.warn("⚠️ Docker client initialization failed, skipping this failover check: {}", e.getMessage());
				return;
			}
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

        // Skip inactive sessions. Should not happen, we have filtered them out
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
		// This means container is alive but not progressing (ffmpeg stuck)
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
	 * Send graceful stop signal to backup container (like OpenVidu does)
	 * This allows FFmpeg to finish chunk processing, join files, and generate metadata
	 */
	public boolean stopBackupContainerGracefully(String sessionId) {
		String containerId = activeBackupContainers.get(sessionId);
		if (containerId == null) {
			log.warn("No backup container found for session: {}", sessionId);
			return false;
		}

		try {
			log.info("🛑 Sending graceful stop signal to backup container {} for session {}", containerId, sessionId);

			DockerClient client = getDockerClient();

			// First, send the 'q' command to FFmpeg (same as OpenVidu approach)
			boolean stopSignalSent = sendStopSignalToContainer(containerId);

			if (!stopSignalSent) {
				log.warn("Failed to send stop signal to container {}, falling back to force stop", containerId);
				return forceStopBackupContainer(sessionId);
			}

			// Wait for container to finish gracefully (up to 120 seconds for chunk processing)
			boolean gracefulShutdown = waitForContainerCompletion(containerId, 120);

			if (gracefulShutdown) {
				log.info("✅ Backup container {} completed gracefully", containerId);
			} else {
				log.warn("⏰ Container {} did not complete within timeout, forcing shutdown", containerId);
				// Force stop after timeout
				return forceStopBackupContainer(sessionId);
			}

			// Clean up tracking
			activeBackupContainers.remove(sessionId);

			// Update session record
			updateSessionBackupContainerInfo(sessionId, null, null);

			log.info("✅ Gracefully stopped backup container for session: {}", sessionId);
			return true;

		} catch (Exception e) {
			log.error("❌ Error during graceful stop of backup container {} for session {}: {}",
					 containerId, sessionId, e.getMessage(), e);

			// Fallback to force stop
			return forceStopBackupContainer(sessionId);
		}
	}

	/**
	 * Send stop signal to container using Docker exec (equivalent to OpenVidu's approach)
	 */
	private boolean sendStopSignalToContainer(String containerId) {
		try {
			DockerClient client = getDockerClient();

			log.debug("📡 Sending 'echo q > stop' command to container: {}", containerId);

			// Create exec command - equivalent to OpenVidu's approach
			ExecCreateCmdResponse execCreateCmdResponse = client.execCreateCmd(containerId)
				.withAttachStdout(true)
				.withAttachStderr(true)
				.withCmd("bash", "-c", "echo 'q' > stop")
				.exec();

			// Execute the command asynchronously
			client.execStartCmd(execCreateCmdResponse.getId())
				.exec(new ResultCallback.Adapter<Frame>() {
					@Override
					public void onNext(Frame frame) {
						String output = new String(frame.getPayload()).trim();
						if (!output.isEmpty()) {
							log.debug("[CONTAINER-{}] {}", containerId.substring(0, 8), output);
						}
					}

					@Override
					public void onError(Throwable throwable) {
						log.warn("Error in exec callback for container {}: {}", containerId, throwable.getMessage());
					}

					@Override
					public void onComplete() {
						log.debug("Stop signal command completed for container: {}", containerId);
					}
				});

			log.info("✅ Stop signal sent to backup container: {}", containerId);
			return true;

		} catch (Exception e) {
			log.error("❌ Failed to send stop signal to container {}: {}", containerId, e.getMessage(), e);
			return false;
		}
	}

	/**
	 * Wait for container to complete processing and exit
	 */
	private boolean waitForContainerCompletion(String containerId, int timeoutSeconds) {
		try {
			DockerClient client = getDockerClient();

			log.info("⏳ Waiting up to {} seconds for container {} to complete gracefully...",
					timeoutSeconds, containerId);

			long startTime = System.currentTimeMillis();
			long timeoutMillis = timeoutSeconds * 1000L;

			while ((System.currentTimeMillis() - startTime) < timeoutMillis) {
				try {
					// Check container status
					InspectContainerResponse containerInfo = client.inspectContainerCmd(containerId).exec();

					if (containerInfo.getState().getRunning() == null || !containerInfo.getState().getRunning()) {
						// Container has stopped
						String exitCode = containerInfo.getState().getExitCode() != null ?
										containerInfo.getState().getExitCode().toString() : "unknown";

						log.info("🏁 Container {} stopped with exit code: {}", containerId, exitCode);

						// Clean up the stopped container
						try {
							client.removeContainerCmd(containerId).withForce(true).exec();
							log.debug("🗑️ Removed stopped container: {}", containerId);
						} catch (Exception e) {
							log.warn("Failed to remove stopped container {}: {}", containerId, e.getMessage());
						}

						return true;
					}

					// Log progress every 10 seconds
					long elapsed = (System.currentTimeMillis() - startTime) / 1000;
					if (elapsed % 10 == 0 && elapsed > 0) {
						log.debug("⏳ Still waiting for container {} completion... ({}s elapsed)",
								 containerId, elapsed);
					}

					// Check every 2 seconds
					Thread.sleep(2000);

				} catch (InterruptedException e) {
					log.warn("Wait interrupted for container: {}", containerId);
					Thread.currentThread().interrupt();
					return false;
				} catch (Exception e) {
					log.debug("Error checking container status (container may have stopped): {}", e.getMessage());
					// Container might have been removed already, consider it stopped
					return true;
				}
			}

			log.warn("⏰ Timeout waiting for container {} to complete gracefully", containerId);
			return false;

		} catch (Exception e) {
			log.error("❌ Error waiting for container completion: {}", e.getMessage(), e);
			return false;
		}
	}

	/**
	 * Force stop backup container (original method renamed for clarity)
	 */
	public boolean forceStopBackupContainer(String sessionId) {
		String containerId = activeBackupContainers.get(sessionId);
		if (containerId == null) {
			log.warn("No backup container found for session: {}", sessionId);
			return false;
		}

		try {
			log.info("💥 Force stopping backup container {} for session {}", containerId, sessionId);

			DockerClient client = getDockerClient();

			// Force stop container (with timeout)
			client.stopContainerCmd(containerId)
				.withTimeout(10)  // Shorter timeout for force stop
				.exec();

			// Remove container
			client.removeContainerCmd(containerId)
				.withForce(true)
				.exec();

			// Remove from tracking
			activeBackupContainers.remove(sessionId);

			// Update session record
			updateSessionBackupContainerInfo(sessionId, null, null);

			log.info("✅ Force stopped backup container for session: {}", sessionId);
			return true;

		} catch (Exception e) {
			log.error("❌ Failed to force stop backup container {} for session {}: {}",
					 containerId, sessionId, e.getMessage(), e);
			return false;
		}
	}

	/**
	 * Update session backup container information
	 */
	private void updateSessionBackupContainerInfo(String sessionId, String containerId, String containerName) {
		try {
			var sessionOpt = sessionRepository.findById(sessionId);
			if (sessionOpt.isPresent()) {
				RecordingSession session = sessionOpt.get();
				session.setBackupContainerId(containerId);
				session.setBackupContainerName(containerName);
				sessionRepository.update(session);
			}
		} catch (Exception e) {
			log.warn("Failed to update session backup container info for {}: {}", sessionId, e.getMessage());
		}
	}

	/**
	 * Rename the original stopBackupContainer method for clarity
	 */
	public boolean stopBackupContainer(String sessionId) {
		// Default to graceful stop
		return stopBackupContainerGracefully(sessionId);
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
			// must be recording_eiglesia23_1. Must change the ~ for an _
			String suffix = sessionId.replaceAll("[^a-zA-Z0-9_.-]", "_");
			String prefix = "recording_";
			suffix = ensureSessionIdLength(sessionId, prefix);
            String containerName = prefix + suffix;

			// Ensure container name is unique by killing any container with same name
			try {
				var existingContainers = client.listContainersCmd()
					.withShowAll(true)
					.withNameFilter(java.util.List.of(containerName))
					.exec();
				for (var existing : existingContainers) {
					log.warn("⚠️ Found existing container with name {}, removing it", containerName);
					client.removeContainerCmd(existing.getId())
						.withForce(true)
						.exec();
				}
			} catch (Exception e) {
				log.warn("⚠️ Error checking/removing existing container with name {}: {}", containerName, e.getMessage());
			}

            // Determine starting chunk
            String startChunk = determineStartChunk(session);

            // Prepare environment variables
            var envVars = buildEnvironmentVariables(session, startChunk);

			// Volume bindings (if any) can be added here
			Volume volume1 = new Volume("/recordings");
			List<Volume> volumes = new ArrayList<>();
			volumes.add(volume1);
			Bind bind1 = new Bind(recordingPath, volume1);
			List<Bind> binds = new ArrayList<>();
			binds.add(bind1);

            // Create container
			CreateContainerResponse container = client.createContainerCmd(openviduRecordImage + ":" + imageTag)
                .withName(containerName)
                .withEnv(envVars.toArray(new String[0]))
                .withVolumes(volumes.toArray(new Volume[0]))
                .withHostConfig(HostConfig.newHostConfig()
                    .withNetworkMode("host")  // Use host network like OpenVidu
                    .withBinds(binds)
                    .withAutoRemove(false)    // Don't auto-remove for debugging
                    .withRestartPolicy(RestartPolicy.noRestart())
                    .withShmSize(shmSize))   // Configurable via properties
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
		log.debug("Determining start chunk for session {}: lastChunk='{}'", session.getSessionId(), lastChunk);

		if (lastChunk != null && !lastChunk.trim().isEmpty()) {
			try {
				// More precise regex to extract just the numeric part before the file extension
				Pattern pattern = Pattern.compile("^(\\d+)\\.");
				Matcher matcher = pattern.matcher(lastChunk.trim());

				if (matcher.find()) {
					String chunkNumber = matcher.group(1);
					log.debug("Extracted chunk number for session {}: '{}'", session.getSessionId(), chunkNumber);

					int currentChunk = Integer.parseInt(chunkNumber);
					int nextChunk = currentChunk + 1;

					log.debug("Current chunk: {}, Next chunk for session {}: {}", currentChunk, session.getSessionId(), nextChunk);
					return String.format("%04d", nextChunk);
				} else {
					log.warn("Could not extract chunk number from filename: '{}'", lastChunk);
				}
			} catch (NumberFormatException e) {
				log.warn("Failed to parse chunk number from: '{}', error: {}", lastChunk, e.getMessage());
			}
		} else {
			log.debug("No lastChunk provided for session {}, using default", session.getSessionId());
		}

		// Default to chunk 0000 if we can't determine (backup starts from beginning)
		log.debug("Using default start chunk 0000 for session {}", session.getSessionId());
		return "0000";
	}

	/**
	 * Parse environment JSON from session into a Map
	 * @param session
	 * @return
	 */
	 private java.util.Map<String, Object> parseEnvironmentData(RecordingSession session) {
		if (session.getEnvironment() == null || session.getEnvironment().trim().isEmpty()) {
			return new java.util.HashMap<>();
		}

		try {
			com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
			return mapper.readValue(session.getEnvironment(),
				new com.fasterxml.jackson.core.type.TypeReference<java.util.Map<String, Object>>() {});
		} catch (Exception e) {
			log.warn("Failed to parse environment JSON for session {}: {}", session.getSessionId(), e.getMessage());
			return new java.util.HashMap<>();
		}
	}

    /**
     * Build environment variables for backup recording container using session data
     */
    private java.util.List<String> buildEnvironmentVariables(RecordingSession session, String startChunk) {
        java.util.List<String> envVars = new java.util.ArrayList<>();

        try {
            // Parse environment JSON from session
            final java.util.Map<String, Object> environmentData = parseEnvironmentData(session);
			if (environmentData.isEmpty()) {
				log.warn("No environment data found in session {}, using minimal variables", session.getSessionId());
			}

            // Helper function to get environment value with fallback
            java.util.function.Function<String, String> getEnvValue = (key) -> {
                Object value = environmentData.get(key);
                return value != null ? value.toString() : "";
            };

            // Core recording variables from environment data
            envVars.add("DEBUG_MODE=" + getEnvValue.apply("debugMode"));
            envVars.add("CONTAINER_WORKING_MODE=" + getEnvValue.apply("containerWorkingMode"));
            envVars.add("URL=" + getEnvValue.apply("url"));
            envVars.add("ONLY_VIDEO=" + getEnvValue.apply("onlyVideo"));
            envVars.add("RESOLUTION=" + getEnvValue.apply("resolution"));
            envVars.add("FRAMERATE=" + getEnvValue.apply("framerate"));
            envVars.add("VIDEO_ID=" + getEnvValue.apply("videoId"));
            envVars.add("VIDEO_NAME=" + getEnvValue.apply("videoName"));
            envVars.add("VIDEO_FORMAT=" + getEnvValue.apply("videoFormat"));
            envVars.add("RECORDING_JSON=" + getEnvValue.apply("recordingJson"));

            // Backup container specific variables
            envVars.add("START_CHUNK=" + startChunk);
            envVars.add("IS_RECOVERY_CONTAINER=true");  // Always true for backup containers

            // Original container information
            envVars.add("ORIGINAL_CLIENT_HOST=" + (session.getClientHost() != null ? session.getClientHost() : "unknown"));
            envVars.add("ORIGINAL_HOSTNAME=" + getEnvValue.apply("hostname"));
            envVars.add("ORIGINAL_CONTAINER_IP=" + getEnvValue.apply("containerIp"));

            log.debug("Built {} environment variables for backup container", envVars.size());
            if (log.isTraceEnabled()) {
                envVars.forEach(var -> {
                    // Don't log sensitive data
                    if (var.contains("PASSWORD") || var.contains("SECRET")) {
                        log.trace("  - {}", var.replaceAll("=.*", "=[HIDDEN]"));
                    } else {
                        log.trace("  - {}", var);
                    }
                });
            }

        } catch (Exception e) {
            log.error("Error building environment variables for session {}: {}", session.getSessionId(), e.getMessage(), e);

            // Fallback to basic environment variables if parsing fails
            envVars.clear();
            envVars.add("VIDEO_ID=" + session.getSessionId());
            envVars.add("VIDEO_NAME=" + session.getSessionId());
            envVars.add("START_CHUNK=" + startChunk);
            envVars.add("ONLY_VIDEO=" + false);
            envVars.add("RESOLUTION=" + "1280x720");
            envVars.add("FRAMERATE=" + 25);
			envVars.add("VIDEO_FORMAT=mp4");
            envVars.add("SESSION_ID=" + session.getSessionId());
            envVars.add("CLIENT_ID=" + session.getClientId() + "-backup");
            envVars.add("IS_RECOVERY_CONTAINER=true");
            envVars.add("HA_CONTROLLER_HOST=" + controllerHost);
            envVars.add("HA_CONTROLLER_PORT=" + controllerPort);
            envVars.add("HA_CONTROLLER_USERNAME=" + securityUsername);
            envVars.add("HA_CONTROLLER_PASSWORD=" + securityPassword);
            envVars.add("RECORDING_BASE_URL=" + recordingBaseUrl);
            envVars.add("HEARTBEAT_INTERVAL=10");
            envVars.add("ORIGINAL_CLIENT_HOST=" + (session.getClientHost() != null ? session.getClientHost() : "unknown"));

            log.warn("Using fallback environment variables for session: {}", session.getSessionId());
        }

        return envVars;
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
            forceStopBackupContainer(sessionId);
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

	private String ensureSessionIdLength(String sessionId, String recordingPrefix) {
		int maxLength = 63;

		// If the full name would exceed the limit, trim the sessionId from the beginning
		if (recordingPrefix.length() + sessionId.length() > maxLength) {
			int allowedSessionIdLength = maxLength - recordingPrefix.length();
			sessionId = sessionId.substring(sessionId.length() - allowedSessionIdLength);
		}

		return sessionId;
	}

}
