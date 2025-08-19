# Multi-stage build for OV Recorder HA Controller
FROM maven:3.9.4-openjdk-17-slim AS build

# Set working directory
WORKDIR /app

# Copy Maven files first (for better layer caching)
COPY pom.xml .
COPY .mvn .mvn
COPY mvnw .

# Download dependencies (this layer will be cached if pom.xml doesn't change)
RUN ./mvnw dependency:go-offline -B

# Copy source code
COPY src src

# Build the application
RUN ./mvnw clean package -DskipTests

# Runtime stage
FROM openjdk:17-jdk-slim

# Install curl for health checks and other utilities
RUN apt-get update && \
  apt-get install -y curl jq && \
  rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy the built jar from build stage
COPY --from=build /app/target/ov-recorder-1.0.0.jar app.jar

# Create logs directory
RUN mkdir -p logs

# Create non-root user for security
RUN groupadd -r ovrecorder && useradd -r -g ovrecorder ovrecorder
RUN chown -R ovrecorder:ovrecorder /app
USER ovrecorder

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/actuator/health || exit 1

# Labels for identification
LABEL maintainer="NaevaTec-OpenVidu eiglesia@openvidu.io"
LABEL description="OV Recorder HA Controller"
LABEL version="1.0.0"
LABEL component="ha-controller"

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]