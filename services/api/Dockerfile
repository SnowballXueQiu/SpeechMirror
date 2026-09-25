FROM rust:1.85-bookworm AS builder
WORKDIR /build
COPY services/api/Cargo.toml services/api/Cargo.lock ./
COPY services/api/src ./src
COPY openapi /openapi
RUN cargo build --release --locked

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates libreoffice-core libreoffice-impress libreoffice-writer \
       poppler-utils tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-eng fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --uid 10001 speechmirror
WORKDIR /app
COPY --from=builder /build/target/release/speechmirror-api /usr/local/bin/speechmirror-api
RUN mkdir -p /app/data && chown -R speechmirror:speechmirror /app
USER speechmirror
EXPOSE 8080
ENTRYPOINT ["speechmirror-api"]
