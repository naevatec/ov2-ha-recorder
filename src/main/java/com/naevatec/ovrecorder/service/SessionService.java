package com.naevatec.ovrecorder.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import com.naevatec.ovrecorder.model.RecordingSession;
import com.naevatec.ovrecorder.repository.SessionRepository;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@RequiredArgsConstructor
@Slf4j
public class SessionService {

  private final SessionRepository sessionRepository;

  @Value("${app.session.max-inactive-time:600}")
  private long maxInactiveTimeSeconds;

  /**
   * Create a new recording session
   */
  public RecordingSession createSession(String sessionId, String clientId, String clientHost) {
    log.info("Creating new session: {} for client: {}", sessionId, clientId);

    if (sessionRepository.exists(sessionId)) {
      throw new IllegalArgumentException("Session with ID " + sessionId + " already exists");
    }

    RecordingSession session = new RecordingSession(sessionId, clientId, clientHost);
    sessionRepository.save(session);

    log.info("Session created successfully: {}", sessionId);
    return session;
  }

  /**
   * Register a new recording session (alternative method for controller compatibility)
   */
  public RecordingSession registerSession(RecordingSession session) {
    log.info("Registering new session: {} for client: {}", session.getSessionId(), session.getClientId());

    if (sessionRepository.exists(session.getSessionId())) {
      throw new IllegalArgumentException("Session with ID " + session.getSessionId() + " already exists");
    }

    // Set creation time and initial status
    session.setCreatedAt(LocalDateTime.now());
    session.setLastHeartbeat(LocalDateTime.now());
    session.setActive(true);

    // Set default status if not provided
    if (session.getStatus() == null) {
      session.setStatus(RecordingSession.SessionStatus.STARTING);
    }

    sessionRepository.save(session);
    log.info("Session registered successfully: {}", session.getSessionId());
    return session;
  }

  /**
   * Check if session exists
   */
  public boolean sessionExists(String sessionId) {
    return sessionRepository.exists(sessionId);
  }

  /**
   * Get session by ID
   */
  public Optional<RecordingSession> getSession(String sessionId) {
    return sessionRepository.findById(sessionId);
  }

  /**
   * Get all active sessions
   */
  public List<RecordingSession> getAllActiveSessions() {
    return sessionRepository.findAllActiveSessions();
  }

  /**
   * Get all sessions (both active and inactive)
   */
  public List<RecordingSession> getAllSessions() {
    return sessionRepository.findAll();
  }

  /**
   * Get all inactive sessions
   */
  public List<RecordingSession> getAllInactiveSessions() {
    return sessionRepository.findAllInactiveSessions();
  }

  /**
   * Get count of active sessions
   */
  public long getActiveSessionCount() {
    return sessionRepository.getActiveSessionCount();
  }

  /**
   * Get count of total sessions (active and inactive)
   */
  public long getTotalSessionCount() {
    return sessionRepository.getTotalSessionCount();
  }

  /**
   * Get count of inactive sessions
   */
  public long getInactiveSessionCount() {
    return sessionRepository.getInactiveSessionCount();
  }

  /**
   * Update session heartbeat (keep-alive) without chunk info
   */
  public boolean updateHeartbeat(String sessionId) {
    return updateHeartbeat(sessionId, null);
  }

  /**
   * Update session heartbeat (keep-alive) with optional chunk info
   */
  public boolean updateHeartbeat(String sessionId, String lastChunk) {
    Optional<RecordingSession> sessionOpt = sessionRepository.findById(sessionId);

    if (sessionOpt.isEmpty()) {
      log.warn("Attempted to update heartbeat for non-existent session: {}", sessionId);
      return false;
    }

    RecordingSession session = sessionOpt.get();

    if (lastChunk != null && !lastChunk.isEmpty()) {
      session.updateHeartbeat(lastChunk);
      log.debug("Updated heartbeat for session: {} with chunk: {}", sessionId, lastChunk);
    } else {
      session.updateHeartbeat();
      log.debug("Updated heartbeat for session: {}", sessionId);
    }

    sessionRepository.update(session);
    return true;
  }

