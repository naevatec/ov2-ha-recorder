package com.naevatec.ovrecorder.repository;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.naevatec.ovrecorder.model.RecordingSession;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

@Repository
@RequiredArgsConstructor
@Slf4j
public class SessionRepository {

  private static final String SESSION_KEY_PREFIX = "session:";
  private static final String ACTIVE_SESSIONS_SET = "active_sessions";

  private final RedisTemplate<String, String> redisTemplate;
  private final ObjectMapper objectMapper = createObjectMapper();

  private static ObjectMapper createObjectMapper() {
    ObjectMapper mapper = new ObjectMapper();
    mapper.registerModule(new JavaTimeModule());
    return mapper;
  }

  /**
   * INSERT: Save a recording session to Redis
   */
  public void save(RecordingSession session) {
    try {
      String sessionKey = SESSION_KEY_PREFIX + session.getSessionId();
      String sessionJson = objectMapper.writeValueAsString(session);

      // Store the session data
      redisTemplate.opsForValue().set(sessionKey, sessionJson);

      // Add to active sessions set for quick lookups
      redisTemplate.opsForSet().add(ACTIVE_SESSIONS_SET, session.getSessionId());

      // Set expiration time (e.g., 24 hours)
      redisTemplate.expire(sessionKey, 24, TimeUnit.HOURS);

      log.debug("Saved session: {}", session.getSessionId());

    } catch (JsonProcessingException e) {
      log.error("Error saving session {}: {}", session.getSessionId(), e.getMessage());
      throw new RuntimeException("Failed to save session", e);
    }
  }

  /**
   * REVIEW/GET: Retrieve a recording session by ID
   */
  public Optional<RecordingSession> findById(String sessionId) {
    try {
      String sessionKey = SESSION_KEY_PREFIX + sessionId;
      String sessionJson = redisTemplate.opsForValue().get(sessionKey);

      if (sessionJson == null) {
        log.debug("Session not found: {}", sessionId);
        return Optional.empty();
      }

      RecordingSession session = objectMapper.readValue(sessionJson, RecordingSession.class);
      log.debug("Retrieved session: {}", sessionId);
      return Optional.of(session);

    } catch (JsonProcessingException e) {
      log.error("Error retrieving session {}: {}", sessionId, e.getMessage());
      return Optional.empty();
    }
  }

  /**
   * REVIEW/GET: Get all active session IDs
   */
  public Set<String> findAllActiveSessionIds() {
    Set<String> sessionIds = redisTemplate.opsForSet().members(ACTIVE_SESSIONS_SET);
    log.debug("Found {} active session IDs", sessionIds != null ? sessionIds.size() : 0);
    return sessionIds != null ? sessionIds : Set.of();
  }

  /**
   * REVIEW/GET: Get all active sessions
   */
  public List<RecordingSession> findAllActiveSessions() {
//    Set<String> sessionIds = findAllActiveSessionIds();
//
//    return sessionIds.stream()
//        .map(this::findById)
//        .filter(Optional::isPresent)
//        .map(Optional::get)
//        .collect(Collectors.toList());
	      try {
      List<RecordingSession> allSessions = findAll();

      List<RecordingSession> activeSessions = allSessions.stream()
          .filter(RecordingSession::isActive)
          .collect(Collectors.toList());

      log.debug("Found {} active sessions out of {} total sessions", activeSessions.size(), allSessions.size());

      return activeSessions;

    } catch (Exception e) {
      log.error("Error retrieving inactive sessions: {}", e.getMessage(), e);
      return List.of();
    }

  }

  /**
   * REVIEW/GET: Get all inactive sessions
   * Returns sessions that are marked as inactive or have inactive status
   */
  public List<RecordingSession> findAllInactiveSessions() {
    try {
      List<RecordingSession> allSessions = findAll();

      List<RecordingSession> inactiveSessions = allSessions.stream()
          .filter(session -> !session.isActive())
          .collect(Collectors.toList());

      log.debug("Found {} inactive sessions out of {} total sessions",
                inactiveSessions.size(), allSessions.size());

      return inactiveSessions;

    } catch (Exception e) {
      log.error("Error retrieving inactive sessions: {}", e.getMessage(), e);
      return List.of();
    }
  }

  /**
   * REVIEW/GET: Get ALL sessions (both active and inactive)
   * This method finds all session keys in Redis and retrieves them
   */
  public List<RecordingSession> findAll() {
    try {
      // Find all keys with session prefix using SCAN pattern
      Set<String> sessionKeys = redisTemplate.keys(SESSION_KEY_PREFIX + "*");

      if (sessionKeys == null || sessionKeys.isEmpty()) {
        log.debug("No sessions found in Redis");
        return List.of();
      }

      // Retrieve all sessions
      List<RecordingSession> allSessions = sessionKeys.stream()
          .map(key -> {
            try {
              String sessionJson = redisTemplate.opsForValue().get(key);
              if (sessionJson != null) {
                return objectMapper.readValue(sessionJson, RecordingSession.class);
              }
              return null;
            } catch (JsonProcessingException e) {
              log.warn("Failed to parse session from key {}: {}", key, e.getMessage());
              return null;
            }
          })
          .filter(session -> session != null)
          .collect(Collectors.toList());

      log.debug("Retrieved {} total sessions from Redis", allSessions.size());
      return allSessions;

    } catch (Exception e) {
      log.error("Error retrieving all sessions: {}", e.getMessage(), e);
      return List.of();
    }
  }

