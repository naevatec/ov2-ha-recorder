# Swagger Integration Testing Instructions

## 🚀 Quick Start

### 1. Build and Run (Development Mode)
```bash
# Default profile is 'dev' - Swagger enabled
mvn clean package -DskipTests
cd docker/
./start.sh start
```

### 2. Access Swagger UI
- **Swagger UI**: http://localhost:8080/swagger-ui.html
- **OpenAPI JSON**: http://localhost:8080/api-docs

### 3. Production Mode (Swagger Disabled)
```bash
# Set production profile
export SPRING_PROFILES_ACTIVE=prod
export SWAGGER_ENABLED=false
export SWAGGER_UI_ENABLED=false

# Or via Docker environment
docker run -e SPRING_PROFILES_ACTIVE=prod your-app
```

## 🔧 Profile-based Testing

### Development Environment
```bash
export SPRING_PROFILES_ACTIVE=dev
# Swagger: ✅ Enabled
# Access: http://localhost:8080/swagger-ui.html
```

### Test Environment
```bash
export SPRING_PROFILES_ACTIVE=test
# Swagger: ✅ Enabled
# Access: http://localhost:8080/swagger-ui.html
```

### Production Environment
```bash
export SPRING_PROFILES_ACTIVE=prod
# Swagger: ❌ Disabled
# Access: 404 Not Found
```

## 📋 Verification Steps

### 1. Development Mode Verification
```bash
# Check if Swagger UI is accessible
curl -I http://localhost:8080/swagger-ui.html
# Expected: HTTP/200 OK

# Check OpenAPI documentation
curl http://localhost:8080/api-docs | jq .
# Expected: JSON OpenAPI specification
```

### 2. Production Mode Verification
```bash
# Set production profile
export SPRING_PROFILES_ACTIVE=prod

# Restart application
./start.sh restart

# Check if Swagger UI is disabled
curl -I http://localhost:8080/swagger-ui.html
# Expected: HTTP/404 Not Found

# Check if OpenAPI docs are disabled
curl -I http://localhost:8080/api-docs
# Expected: HTTP/404 Not Found

# Verify API endpoints still work
curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions/health
# Expected: HTTP/200 OK with health data
```

### 3. API Testing via Swagger UI

1. **Open Swagger UI**: http://localhost:8080/swagger-ui.html
2. **Click "Authorize"** button (top right)
3. **Enter credentials**:
   - Username: `recorder`
   - Password: `rec0rd3r_2024!`
4. **Test endpoints**:
   - Try `GET /api/sessions/health` first
   - Create a session with `POST /api/sessions`
   - Test other endpoints

## 🔍 Endpoints Available in Swagger

### Session Management
- `POST /api/sessions` - Create new session
- `GET /api/sessions` - List all active sessions
- `GET /api/sessions/{sessionId}` - Get specific session
- `DELETE /api/sessions/{sessionId}` - Remove session

### Session Operations
- `PUT /api/sessions/{sessionId}/heartbeat` - Update heartbeat
- `PUT /api/sessions/{sessionId}/status` - Update status
- `PUT /api/sessions/{sessionId}/path` - Update recording path
- `PUT /api/sessions/{sessionId}/stop` - Stop session
- `GET /api/sessions/{sessionId}/active` - Check if active

### Maintenance
- `POST /api/sessions/cleanup` - Manual cleanup
- `GET /api/sessions/health` - Health check

## 🎯 Example Session Creation via Swagger

### Sample Request Body:
```json
{
  "sessionId": "112_-_eiglesia_emer_minusculas_-_27541_-_2_-_e7f0bc2500695967644cc47135eb105f",
  "clientId": "client-01",
  "clientHost": "192.168.1.100",
  "metadata": "Test recording session"
}
```

### Expected Response:
```json
{
  "sessionId": "112_-_eiglesia_emer_minusculas_-_27541_-_2_-_e7f0bc2500695967644cc47135eb105f",
  "clientId": "client-01",
  "clientHost": "192.168.1.100",
  "status": "STARTING",
  "createdAt": "2024-01-20 10:30:00",
  "lastHeartbeat": "2024-01-20 10:30:00",
  "recordingPath": null,
  "metadata": "Test recording session"
}
```

## 🚨 Security Notes

- **Authentication Required**: All API endpoints (except health checks) require HTTP Basic Auth
- **Production Safety**: Swagger is automatically disabled in production profile
- **No Auth for Swagger UI**: Documentation interface doesn't require authentication (but APIs do)

## 🔧 Troubleshooting

### Swagger UI Not Loading
```bash
# Check if springdoc dependency is included
mvn dependency:tree | grep springdoc

# Check application logs
docker logs ov-recorder

# Verify profile and properties
curl http://localhost:8080/actuator/env | jq '.propertySources[] | select(.name | contains("application"))'
```

### Swagger Disabled When Expected to be Enabled
```bash
# Check current profile
echo $SPRING_PROFILES_ACTIVE

# Check swagger properties
curl http://localhost:8080/actuator/configprops | jq '.contexts.application.beans.springDocConfigProperties'

# Force enable in development
export SWAGGER_ENABLED=true
export SWAGGER_UI_ENABLED=true
```

### Authentication Issues in Swagger UI
1. Make sure you clicked "Authorize" button
2. Use correct credentials: `recorder` / `rec0rd3r_2024!`
3. Check if credentials are properly configured in properties
4. Verify no typos in username/password

## 📚 Additional Resources

- **SpringDoc Documentation**: https://springdoc.org/
- **OpenAPI 3 Specification**: https://swagger.io/specification/
- **Swagger UI Documentation**: https://swagger.io/tools/swagger-ui/
