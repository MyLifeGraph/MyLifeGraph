FROM python:3.12.10-slim-bookworm

RUN pip install --no-cache-dir \
      matplotlib==3.10.3 \
      numpy==2.2.6 \
      pandas==2.2.3 \
      scipy==1.15.3 \
      statsmodels==0.14.4 \
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