  /**
   * REVIEW/GET: Check if a session exists
   */
  public boolean exists(String sessionId) {
    String sessionKey = SESSION_KEY_PREFIX + sessionId;
    Boolean exists = redisTemplate.hasKey(sessionKey);
    return Boolean.TRUE.equals(exists);
  }

  /**
   * UPDATE: Update an existing session
   */
  public void update(RecordingSession session) {
    if (!exists(session.getSessionId())) {
      log.warn("Attempting to update non-existent session: {}", session.getSessionId());
      return;
    }
    save(session); // Save will overwrite existing data
  }

  /**
   * REMOVE: Delete a session by ID
   */
  public void deleteById(String sessionId) {
    String sessionKey = SESSION_KEY_PREFIX + sessionId;

    // Remove from Redis hash
    redisTemplate.delete(sessionKey);

    // Remove from active sessions set
    redisTemplate.opsForSet().remove(ACTIVE_SESSIONS_SET, sessionId);

    log.debug("Deleted session: {}", sessionId);
  }

  /**
   * REMOVE: Delete multiple sessions
   */
  public void deleteAll(List<String> sessionIds) {
    if (sessionIds.isEmpty()) {
      return;
    }

    // Prepare keys for deletion
    List<String> keys = sessionIds.stream()
        .map(id -> SESSION_KEY_PREFIX + id)
        .collect(Collectors.toList());

    // Delete session data
    redisTemplate.delete(keys);

    // Remove from active sessions set
    String[] sessionIdArray = sessionIds.toArray(new String[0]);
    redisTemplate.opsForSet().remove(ACTIVE_SESSIONS_SET, (Object[]) sessionIdArray);

    log.debug("Deleted {} sessions", sessionIds.size());
  }

  /**
   * Get count of active sessions
   */
  public long getActiveSessionCount() {
    Long count = redisTemplate.opsForSet().size(ACTIVE_SESSIONS_SET);
    return count != null ? count : 0;
  }

  /**
   * Get count of all sessions (including inactive)
   */
  public long getTotalSessionCount() {
    try {
      Set<String> sessionKeys = redisTemplate.keys(SESSION_KEY_PREFIX + "*");
      return sessionKeys != null ? sessionKeys.size() : 0;
    } catch (Exception e) {
      log.error("Error getting total session count: {}", e.getMessage());
      return 0;
    }
  }

  /**
   * Get count of inactive sessions
   */
  public long getInactiveSessionCount() {
    try {
      return findAllInactiveSessions().size();
    } catch (Exception e) {
      log.error("Error getting inactive session count: {}", e.getMessage());
      return 0;
    }
  }

  /**
   * Clean up orphaned session IDs (IDs in the set but no actual session data)
   */
  public void cleanupOrphanedSessions() {
    Set<String> sessionIds = findAllActiveSessionIds();
    List<String> orphanedIds = sessionIds.stream()
        .filter(id -> !exists(id))
        .toList();

    if (!orphanedIds.isEmpty()) {
      String[] orphanedArray = orphanedIds.toArray(new String[0]);
      redisTemplate.opsForSet().remove(ACTIVE_SESSIONS_SET, (Object[]) orphanedArray);
      log.info("Cleaned up {} orphaned session IDs", orphanedIds.size());
    }
  }

  /**
   * Clean up old inactive sessions by their Redis keys
   * More efficient than loading all sessions when we just want to delete them
   */
  public int cleanupOldInactiveSessionsByKeys(long maxAgeHours) {
    try {
      Set<String> sessionKeys = redisTemplate.keys(SESSION_KEY_PREFIX + "*");
      if (sessionKeys == null || sessionKeys.isEmpty()) {
        return 0;
      }

      // Get TTL for each key and remove expired ones
      List<String> keysToDelete = sessionKeys.stream()
          .filter(key -> {
            Long ttl = redisTemplate.getExpire(key, TimeUnit.HOURS);
            return ttl != null && ttl <= (24 - maxAgeHours); // Default TTL is 24h
          })
          .collect(Collectors.toList());

      if (!keysToDelete.isEmpty()) {
        // Delete the keys
        redisTemplate.delete(keysToDelete);

        // Extract session IDs and remove from active set
        List<String> sessionIds = keysToDelete.stream()
            .map(key -> key.substring(SESSION_KEY_PREFIX.length()))
            .collect(Collectors.toList());

        if (!sessionIds.isEmpty()) {
          String[] sessionIdArray = sessionIds.toArray(new String[0]);
          redisTemplate.opsForSet().remove(ACTIVE_SESSIONS_SET, (Object[]) sessionIdArray);
        }

        log.info("Cleaned up {} old inactive sessions by TTL", keysToDelete.size());
        return keysToDelete.size();
      }

      return 0;

    } catch (Exception e) {
      log.error("Error cleaning up old inactive sessions by keys: {}", e.getMessage(), e);
      return 0;
    }
  }
}
