package com.naevatec.ovrecorder.controller;

import com.naevatec.ovrecorder.service.WebhookRelayService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import jakarta.servlet.http.HttpServletRequest;
import java.util.Enumeration;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

@RestController
@RequestMapping("/openvidu/webhook")
@Tag(name = "OpenVidu Webhook Relay", description = "Relay endpoint for OpenVidu webhook notifications")
@RequiredArgsConstructor
@Slf4j
public class WebhookController {

    private final WebhookRelayService webhookRelayService;

    /**
     * Primary webhook endpoint - receives all OpenVidu webhook notifications
     * POST /openvidu/webhook
     */
    @Operation(
        summary = "Receive OpenVidu webhook notifications",
        description = "Primary endpoint that receives OpenVidu webhook notifications and relays them to the configured target endpoint with minimal delay. " +
                     "This endpoint accepts any JSON payload and forwards it immediately."
    )
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Webhook received and relayed successfully"),
        @ApiResponse(responseCode = "202", description = "Webhook received, relay in progress"),
        @ApiResponse(responseCode = "400", description = "Invalid webhook payload"),
        @ApiResponse(responseCode = "500", description = "Error processing webhook")
    })
    @PostMapping(consumes = {"application/json", "text/plain", "*/*"})
    public ResponseEntity<Map<String, Object>> receiveWebhook(
        @io.swagger.v3.oas.annotations.parameters.RequestBody(
            description = "OpenVidu webhook payload",
            content = @Content(
                mediaType = "application/json",
                schema = @Schema(implementation = Object.class),
                examples = {
                    @ExampleObject(
                        name = "Session Created",
                        value = """
                        {
                          "event": "sessionCreated",
                          "timestamp": 1647856800000,
                          "sessionId": "ses_123456789",
                          "customSessionId": "my-session"
                        }
                        """
                    ),
                    @ExampleObject(
                        name = "Recording Started",
                        value = """
                        {
                          "event": "recordingStatusChanged",
                          "timestamp": 1647856800000,
                          "sessionId": "ses_123456789",
                          "recordingId": "rec_123456789",
                          "status": "started"
                        }
                        """
                    )
                }
            )
        )
        @RequestBody String payload,
        HttpServletRequest request) {

        long startTime = System.currentTimeMillis();

        try {
            // Extract headers
            HttpHeaders headers = extractHeaders(request);

            // Log webhook reception (debug level to avoid spam)
            log.debug("Received OpenVidu webhook from {}: {} bytes",
                getClientIP(request), payload != null ? payload.length() : 0);

            // Start async relay immediately to minimize delay
            CompletableFuture<WebhookRelayService.WebhookRelayResult> relayFuture =
                webhookRelayService.relayWebhook(payload, headers, HttpMethod.POST);

            log.debug("RelayFuture: " + relayFuture.toString());

            // Return immediate response (don't wait for relay completion)
            long processingTime = System.currentTimeMillis() - startTime;

            Map<String, Object> response = Map.of(
                "status", "received",
                "message", "Webhook received and relay initiated",
                "timestamp", java.time.LocalDateTime.now(),
                "processingTimeMs", processingTime
            );

            // Log successful reception
            log.info("OpenVidu webhook received and relay initiated in {}ms from {}",
                processingTime, getClientIP(request));

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            long processingTime = System.currentTimeMillis() - startTime;
            log.error("Error processing OpenVidu webhook after {}ms: {}", processingTime, e.getMessage(), e);

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of(
                    "status", "error",
                    "message", "Error processing webhook: " + e.getMessage(),
                    "timestamp", java.time.LocalDateTime.now(),
                    "processingTimeMs", processingTime
                ));
        }
    }

    /**
     * Alternative endpoint for different HTTP methods
     * Support GET, PUT, PATCH, DELETE if needed
     */
    @RequestMapping(method = {RequestMethod.PUT, RequestMethod.PATCH, RequestMethod.DELETE},
                   consumes = {"application/json", "text/plain", "*/*"})
    public ResponseEntity<Map<String, Object>> receiveWebhookOtherMethods(
        @RequestBody(required = false) String payload,
        HttpServletRequest request) {

        HttpMethod method = HttpMethod.valueOf(request.getMethod());
        log.debug("Received OpenVidu webhook via {} method", method);

        return processWebhookRequest(payload, request, method);
    }

    /**
     * GET endpoint for webhook verification/testing
     */
    @GetMapping
    public ResponseEntity<Map<String, Object>> webhookHealthCheck(HttpServletRequest request) {
        log.debug("Webhook health check requested from {}", getClientIP(request));

        return ResponseEntity.ok(Map.of(
            "status", "healthy",
            "endpoint", "/openvidu/webhook",
            "message", "OpenVidu webhook relay endpoint is operational",
            "timestamp", java.time.LocalDateTime.now(),
            "relayStatus", webhookRelayService.getRelayStatus()
        ));
    }

    /**
     * Get webhook relay statistics
     * GET /openvidu/webhook/status
     */
    @Operation(
        summary = "Get webhook relay status",
        description = "Returns statistics and configuration information about the webhook relay service"
    )
    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> getWebhookStatus() {
        Map<String, Object> status = webhookRelayService.getRelayStatus();
        status.put("endpoint", "/openvidu/webhook");
        status.put("timestamp", java.time.LocalDateTime.now());

        return ResponseEntity.ok(status);
    }

    /**
     * Process webhook request with specified method
     */
    private ResponseEntity<Map<String, Object>> processWebhookRequest(
            String payload, HttpServletRequest request, HttpMethod method) {

        long startTime = System.currentTimeMillis();

        try {
            HttpHeaders headers = extractHeaders(request);

            // Start async relay
            webhookRelayService.relayWebhook(payload, headers, method);

            long processingTime = System.currentTimeMillis() - startTime;

            return ResponseEntity.ok(Map.of(
                "status", "received",
                "method", method.name(),
                "message", "Webhook received and relay initiated",
                "timestamp", java.time.LocalDateTime.now(),
                "processingTimeMs", processingTime
            ));

        } catch (Exception e) {
            long processingTime = System.currentTimeMillis() - startTime;
            log.error("Error processing {} webhook after {}ms: {}", method, processingTime, e.getMessage(), e);

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of(
                    "status", "error",
                    "method", method.name(),
                    "message", "Error processing webhook: " + e.getMessage(),
                    "timestamp", java.time.LocalDateTime.now(),
                    "processingTimeMs", processingTime
                ));
        }
    }

    /**
     * Extract headers from HTTP request
     */
    private HttpHeaders extractHeaders(HttpServletRequest request) {
        HttpHeaders headers = new HttpHeaders();

        Enumeration<String> headerNames = request.getHeaderNames();
        while (headerNames.hasMoreElements()) {
            String headerName = headerNames.nextElement();
            Enumeration<String> headerValues = request.getHeaders(headerName);
            while (headerValues.hasMoreElements()) {
                headers.add(headerName, headerValues.nextElement());
            }
        }

        return headers;
    }

    /**
     * Get client IP address
     */
    private String getClientIP(HttpServletRequest request) {
        String xForwardedFor = request.getHeader("X-Forwarded-For");
        if (xForwardedFor != null && !xForwardedFor.isEmpty()) {
            return xForwardedFor.split(",")[0].trim();
        }

        String xRealIp = request.getHeader("X-Real-IP");
        if (xRealIp != null && !xRealIp.isEmpty()) {
            return xRealIp;
        }

        return request.getRemoteAddr();
    }
}
