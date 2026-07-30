export default class DurationReporter {
  onBegin(_config, suite) {
    this.startedAt = performance.now();
    this.testCount = suite.allTests().length;
  }

  onTestEnd(test, result) {
    console.log(
      `[e2e:test-timing] ${JSON.stringify({
        test: test.title,
        file: test.location.file,
        duration_ms: result.duration,
        retry: result.retry,
        status: result.status,
      })}`,
    );
  }

  onEnd(result) {
    console.log(
      `[e2e:timing] ${JSON.stringify({
        phase: 'journeys',
        suite: process.env.E2E_SUITE ?? 'full',
        duration_ms: Math.round(performance.now() - this.startedAt),
        tests: this.testCount,
        status: result.status,
      })}`,
    );
  }
}
