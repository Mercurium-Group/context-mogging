---
name: error-handling
description: Retry policy, error reporting format, and anti-patterns for robust error handling. Triggers on: error, exception, failure, retry, catch, throw, try/catch.
version: 1.0.0
---

# Error Handling

## Retry Policy

Use a maximum of **3 retries** with exponential backoff for transient failures (network timeouts, rate limits, temporary service unavailability):

```typescript
async function withRetry<T>(
  fn: () => Promise<T>,
  maxAttempts = 3,
  baseDelayMs = 250
): Promise<T> {
  let lastError: Error;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastError = err as Error;
      if (attempt === maxAttempts) break;
      const delay = baseDelayMs * 2 ** (attempt - 1); // 250ms, 500ms, 1000ms
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
  throw lastError!;
}
```

**Only retry on transient errors.** Don't retry on:
- Authentication failures (401, 403)
- Validation errors (400)
- Not found (404)
- Your own bugs — fix them instead

## When to Retry vs Fail Fast

| Situation | Action |
|---|---|
| Network timeout | Retry with backoff |
| Rate limit (429) | Retry after `Retry-After` header delay |
| Service unavailable (503) | Retry with backoff |
| Invalid input (400) | Fail immediately — fix the input |
| Auth failure (401/403) | Fail immediately — refresh token or re-auth |
| Database conflict | Retry once with fresh read |
| Unknown error | Fail, log full context |

## Error Reporting Format

When throwing or logging errors, include **what happened**, **why it happened**, and **where to look next**:

```typescript
throw new AppError({
  message: "Failed to process payment",
  cause: originalError,
  context: {
    orderId,
    userId,
    amount,
    attempt,
  },
  resolution: "Check payment processor logs. If recurring, verify API key is valid.",
});
```

For logging:
```typescript
logger.error("Payment processing failed", {
  error: err.message,
  stack: err.stack,
  orderId,
  userId,
  amount,
  timestamp: new Date().toISOString(),
});
```

Always include **enough context to reproduce the failure** without needing to ask follow-up questions.

## Error Class Structure

Create specific error classes for different failure modes rather than using generic `Error`:

```typescript
class AppError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly context?: Record<string, unknown>
  ) {
    super(message);
    this.name = "AppError";
  }
}

class ValidationError extends AppError { ... }
class AuthError extends AppError { ... }
class NotFoundError extends AppError { ... }
class ExternalServiceError extends AppError { ... }
```

This lets you catch specific error types and handle them appropriately.

## Anti-Patterns

**Swallowing errors silently:**
```typescript
// Bad
try {
  await riskyOperation();
} catch (_) {} // silent failure — bugs disappear

// Good
try {
  await riskyOperation();
} catch (err) {
  logger.error("riskyOperation failed", { err });
  throw err; // or handle meaningfully
}
```

**Overly broad catch:**
```typescript
// Bad — catches bugs you should fix, not just expected failures
} catch (err) {
  return null; // masks programming errors

// Good — be specific about what you're handling
} catch (err) {
  if (err instanceof NetworkError) return retry();
  throw err; // let unexpected errors propagate
}
```

**Logging without context:**
```typescript
// Bad — useless in production
console.error("Something went wrong");

// Good — actionable
logger.error("User lookup failed", { userId, endpoint: "/api/users", err });
```

**Retrying non-idempotent operations:**
Don't blindly retry mutations (writes, payments, emails). Check if the operation already succeeded before retrying — use idempotency keys where the external service supports them.

## Handling Errors in Claude Code Context

When Claude encounters a failure during a task:

1. **Do not retry the same action** — diagnose the root cause first
2. **Report the exact error** with full context (file path, line, command output)
3. **Propose the fix** before attempting it
4. **If blocked** after one retry, surface the issue to the user — do not loop
