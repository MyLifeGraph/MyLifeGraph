FROM python:3.12.10-slim-bookworm@sha256:fd95fa221297a88e1cf49c55ec1828edd7c5a428187e67b5d1805692d11588db

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --only-binary=:all: --require-hashes \
      -r /tmp/requirements.txt \
    && rm -f /tmp/requirements.txt \
    && useradd --uid 65532 --no-create-home --shell /usr/sbin/nologin coach

COPY runner.py /opt/coach-analysis/runner.py
RUN chmod 0555 /opt/coach-analysis/runner.py

ARG COACH_ANALYSIS_REVISION=1
LABEL org.mylifegraph.coach-analysis.revision="${COACH_ANALYSIS_REVISION}"

ENV HOME=/tmp \
    MPLBACKEND=Agg \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONNOUSERSITE=1

USER 65532:65532
# The host enforces the public 30-second tool limit. This independent
# container-internal ceiling ensures an attached `docker run --rm` cannot
# survive indefinitely if the MCP or Codex host process disappears mid-turn.
ENTRYPOINT ["timeout", "--signal=KILL", "35s", "python", "-I", "/opt/coach-analysis/runner.py"]
