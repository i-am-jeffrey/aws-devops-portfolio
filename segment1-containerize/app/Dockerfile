# Multi-stage build keeps the final image small and dependency-install
# tooling out of the runtime image. Verify the python:3.12-slim tag is
# still the version you want -- base image tags get updated over time.

# ---- build stage ----
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --target=/install -r requirements.txt

# ---- runtime stage ----
FROM python:3.12-slim
WORKDIR /app

RUN useradd --uid 1000 --shell /usr/sbin/nologin appuser

COPY --from=builder /install /usr/local/lib/python3.12/site-packages
COPY --chown=appuser:appuser app.py .

USER appuser

EXPOSE 8080
CMD ["python", "app.py"]
