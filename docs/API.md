# SolidLog API Documentation

This document describes the SolidLog HTTP ingestion API for sending logs from your applications.

## Table of Contents

- [Overview](#overview)
- [Authentication](#authentication)
- [Endpoints](#endpoints)
- [Request Formats](#request-formats)
- [Response Formats](#response-formats)
- [Field Reference](#field-reference)
- [Error Handling](#error-handling)
- [Rate Limiting](#rate-limiting)
- [Examples](#examples)
- [Client Libraries](#client-libraries)

## Overview

SolidLog provides an HTTP API for ingesting structured log entries. Logs are sent as JSON via POST requests and stored for parsing and querying.

**Base URL:**
```
http://yourapp.com/admin/logs/api/v1
```

(Adjust based on where you mount the SolidLog engine)

**API Version:** v1

## Authentication

All API requests require bearer token authentication.

### Creating a Token

```bash
rails solid_log:create_token["Production API"]
```

Output:
```
Token created successfully!
Name: Production API
Token: slk_1a2b3c4d5e6f7g8h9i0j

IMPORTANT: Save this token securely. It will not be shown again.
```

### Using the Token

Include the token in the `Authorization` header:

```
Authorization: Bearer slk_1a2b3c4d5e6f7g8h9i0j
```

**Security Notes:**
- Tokens are stored hashed with BCrypt (cannot be recovered)
- Use environment variables to store tokens in your app
- Rotate tokens periodically
- Use different tokens for different environments/services
- Revoke compromised tokens via the UI

## Endpoints

### POST /api/v1/ingest

Ingest one or more log entries.

**Endpoint:**
```
POST /admin/logs/api/v1/ingest
```

**Headers:**
```
Authorization: Bearer YOUR_TOKEN
Content-Type: application/json  (for single/batch)
Content-Type: application/x-ndjson  (for NDJSON)
```

**Request Body:**
- Single entry: JSON object
- Batch: JSON array of objects
- NDJSON: Newline-delimited JSON objects

**Response:**
```json
{
  "status": "accepted",
  "count": 5
}
```

**Status Codes:**
- `202 Accepted` - Logs successfully ingested
- `401 Unauthorized` - Missing or invalid token
- `422 Unprocessable Entity` - Invalid JSON or missing required fields
- `500 Internal Server Error` - Server error

## Request Formats

### Single Entry

Send a single log entry as a JSON object:

```bash
curl -X POST http://yourapp.com/admin/logs/api/v1/ingest \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "2025-01-15T10:30:45Z",
    "level": "info",
    "message": "User login successful",
    "app": "web",
    "env": "production"
  }'
```

### Batch (JSON Array)

Send multiple entries in a single request:

```bash
curl -X POST http://yourapp.com/admin/logs/api/v1/ingest \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '[
    {
      "timestamp": "2025-01-15T10:30:45Z",
      "level": "info",
      "message": "Request started"
    },
    {
      "timestamp": "2025-01-15T10:30:46Z",
      "level": "info",
      "message": "Request completed"
    }
  ]'
```

**Batch Limits:**
- Default max: 1000 entries per batch
- Configurable via `config.max_batch_size`
- Larger batches are more efficient
- Recommended: 100-500 entries per batch

### NDJSON (Newline-Delimited JSON)

For streaming or large batches, use NDJSON:

```bash
curl -X POST http://yourapp.com/admin/logs/api/v1/ingest \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/x-ndjson" \
  --data-binary @- << EOF
{"timestamp":"2025-01-15T10:30:45Z","level":"info","message":"Log 1"}
{"timestamp":"2025-01-15T10:30:46Z","level":"info","message":"Log 2"}
{"timestamp":"2025-01-15T10:30:47Z","level":"warn","message":"Log 3"}
EOF
```

**Benefits:**
- Stream logs as they're generated
- Lower memory usage for large batches
- Easy to append to files
- Standard format for log shipping

## Response Formats

### Success Response

**Status:** `202 Accepted`

```json
{
  "status": "accepted",
  "count": 5
}
```

**Fields:**
- `status` - Always "accepted" for successful requests
- `count` - Number of log entries ingested

**Note:** `202 Accepted` means logs are queued for parsing, not yet queryable. Parsing typically completes within 1-5 minutes.

### Error Response

**Status:** `401 Unauthorized`

```json
{
  "error": "Unauthorized",
  "message": "Invalid or missing authentication token"
}
```

**Status:** `422 Unprocessable Entity`

```json
{
  "error": "Unprocessable Entity",
  "message": "Invalid JSON: unexpected token at '{malformed}'"
}
```

**Status:** `500 Internal Server Error`

```json
{
  "error": "Internal Server Error",
  "message": "An unexpected error occurred"
}
```

## Field Reference

### Standard Fields

These fields have special meaning and get promoted to dedicated columns:

| Field | Type | Required | Description | Example |
|-------|------|----------|-------------|---------|
| `timestamp` | String (ISO 8601) | No* | When the log was created | `"2025-01-15T10:30:45Z"` |
| `level` | String | No* | Log level | `"info"`, `"warn"`, `"error"` |
| `message` | String | No* | Log message | `"User login successful"` |
| `app` | String | No | Application name | `"web"`, `"worker"`, `"api"` |
| `env` | String | No | Environment | `"production"`, `"staging"` |
| `request_id` | String | No | Request correlation ID | `"abc-123-def-456"` |
| `job_id` | String | No | Background job correlation ID | `"job-789"` |
| `duration` | Number | No | Request/job duration (ms) | `145.2` |
| `status_code` | Integer | No | HTTP status code | `200`, `404`, `500` |
| `controller` | String | No | Rails controller | `"UsersController"` |
| `action` | String | No | Rails action | `"create"` |
| `path` | String | No | Request path | `"/users/sign_in"` |
| `method` | String | No | HTTP method | `"GET"`, `"POST"` |

\* While not strictly required, logs should include at least `timestamp`, `level`, and `message` for meaningful display.

### Log Levels

Supported log levels (case-insensitive):

- `debug` - Detailed debugging information
- `info` - General informational messages (default)
- `warn` - Warning messages
- `error` - Error messages
- `fatal` - Fatal errors

Unknown levels default to `info`.

### Custom Fields

Any additional fields are automatically tracked in the field registry:

```json
{
  "timestamp": "2025-01-15T10:30:45Z",
  "level": "info",
  "message": "User action",
  "user_id": 42,
  "ip_address": "192.168.1.1",
  "user_agent": "Mozilla/5.0...",
  "custom_metric": 123.45
}
```

Custom fields:
- Stored in `extra_fields` JSON column
- Tracked in field registry with usage counts
- Can be promoted to dedicated columns for performance
- Searchable via full-text search
- Type-inferred (string, number, boolean, datetime)

**Field Naming Conventions:**
- Use snake_case: `user_id` (not `userId`)
- Keep names short but descriptive
- Avoid special characters (stick to a-z, 0-9, `_`)
- Be consistent across your applications

### Timestamp Formats

Supported timestamp formats:

```
ISO 8601: "2025-01-15T10:30:45Z"
ISO 8601 with offset: "2025-01-15T10:30:45-05:00"
RFC 3339: "2025-01-15T10:30:45.123Z"
Unix epoch (seconds): 1736937045
Unix epoch (milliseconds): 1736937045123
```

If no timestamp is provided, the ingestion time is used.

## Error Handling

### Client-Side Errors

**401 Unauthorized:**
- Check token is correct
- Verify `Authorization` header format
- Ensure token hasn't been revoked

**422 Unprocessable Entity:**
- Validate JSON syntax
- Check field types (timestamp format, etc.)
- Ensure batch size within limits

### Server-Side Errors

**500 Internal Server Error:**
- SolidLog will log the error internally
- Check server logs for details
- Retry with exponential backoff

**Network Errors:**
- Implement retry logic with exponential backoff
- Queue logs locally and send in batches
- Monitor for sustained failures

### Retry Strategy

Recommended retry logic:

```ruby
def ingest_with_retry(logs, max_retries: 3)
  retries = 0

  begin
    response = http_post('/api/v1/ingest', logs)
    return response if response.code == 202

    if response.code >= 500
      raise "Server error: #{response.code}"
    else
      # Client error, don't retry
      Rails.logger.error("Failed to ingest logs: #{response.body}")
      return nil
    end

  rescue => e
    retries += 1
    if retries <= max_retries
      sleep(2 ** retries)  # Exponential backoff: 2s, 4s, 8s
      retry
    else
      Rails.logger.error("Failed to ingest logs after #{max_retries} retries: #{e}")
      nil
    end
  end
end
```

## Rate Limiting

**Current Implementation:** No rate limiting

**Best Practices:**
- Batch logs (100-500 per request)
- Send logs asynchronously
- Implement client-side queuing
- Monitor ingestion lag

**Future Considerations:**
- Per-token rate limits (planned)
- Burst allowance for spikes (planned)

## Examples

### Ruby (Net::HTTP)

```ruby
require 'net/http'
require 'json'

def send_log(message, level: 'info', **extra)
  uri = URI('http://localhost:3000/admin/logs/api/v1/ingest')

  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.path)
  request['Authorization'] = "Bearer #{ENV['SOLIDLOG_TOKEN']}"
  request['Content-Type'] = 'application/json'

  payload = {
    timestamp: Time.now.utc.iso8601,
    level: level,
    message: message,
    app: 'my-app',
    env: Rails.env
  }.merge(extra)

  request.body = payload.to_json

  response = http.request(request)
  response.code == '202'
end

# Usage
send_log('User logged in', user_id: 42, ip: '192.168.1.1')
```

### Ruby (HTTParty)

```ruby
require 'httparty'

class SolidLogClient
  include HTTParty
  base_uri 'http://localhost:3000/admin/logs/api/v1'

  def initialize(token)
    @token = token
  end

  def ingest(logs)
    self.class.post('/ingest',
      headers: {
        'Authorization' => "Bearer #{@token}",
        'Content-Type' => 'application/json'
      },
      body: Array(logs).to_json
    )
  end
end

# Usage
client = SolidLogClient.new(ENV['SOLIDLOG_TOKEN'])
client.ingest([
  { timestamp: Time.now.utc.iso8601, level: 'info', message: 'Log 1' },
  { timestamp: Time.now.utc.iso8601, level: 'info', message: 'Log 2' }
])
```

### cURL

```bash
#!/bin/bash
TOKEN="your_token_here"
URL="http://localhost:3000/admin/logs/api/v1/ingest"

curl -X POST "$URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "level": "info",
    "message": "Test log from curl",
    "app": "test"
  }'
```

### Python

```python
import requests
import json
from datetime import datetime
import os

class SolidLogClient:
    def __init__(self, base_url, token):
        self.base_url = base_url
        self.token = token

    def ingest(self, logs):
        headers = {
            'Authorization': f'Bearer {self.token}',
            'Content-Type': 'application/json'
        }

        if not isinstance(logs, list):
            logs = [logs]

        response = requests.post(
            f'{self.base_url}/api/v1/ingest',
            headers=headers,
            json=logs
        )

        return response.status_code == 202

# Usage
client = SolidLogClient(
    'http://localhost:3000/admin/logs',
    os.environ['SOLIDLOG_TOKEN']
)

client.ingest({
    'timestamp': datetime.utcnow().isoformat() + 'Z',
    'level': 'info',
    'message': 'User action',
    'user_id': 42
})
```

### JavaScript (Node.js)

```javascript
const axios = require('axios');

class SolidLogClient {
  constructor(baseURL, token) {
    this.client = axios.create({
      baseURL: `${baseURL}/api/v1`,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      }
    });
  }

  async ingest(logs) {
    try {
      const response = await this.client.post('/ingest',
        Array.isArray(logs) ? logs : [logs]
      );
      return response.status === 202;
    } catch (error) {
      console.error('Failed to ingest logs:', error.message);
      return false;
    }
  }
}

// Usage
const client = new SolidLogClient(
  'http://localhost:3000/admin/logs',
  process.env.SOLIDLOG_TOKEN
);

client.ingest({
  timestamp: new Date().toISOString(),
  level: 'info',
  message: 'User action',
  user_id: 42
});
```

### Lograge Integration

For Rails apps using Lograge:

```ruby
# config/environments/production.rb
config.lograge.enabled = true
config.lograge.formatter = Lograge::Formatters::Json.new

# Custom logger that sends to SolidLog
class SolidLogLogger < ActiveSupport::Logger
  def initialize(token, url)
    @token = token
    @url = url
    @queue = []
    @mutex = Mutex.new
    super(nil)  # No file output
  end

  def add(severity, message = nil, progname = nil)
    return if Thread.current[:solid_log_silenced]

    log_entry = JSON.parse(message) rescue { message: message }
    log_entry[:timestamp] = Time.now.utc.iso8601
    log_entry[:level] = severity_label(severity)

    @mutex.synchronize do
      @queue << log_entry
      flush_if_needed
    end
  end

  private

  def flush_if_needed
    return if @queue.size < 10  # Batch threshold

    payload = @queue.shift(10)
    Thread.new do
      send_to_solidlog(payload)
    end
  end

  def send_to_solidlog(logs)
    uri = URI(@url)
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri.path)
    request['Authorization'] = "Bearer #{@token}"
    request['Content-Type'] = 'application/json'
    request.body = logs.to_json
    http.request(request)
  rescue => e
    # Silently fail to avoid logging recursion
  end

  def severity_label(severity)
    case severity
    when Logger::DEBUG then 'debug'
    when Logger::INFO then 'info'
    when Logger::WARN then 'warn'
    when Logger::ERROR then 'error'
    when Logger::FATAL then 'fatal'
    else 'unknown'
    end
  end
end

# Use the custom logger
config.lograge.logger = SolidLogLogger.new(
  ENV['SOLIDLOG_TOKEN'],
  'http://localhost:3000/admin/logs/api/v1/ingest'
)
```

## Client Libraries

### Official

Coming soon:
- `solid_log-client` Ruby gem
- `solid_log-js` npm package

### Community

Contributions welcome!

## Security Best Practices

1. **Use HTTPS in production**
   ```ruby
   # Force SSL for ingestion endpoint
   config.force_ssl = true
   ```

2. **Rotate tokens regularly**
   ```bash
   # Create new token
   rails solid_log:create_token["Production API v2"]

   # Update apps to use new token
   # Revoke old token via UI
   ```

3. **Use environment variables**
   ```bash
   # Never commit tokens to git
   export SOLIDLOG_TOKEN="slk_..."
   ```

4. **Separate tokens per service**
   ```bash
   rails solid_log:create_token["Web App"]
   rails solid_log:create_token["Worker App"]
   rails solid_log:create_token["API Service"]
   ```

5. **Monitor token usage**
   ```bash
   # Check last_used_at in UI or via rake task
   rails solid_log:list_tokens
   ```

## Troubleshooting

### Logs not appearing in UI

1. Check ingestion response is `202 Accepted`
2. Verify parser worker is running:
   ```bash
   rails solid_log:health
   ```
3. Check for unparsed entries:
   ```bash
   rails solid_log:stats
   # Look for "Unparsed raw entries"
   ```
4. Manually trigger parsing:
   ```bash
   rails solid_log:parse_logs
   ```

### High parse backlog

- Increase parser concurrency:
  ```ruby
  config.parser_concurrency = 10
  ```
- Run multiple parser processes
- Check for parsing errors in server logs

### Authentication failures

- Verify token format: `slk_...`
- Check for trailing spaces in token
- Ensure token hasn't been revoked
- Verify `Authorization: Bearer` header format

## API Changelog

### v1 (Current)

- Initial release
- POST /api/v1/ingest endpoint
- Bearer token authentication
- JSON and NDJSON support
- Batch ingestion

### Future Versions

Planned features:
- Query API (GET /api/v1/logs)
- Webhook subscriptions
- Real-time streaming
- OAuth2 authentication

## Support

- **Documentation**: [README.md](../README.md)
- **Architecture**: [ARCHITECTURE.md](ARCHITECTURE.md)
- **Deployment**: [DEPLOYMENT.md](DEPLOYMENT.md)
- **Issues**: https://github.com/namolnad/solid_log/issues