  /**
   * Update session heartbeat and return session (for controller compatibility)
   */
  public Optional<RecordingSession> updateHeartbeatAndGet(String sessionId, String lastChunk) {
    Optional<RecordingSession> sessionOpt = sessionRepository.findById(sessionId);

    if (sessionOpt.isEmpty()) {
      log.warn("Attempted to update heartbeat for non-existent session: {}", sessionId);
      return Optional.empty();
    }

    RecordingSession session = sessionOpt.get();

    if (lastChunk != null && !lastChunk.isEmpty()) {
      session.updateHeartbeat(lastChunk);
      log.debug("Updated heartbeat for session: {} with chunk: {}", sessionId, lastChunk);
    } else {
      session.updateHeartbeat();
      log.debug("Updated heartbeat for session: {}", sessionId);
    }

    sessionRepository.update(session);
    return Optional.of(session);
  }

  /**
   * Update session status
   */
  public boolean updateSessionStatus(String sessionId, RecordingSession.SessionStatus status) {
    Optional<RecordingSession> sessionOpt = sessionRepository.findById(sessionId);

    if (sessionOpt.isEmpty()) {
      log.warn("Attempted to update status for non-existent session: {}", sessionId);
      return false;
    }

    RecordingSession session = sessionOpt.get();
    session.setStatus(status);
    switch (session.getStatus()) {
      case PAUSED:
      case STOPPING:
      case COMPLETED:
      case FAILED:
      case INACTIVE:
        session.setActive(false);
        break;
      default:
        break;
    }
    session.updateHeartbeat(); // Update heartbeat when status changes
    sessionRepository.update(session);

    log.info("Updated status for session {}: {}", sessionId, status);
    return true;
  }

  /**
   * Mark session as inactive (soft delete)
   */
  public Optional<RecordingSession> markSessionInactive(String sessionId) {
    Optional<RecordingSession> sessionOpt = sessionRepository.findById(sessionId);

    if (sessionOpt.isEmpty()) {
      log.warn("Attempted to mark inactive non-existent session: {}", sessionId);
      return Optional.empty();
    }

    RecordingSession session = sessionOpt.get();
    session.setActive(false);
    session.setStatus(RecordingSession.SessionStatus.INACTIVE);
    session.updateHeartbeat();
    sessionRepository.update(session);

    log.info("Session marked as inactive: {}", sessionId);
    return Optional.of(session);
  }

  /**
   * Update session recording path
   */
  public boolean updateRecordingPath(String sessionId, String recordingPath) {
    Optional<RecordingSession> sessionOpt = sessionRepository.findById(sessionId);

    if (sessionOpt.isEmpty()) {
      log.warn("Attempted to update recording path for non-existent session: {}", sessionId);
      return false;
    }

    RecordingSession session = sessionOpt.get();
    session.setRecordingPath(recordingPath);
    session.updateHeartbeat();
    sessionRepository.update(session);

    log.info("Updated recording path for session {}: {}", sessionId, recordingPath);
    return true;
  }

  /**
   * Stop and remove a session
   */
  public boolean stopSession(String sessionId) {
    Optional<RecordingSession> sessionOpt = sessionRepository.findById(sessionId);

    if (sessionOpt.isEmpty()) {
      log.warn("Attempted to stop non-existent session: {}", sessionId);
      return false;
    }

    RecordingSession session = sessionOpt.get();
    session.setStatus(RecordingSession.SessionStatus.STOPPING);
    sessionRepository.update(session);

    // After a brief moment, mark as completed and optionally remove
    // For now, we'll mark as completed
    session.setStatus(RecordingSession.SessionStatus.COMPLETED);
    session.setActive(false);
    sessionRepository.update(session);

    log.info("Stopped session: {}", sessionId);
    return true;
  }

  /**
   * Remove a session completely (hard delete)
   */
  public boolean removeSession(String sessionId) {
    if (!sessionRepository.exists(sessionId)) {
      log.warn("Attempted to remove non-existent session: {}", sessionId);
      return false;
    }

    sessionRepository.deleteById(sessionId);
    log.info("Removed session: {}", sessionId);
    return true;
  }

  /**
   * Deregister session (alias for removeSession for controller compatibility)
   */
  public boolean deregisterSession(String sessionId) {
    return removeSession(sessionId);
  }

