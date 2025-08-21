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
    Set<String> sessionIds = findAllActiveSessionIds();

    return sessionIds.stream()
        .map(this::findById)
        .filter(Optional::isPresent)
        .map(Optional::get)
        .collect(Collectors.toList());
  }

  /**
   * REVIEW/GET: Check if a session exists
   */
  public boolean exists(String sessionId) {
    String sessionKey = SESSION_KEY_PREFIX + sessionId;
    Boolean exists = redisTemplate.hasKey(sessionKey);
    return exists;
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
}
