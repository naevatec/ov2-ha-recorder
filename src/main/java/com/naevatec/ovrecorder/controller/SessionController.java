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
     * Register a new recording session
     */
    @PostMapping
    public ResponseEntity<?> registerSession(@RequestBody Map<String, String> requestBody) {
        try {
            String sessionId = requestBody.get("sessionId");
            String clientId = requestBody.get("clientId");
            String clientHost = requestBody.get("clientHost");

            if (sessionId == null || clientId == null) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "sessionId and clientId are required"));
            }

            RecordingSession registeredSession = sessionService.createSession(sessionId, clientId, clientHost);
            log.info("Session registered: {}", sessionId);

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
                "timestamp", LocalDateTime.now().toString()
            );

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error retrieving sessions", e);
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

            RecordingSession.SessionStatus status;
            try {
                status = RecordingSession.SessionStatus.valueOf(statusStr.toUpperCase());
            } catch (IllegalArgumentException e) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "Invalid status: " + statusStr));
            }

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

            Map<String, Object> response = Map.of(
                "status", "healthy",
                "activeSessions", activeSessionCount,
                "timestamp", LocalDateTime.now().toString(),
                "service", "recorder-ha-controller"
            );

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error during health check", e);

            Map<String, Object> response = Map.of(
                "status", "unhealthy",
                "error", e.getMessage(),
                "timestamp", LocalDateTime.now().toString(),
                "service", "recorder-ha-controller"
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
