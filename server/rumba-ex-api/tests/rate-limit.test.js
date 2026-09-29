const test = require("node:test");
const assert = require("node:assert/strict");
const { createRateLimiter } = require("../middleware/rateLimit");
function request(limiter, ip, forwarded) {
  let status = 200;
  const response = { setHeader() {}, status(value) { status = value; return this; }, json() {} };
  limiter({ ip, headers: { "x-forwarded-for": forwarded }, socket: { remoteAddress: "127.0.0.1" } }, response, () => {});
  return status;
}
test("forwarded header changes do not bypass caller quota", () => {
  const limiter = createRateLimiter({ max: 1 });
  assert.equal(request(limiter, "127.0.0.1", "198.51.100.1"), 200);
  assert.equal(request(limiter, "127.0.0.1", "198.51.100.2"), 429);
});
test("capacity stays bounded and expired identities recover", () => {
  let now = 0;
  const limiter = createRateLimiter({ maxBuckets: 2, windowMs: 1000, clock: () => now });
  assert.equal(request(limiter, "a"), 200);
  assert.equal(request(limiter, "b"), 200);
  assert.equal(request(limiter, "c"), 429);
  now = 1001;
  assert.equal(request(limiter, "c"), 200);
});
