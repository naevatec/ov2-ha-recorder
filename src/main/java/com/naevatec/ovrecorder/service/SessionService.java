package com.naevatec.ovrecorder.service;

import com.naevatec.ovrecorder.model.RecordingSession;
import com.naevatec.ovrecorder.repository.SessionRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

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
    session.updateHeartbeat(); // Update heartbeat when status changes
    sessionRepository.update(session);

    log.info("Updated status for session {}: {}", sessionId, status);
    return true;
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
    sessionRepository.update(session);

    log.info("Stopped session: {}", sessionId);
    return true;
  }

  /**
   * Remove a session completely
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
   * Get session count
   */
  public long getActiveSessionCount() {
    return sessionRepository.getActiveSessionCount();
  }

  /**
   * Check if a session is active
   */
  public boolean isSessionActive(String sessionId) {
    Optional<RecordingSession> session = sessionRepository.findById(sessionId);
    return session.map(RecordingSession::isActive).orElse(false);
  }

  /**
   * Scheduled task to clean up inactive sessions
   * Runs based on app.session.cleanup-interval property
   */
  @Scheduled(fixedDelayString = "${app.session.cleanup-interval:30000}")
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
}
