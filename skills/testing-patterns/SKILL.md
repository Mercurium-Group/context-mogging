---
name: testing-patterns
description: Test file location, structure, coverage targets, and mocking guidelines. Triggers on: test, spec, coverage, jest, pytest, vitest, unit test, integration test.
version: 1.0.0
---

# Testing Patterns

## Test File Location

Match the project's existing convention. If none exists, use **colocated tests** (next to the file being tested):

```
src/
  auth/
    login.ts
    login.test.ts      ← colocated
  utils/
    format.ts
    format.test.ts
```

For larger projects with a dedicated test directory, mirror the source structure:
```
src/auth/login.ts  →  tests/auth/login.test.ts
```

Check where existing tests live before creating new ones. Consistency matters more than the "right" answer.

## Test Structure

Use **Arrange → Act → Assert** within each test:

```typescript
describe("login()", () => {
  it("returns a token when credentials are valid", async () => {
    // Arrange
    const credentials = { email: "user@example.com", password: "correct" };

    // Act
    const result = await login(credentials);

    // Assert
    expect(result.token).toBeDefined();
    expect(result.error).toBeUndefined();
  });

  it("throws AuthError when password is wrong", async () => {
    const credentials = { email: "user@example.com", password: "wrong" };
    await expect(login(credentials)).rejects.toThrow(AuthError);
  });
});
```

Keep one assertion per test where possible. Use `it("does X when Y")` naming — tests are documentation.

## Coverage Targets

- **Unit tests**: aim for 80%+ line coverage on business logic
- **Integration tests**: cover the happy path and 2–3 error paths per endpoint or service boundary
- **E2E tests**: cover critical user journeys only — login, checkout, core workflow

Don't chase 100% coverage. Test the behavior that matters, not implementation details.

## What to Test

**Test behavior, not implementation:**
```typescript
// Bad — tests implementation
expect(userService._cache.size).toBe(1);

// Good — tests behavior
expect(await userService.getUser(id)).toEqual(expectedUser);
```

**Edge cases to cover explicitly:**
- Empty/null/undefined inputs
- Boundary values (0, -1, max int, empty array)
- Network/IO failure paths
- Concurrent access if relevant

## Mocking Guidelines

**Mock at system boundaries** — external APIs, databases, file system, time, randomness:
```typescript
jest.mock("../db/client");
jest.spyOn(Date, "now").mockReturnValue(1700000000000);
```

**Don't mock internals** — if you're mocking your own utility functions to test another function, that's a sign the code needs to be refactored, not the test.

**Keep mocks close to tests** — define mocks in the test file or in a `__mocks__` folder next to the module. Avoid global mock state that bleeds between tests.

**Reset between tests:**
```typescript
beforeEach(() => {
  jest.clearAllMocks();
});
```

## Running Tests

```bash
# Run all tests
npm test

# Run tests for a specific file
npm test -- src/auth/login.test.ts

# Run in watch mode
npm test -- --watch

# With coverage report
npm test -- --coverage
```

For Python projects: `pytest -x -q` (fail fast, quiet output).

## Before Committing

Tests must pass before any commit. If they fail, fix the code — don't skip or comment out the test.
