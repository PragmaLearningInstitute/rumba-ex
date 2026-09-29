function createRateLimiter({ windowMs = 60000, max = 60, maxBuckets = 10000, clock = Date.now } = {}) {
  if (![windowMs, max, maxBuckets].every(n => Number.isInteger(n) && n > 0)) throw new TypeError("Invalid rate-limit bounds");
  const buckets = new Map();
  let nextCleanup = 0;
  return function rateLimiter(req, res, next) {
    const now = clock();
    if (now >= nextCleanup) {
      for (const [key, value] of buckets) if (value.resetAt <= now) buckets.delete(key);
      nextCleanup = now + windowMs;
    }
    const key = req.ip || req.socket?.remoteAddress || "unknown";
    let current = buckets.get(key);
    const reject = (retry) => {
      res.setHeader("Retry-After", String(Math.max(1, Math.ceil(retry / 1000))));
      return res.status(429).json({ error: "Trop de requêtes. Réessayez plus tard." });
    };
    if (!current || current.resetAt <= now) {
      if (!current && buckets.size >= maxBuckets) return reject(windowMs);
      current = { count: 0, resetAt: now + windowMs };
      buckets.set(key, current);
    }
    if (current.count >= max) return reject(current.resetAt - now);
    current.count += 1;
    return next();
  };
}
module.exports = { createRateLimiter, recommendRateLimiter: createRateLimiter() };