  /**
   * Check if a session is active
   */
  public boolean isSessionActive(String sessionId) {
    Optional<RecordingSession> session = sessionRepository.findById(sessionId);
    return session.map(RecordingSession::isActive).orElse(false);
  }

  /**
   * Clean up old inactive sessions
   */
  public int cleanupOldInactiveSessions(LocalDateTime threshold) {
    List<RecordingSession> allSessions = sessionRepository.findAll();
    List<String> oldInactiveSessions = allSessions.stream()
        .filter(session -> !session.isActive() && session.getLastHeartbeat().isBefore(threshold))
        .map(RecordingSession::getSessionId)
        .collect(Collectors.toList());

    if (!oldInactiveSessions.isEmpty()) {
      sessionRepository.deleteAll(oldInactiveSessions);
      log.info("Cleaned up {} old inactive sessions", oldInactiveSessions.size());
    }

    return oldInactiveSessions.size();
  }

  /**
   * Scheduled task to clean up inactive sessions
   * Runs based on app.session.cleanup-interval property
   */
  @Scheduled(fixedDelayString = "#{${app.session.cleanup-interval:30} * 1000}")
  public void cleanupInactiveSessions() {
    log.debug("Starting cleanup of inactive sessions...");

    try {
      // Get all active sessions
      List<RecordingSession> sessions = sessionRepository.findAllActiveSessions();

      // Find inactive sessions
      List<String> inactiveSessions = sessions.stream()
          .filter(session -> session.isInactive(maxInactiveTimeSeconds))
          .map(RecordingSession::getSessionId)
          .collect(Collectors.toList());

      if (!inactiveSessions.isEmpty()) {
        // Mark sessions as inactive before removing
        for (String sessionId : inactiveSessions) {
          updateSessionStatus(sessionId, RecordingSession.SessionStatus.INACTIVE);
        }

        // Remove inactive sessions
        sessionRepository.deleteAll(inactiveSessions);
        log.info("Cleaned up {} inactive sessions: {}", inactiveSessions.size(), inactiveSessions);
      }

      // Clean up orphaned session IDs
      sessionRepository.cleanupOrphanedSessions();

      // Log current status
      long activeCount = sessionRepository.getActiveSessionCount();
      log.debug("Cleanup completed. Active sessions: {}", activeCount);

    } catch (Exception e) {
      log.error("Error during session cleanup: {}", e.getMessage(), e);
    }
  }

  /**
   * Manual cleanup trigger (can be called via REST endpoint)
   */
  public int manualCleanup() {
    log.info("Manual cleanup triggered");

    List<RecordingSession> sessions = sessionRepository.findAllActiveSessions();
    List<String> inactiveSessions = sessions.stream()
        .filter(session -> session.isInactive(maxInactiveTimeSeconds))
        .map(RecordingSession::getSessionId)
        .collect(Collectors.toList());

    if (!inactiveSessions.isEmpty()) {
      sessionRepository.deleteAll(inactiveSessions);
      log.info("Manual cleanup removed {} sessions", inactiveSessions.size());
    }

    sessionRepository.cleanupOrphanedSessions();
    return inactiveSessions.size();
  }

  /**
   * Check the Webhook payload string as JSON object, convert to Map.
   * Then looks for the status field and if it is "stopped" or "stopping", mark the session as stopped.
   * @param payload, String payload from webhook
   */
  public void handleWebhookPayload(String payload) {
    try {
      ObjectMapper objectMapper = new ObjectMapper();
      Map<String, Object> payloadObj = objectMapper.readValue(payload, new TypeReference<HashMap<String, Object>>() {});
      String sessionId = (String) payloadObj.get("uniqueSessionId");
      String status = (String) payloadObj.get("status");
      if (sessionId != null && status != null) {
        if (status.equalsIgnoreCase("stopped")) {
			boolean didStop = updateSessionStatus(sessionId, RecordingSession.SessionStatus.STOPPING);
			if (didStop)
				log.info("Session {} marked as STOPPING due to webhook status: {}", sessionId, status);
			else
				log.warn("Failed to mark session {} as STOPPING - session not found", sessionId);
		}
      }
    } catch (Exception e) {
      log.error("Failed to parse webhook payload: {}", e.getMessage());
      return;
    }
  }
}
