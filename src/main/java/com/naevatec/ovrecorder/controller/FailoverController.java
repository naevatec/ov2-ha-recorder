package com.naevatec.ovrecorder.controller;

import com.naevatec.ovrecorder.service.FailoverService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.Map;

@RestController
@RequestMapping("/api/failover")
@Tag(name = "Failover Management", description = "Docker-in-Docker failover system management")
@RequiredArgsConstructor
@Slf4j
public class FailoverController {

    private final FailoverService failoverService;

    /**
     * Get failover system status and statistics
     * GET /api/failover/status
     */
    @Operation(
        summary = "Get failover system status",
        description = "Returns current status of the Docker-in-Docker failover system including active backup containers and configuration"
    )
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Failover status retrieved successfully"),
        @ApiResponse(responseCode = "500", description = "Error retrieving failover status")
    })
    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> getFailoverStatus() {
        try {
            Map<String, Object> status = failoverService.getFailoverStatus();
            status.put("timestamp", LocalDateTime.now());

            return ResponseEntity.ok(status);
        } catch (Exception e) {
            log.error("Error retrieving failover status", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of(
                    "error", "Failed to retrieve failover status: " + e.getMessage(),
                    "timestamp", LocalDateTime.now()
                ));
        }
    }

    /**
     * Trigger manual failover check
     * POST /api/failover/check
     */
    @Operation(
        summary = "Trigger manual failover check",
        description = "Manually trigger the failover detection process to check for failed sessions and start backup containers if needed"
    )
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Manual failover check completed"),
        @ApiResponse(responseCode = "500", description = "Error during failover check")
    })
    @PostMapping("/check")
    public ResponseEntity<Map<String, Object>> triggerManualFailoverCheck() {
        try {
            Map<String, Object> result = failoverService.triggerManualFailoverCheck();

            log.info("Manual failover check triggered via API");
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("Error during manual failover check", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of(
                    "error", "Manual failover check failed: " + e.getMessage(),
                    "timestamp", LocalDateTime.now()
                ));
        }
    }

    /**
     * Gracefully stop backup container for specific session (sends 'q' to FFmpeg)
     * DELETE /api/failover/backup/{sessionId}
     */
    @Operation(
        summary = "Gracefully stop backup container",
        description = "Send graceful stop signal to backup container, allowing FFmpeg to complete chunk processing"
    )
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Backup container stopped gracefully"),
        @ApiResponse(responseCode = "404", description = "No backup container found for session"),
        @ApiResponse(responseCode = "500", description = "Error stopping backup container")
    })
    @DeleteMapping("/backup/{sessionId}")
    public ResponseEntity<Map<String, Object>> stopBackupContainerGracefully(@PathVariable String sessionId) {
        try {
            boolean stopped = failoverService.stopBackupContainerGracefully(sessionId);

            if (stopped) {
                Map<String, Object> response = Map.of(
                    "message", "Backup container stopped gracefully",
                    "method", "graceful",
                    "sessionId", sessionId,
                    "timestamp", LocalDateTime.now()
                );

                log.info("Backup container stopped gracefully for session: {}", sessionId);
                return ResponseEntity.ok(response);
            } else {
                return ResponseEntity.notFound().build();
            }
        } catch (Exception e) {
            log.error("Error stopping backup container gracefully for session: {}", sessionId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of(
                    "error", "Failed to stop backup container gracefully: " + e.getMessage(),
                    "sessionId", sessionId,
                    "timestamp", LocalDateTime.now()
                ));
        }
    }

    /**
     * Force stop backup container for specific session (immediate termination)
     * DELETE /api/failover/backup/{sessionId}/force
     */
    @Operation(
        summary = "Force stop backup container",
        description = "Immediately terminate backup container without waiting for graceful shutdown"
    )
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Backup container force stopped"),
        @ApiResponse(responseCode = "404", description = "No backup container found for session"),
        @ApiResponse(responseCode = "500", description = "Error force stopping backup container")
    })
    @DeleteMapping("/backup/{sessionId}/force")
    public ResponseEntity<Map<String, Object>> forceStopBackupContainer(@PathVariable String sessionId) {
        try {
            boolean stopped = failoverService.forceStopBackupContainer(sessionId);

            if (stopped) {
                Map<String, Object> response = Map.of(
                    "message", "Backup container force stopped",
                    "method", "force",
                    "sessionId", sessionId,
                    "timestamp", LocalDateTime.now()
                );

                log.info("Backup container force stopped for session: {}", sessionId);
                return ResponseEntity.ok(response);
            } else {
                return ResponseEntity.notFound().build();
            }
        } catch (Exception e) {
            log.error("Error force stopping backup container for session: {}", sessionId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of(
                    "error", "Failed to force stop backup container: " + e.getMessage(),
                    "sessionId", sessionId,
                    "timestamp", LocalDateTime.now()
                ));
        }
    }

    /**
     * Get list of all active backup containers
     * GET /api/failover/backups
     */
    @Operation(
        summary = "List active backup containers",
        description = "Get a list of all currently running backup containers"
    )
    @GetMapping("/backups")
    public ResponseEntity<Map<String, Object>> listActiveBackupContainers() {
        try {
            Map<String, Object> status = failoverService.getFailoverStatus();

            @SuppressWarnings("unchecked")
            Map<String, String> backupContainers = (Map<String, String>) status.get("backupContainerDetails");

            Map<String, Object> response = Map.of(
                "activeBackupContainers", backupContainers != null ? backupContainers : Map.of(),
                "count", backupContainers != null ? backupContainers.size() : 0,
                "timestamp", LocalDateTime.now()
            );

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error listing active backup containers", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of(
                    "error", "Failed to list backup containers: " + e.getMessage(),
                    "timestamp", LocalDateTime.now()
                ));
        }
    }
}
