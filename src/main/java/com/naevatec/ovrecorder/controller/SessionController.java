package com.naevatec.ovrecorder.controller;

import com.naevatec.ovrecorder.model.RecordingSession;
import com.naevatec.ovrecorder.service.SessionService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import jakarta.validation.Valid;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Session Controller for HA Recorder
 *
 * Manages recording session lifecycle with Redis storage
 * Supports session registration, heartbeat tracking, and cleanup
 */
@RestController
@RequestMapping("/api/sessions")
@RequiredArgsConstructor
@Slf4j
public class SessionController {

    private final SessionService sessionService;

    /**
     * Register a new recording session - Enhanced version
     */
    @PostMapping
    public ResponseEntity<?> registerSession(@RequestBody Map<String, Object> requestBody) {
        try {
            String sessionId = (String) requestBody.get("sessionId");
            String clientId = (String) requestBody.get("clientId");
            String clientHost = (String) requestBody.get("clientHost");

            if (sessionId == null || clientId == null) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "sessionId and clientId are required"));
            }

            // Extract additional fields for enhanced registration
            String uniqueSessionId = (String) requestBody.get("uniqueSessionId");
            String originalSessionId = (String) requestBody.get("originalSessionId");
            String statusStr = (String) requestBody.get("status");
            Object recordingJson = requestBody.get("recordingJson");
            Object environment = requestBody.get("environment");
            Object metadata = requestBody.get("metadata");

            // Create session with enhanced data
            RecordingSession session = RecordingSession.builder()
                .sessionId(sessionId)
                .clientId(clientId)
                .clientHost(clientHost)
                .uniqueSessionId(uniqueSessionId)
                .originalSessionId(originalSessionId)
                .status(parseSessionStatus(statusStr))
                .createdAt(LocalDateTime.now())
                .lastHeartbeat(LocalDateTime.now())
                .active(true)
                .build();

            // Set environment variables as JSON string if provided
            if (environment != null) {
                try {
                    session.setEnvironment(new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(environment));
                } catch (Exception e) {
                    log.warn("Failed to serialize environment variables: {}", e.getMessage());
                }
            }

            // Set metadata (prefer metadata field, fallback to recordingJson)
            if (metadata != null) {
                try {
                    session.setMetadata(new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(metadata));
                } catch (Exception e) {
                    log.warn("Failed to serialize metadata: {}", e.getMessage());
                }
            } else if (recordingJson != null) {
                try {
                    session.setMetadata(new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(recordingJson));
                } catch (Exception e) {
                    log.warn("Failed to serialize recordingJson as metadata: {}", e.getMessage());
                }
            }

            RecordingSession registeredSession = sessionService.registerSession(session);
            log.info("Session registered: {} (uniqueId: {}, originalId: {})",
                sessionId, uniqueSessionId, originalSessionId);

            return ResponseEntity.status(HttpStatus.CREATED).body(registeredSession);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest()
                .body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            log.error("Error registering session", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Internal server error"));
        }
    }

    /**
     * Helper method to parse session status
     */
    private RecordingSession.SessionStatus parseSessionStatus(String statusStr) {
        if (statusStr == null || statusStr.trim().isEmpty()) {
            return RecordingSession.SessionStatus.STARTING;
        }

        try {
            // Handle OpenVidu status mapping
            switch (statusStr.toLowerCase()) {
                case "started":
                case "starting":
                    return RecordingSession.SessionStatus.STARTING;
                case "recording":
                    return RecordingSession.SessionStatus.RECORDING;
                case "stopped":
                case "stopping":
                    return RecordingSession.SessionStatus.STOPPING;
                case "failed":
                    return RecordingSession.SessionStatus.FAILED;
                case "completed":
                    return RecordingSession.SessionStatus.COMPLETED;
                case "paused":
                    return RecordingSession.SessionStatus.PAUSED;
                case "inactive":
                    return RecordingSession.SessionStatus.INACTIVE;
                default:
                    return RecordingSession.SessionStatus.valueOf(statusStr.toUpperCase());
            }
        } catch (IllegalArgumentException e) {
            log.warn("Invalid status '{}', using STARTING", statusStr);
            return RecordingSession.SessionStatus.STARTING;
        }
    }

    /**
     * Update session heartbeat with optional chunk tracking
     */
    @PutMapping("/{sessionId}/heartbeat")
    public ResponseEntity<Map<String, Object>> updateHeartbeat(
            @PathVariable String sessionId,
            @RequestBody(required = false) Map<String, String> payload) {

        try {
            String lastChunk = null;
            if (payload != null) {
                lastChunk = payload.get("lastChunk");
            }

            Optional<RecordingSession> sessionOpt = sessionService.updateHeartbeatAndGet(sessionId, lastChunk);

            if (sessionOpt.isPresent()) {
                Map<String, Object> response = Map.of(
                    "message", "Heartbeat updated",
                    "sessionId", sessionId,
                    "timestamp", LocalDateTime.now().toString()
                );

                // Include chunk info in response if provided
                if (lastChunk != null && !lastChunk.isEmpty()) {
                    response = Map.of(
                        "message", "Heartbeat updated",
                        "sessionId", sessionId,
                        "timestamp", LocalDateTime.now().toString(),
                        "lastChunk", lastChunk
                    );
                }

                return ResponseEntity.ok(response);
            } else {
                return ResponseEntity.notFound().build();
            }
        } catch (Exception e) {
            log.error("Error updating heartbeat for session: {}", sessionId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Get a specific session by ID
     */
    @GetMapping("/{sessionId}")
    public ResponseEntity<RecordingSession> getSession(@PathVariable String sessionId) {
        try {
            Optional<RecordingSession> sessionOpt = sessionService.getSession(sessionId);
            return sessionOpt.map(ResponseEntity::ok)
                            .orElse(ResponseEntity.notFound().build());
        } catch (Exception e) {
            log.error("Error retrieving session: {}", sessionId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Get all active sessions
     */
    @GetMapping
    public ResponseEntity<Map<String, Object>> getAllSessions() {
        try {
            List<RecordingSession> sessions = sessionService.getAllActiveSessions();

            Map<String, Object> response = Map.of(
                "sessions", sessions,
                "count", sessions.size(),
                "timestamp", LocalDateTime.now().toString(),
                "type", "active"
            );

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error retrieving active sessions", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Get all sessions (both active and inactive)
     */
    @GetMapping("/all")
    public ResponseEntity<Map<String, Object>> getAllSessionsIncludingInactive() {
        try {
            List<RecordingSession> allSessions = sessionService.getAllSessions();

            // Separate into active and inactive for statistics
            long activeCount = allSessions.stream()
                .filter(RecordingSession::isActive)
                .count();
            long inactiveCount = allSessions.size() - activeCount;

            Map<String, Object> response = Map.of(
                "sessions", allSessions,
                "totalCount", allSessions.size(),
                "activeCount", activeCount,
                "inactiveCount", inactiveCount,
                "timestamp", LocalDateTime.now().toString(),
                "type", "all"
            );

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error retrieving all sessions", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Get all inactive sessions
     */
    @GetMapping("/inactive")
    public ResponseEntity<Map<String, Object>> getAllInactiveSessions() {
        try {
            List<RecordingSession> inactiveSessions = sessionService.getAllInactiveSessions();

            Map<String, Object> response = Map.of(
                "sessions", inactiveSessions,
                "count", inactiveSessions.size(),
                "timestamp", LocalDateTime.now().toString(),
                "type", "inactive"
            );

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error retrieving inactive sessions", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Check if a session is active
     */
    @GetMapping("/{sessionId}/active")
    public ResponseEntity<Map<String, Object>> isSessionActive(@PathVariable String sessionId) {
        try {
            boolean isActive = sessionService.isSessionActive(sessionId);

            Map<String, Object> response = Map.of(
                "sessionId", sessionId,
                "active", isActive,
                "timestamp", LocalDateTime.now().toString()
            );

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error checking session active status: {}", sessionId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Deactivate a session (mark as inactive but keep record)
     */
    @PutMapping("/{sessionId}/deactivate")
    public ResponseEntity<Map<String, Object>> deactivateSession(@PathVariable String sessionId) {
        try {
            Optional<RecordingSession> sessionOpt = sessionService.markSessionInactive(sessionId);

            if (sessionOpt.isPresent()) {
                Map<String, Object> response = Map.of(
                    "message", "Session deactivated",
                    "sessionId", sessionId,
                    "status", "INACTIVE",
                    "timestamp", LocalDateTime.now().toString()
                );

                log.info("Session deactivated: {}", sessionId);
                return ResponseEntity.ok(response);
            } else {
                return ResponseEntity.notFound().build();
            }
        } catch (Exception e) {
            log.error("Error deactivating session: {}", sessionId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Update session status
     */
    @PutMapping("/{sessionId}/status")
    public ResponseEntity<Map<String, Object>> updateSessionStatus(
            @PathVariable String sessionId,
            @RequestBody Map<String, String> payload) {
        try {
            String statusStr = payload.get("status");
            if (statusStr == null) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "status field is required"));
            }

            RecordingSession.SessionStatus status = parseSessionStatus(statusStr);
            boolean updated = sessionService.updateSessionStatus(sessionId, status);

            if (updated) {
                Map<String, Object> response = Map.of(
                    "message", "Session status updated",
                    "sessionId", sessionId,
                    "status", status.toString(),
                    "timestamp", LocalDateTime.now().toString()
                );

                return ResponseEntity.ok(response);
            } else {
                return ResponseEntity.notFound().build();
            }
        } catch (Exception e) {
            log.error("Error updating session status: {}", sessionId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Update session recording path
     */
    @PutMapping("/{sessionId}/recording-path")
    public ResponseEntity<Map<String, Object>> updateRecordingPath(
            @PathVariable String sessionId,
            @RequestBody Map<String, String> payload) {
        try {
            String recordingPath = payload.get("recordingPath");
            if (recordingPath == null) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "recordingPath field is required"));
            }

            boolean updated = sessionService.updateRecordingPath(sessionId, recordingPath);

            if (updated) {
                Map<String, Object> response = Map.of(
                    "message", "Recording path updated",
                    "sessionId", sessionId,
                    "recordingPath", recordingPath,
                    "timestamp", LocalDateTime.now().toString()
                );

                return ResponseEntity.ok(response);
            } else {
                return ResponseEntity.notFound().build();
            }
        } catch (Exception e) {
            log.error("Error updating recording path for session: {}", sessionId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Stop a session (mark as stopping/completed)
     */
    @PutMapping("/{sessionId}/stop")
    public ResponseEntity<Map<String, Object>> stopSession(@PathVariable String sessionId) {
        try {
            boolean stopped = sessionService.stopSession(sessionId);

            if (stopped) {
                Map<String, Object> response = Map.of(
                    "message", "Session stopped",
                    "sessionId", sessionId,
                    "timestamp", LocalDateTime.now().toString()
                );

                log.info("Session stopped: {}", sessionId);
                return ResponseEntity.ok(response);
            } else {
                return ResponseEntity.notFound().build();
            }
        } catch (Exception e) {
            log.error("Error stopping session: {}", sessionId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Deregister (remove) a recording session
     */
    @DeleteMapping("/{sessionId}")
    public ResponseEntity<Map<String, Object>> deregisterSession(@PathVariable String sessionId) {
        try {
            boolean removed = sessionService.deregisterSession(sessionId);

            if (removed) {
                Map<String, Object> response = Map.of(
                    "message", "Session removed",
                    "sessionId", sessionId,
                    "timestamp", LocalDateTime.now().toString()
                );

                log.info("Session deregistered: {}", sessionId);
                return ResponseEntity.ok(response);
            } else {
                return ResponseEntity.notFound().build();
            }
        } catch (Exception e) {
            log.error("Error deregistering session: {}", sessionId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Health check endpoint
     */
    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> healthCheck() {
        try {
            long activeSessionCount = sessionService.getActiveSessionCount();
            long totalSessionCount = sessionService.getTotalSessionCount();
            long inactiveSessionCount = totalSessionCount - activeSessionCount;

            Map<String, Object> response = Map.of(
                "status", "healthy",
                "activeSessions", activeSessionCount,
                "totalSessions", totalSessionCount,
                "inactiveSessions", inactiveSessionCount,
                "timestamp", LocalDateTime.now().toString(),
                "service", "recorder-ha-controller",
                "s3CleanupInfo", sessionService.getS3CleanupInfo()
            );

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error during health check", e);

            Map<String, Object> response = Map.of(
                "status", "unhealthy",
                "error", e.getMessage(),
                "timestamp", LocalDateTime.now().toString(),
                "service", "recorder-ha-controller",
                "s3CleanupInfo", "unavailable"
            );

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(response);
        }
    }

    /**
     * Manual cleanup of inactive sessions
     */
    @PostMapping("/cleanup")
    public ResponseEntity<Map<String, Object>> cleanupSessions() {
        try {
            int removedCount = sessionService.manualCleanup();

            Map<String, Object> response = Map.of(
                "message", "Manual cleanup completed",
                "removedSessions", removedCount,
                "timestamp", LocalDateTime.now().toString()
            );

            log.info("Manual cleanup completed, removed {} sessions", removedCount);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error during manual cleanup", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }
}
