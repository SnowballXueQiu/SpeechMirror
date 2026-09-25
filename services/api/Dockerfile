# syntax=docker/dockerfile:1.7
FROM rust:1.88-bookworm AS builder
WORKDIR /build
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse \
    CARGO_HTTP_MULTIPLEXING=false
COPY services/api/docker/cargo-config.toml /usr/local/cargo/config.toml
COPY services/api/Cargo.toml services/api/Cargo.lock ./
COPY services/api/src ./src
COPY openapi /openapi
RUN --mount=type=cache,id=speechmirror-cargo-registry,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,id=speechmirror-cargo-git,target=/usr/local/cargo/git,sharing=locked \
    --mount=type=cache,id=speechmirror-api-target,target=/build/target,sharing=locked \
    cargo build --release --locked \
    && install -Dm755 target/release/speechmirror-api /out/speechmirror-api

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates libreoffice-core libreoffice-impress libreoffice-writer \
       poppler-utils tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-eng fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --uid 10001 speechmirror
WORKDIR /app
COPY --from=builder /out/speechmirror-api /usr/local/bin/speechmirror-api
RUN mkdir -p /app/data && chown -R speechmirror:speechmirror /app
USER speechmirror
EXPOSE 8080
ENTRYPOINT ["speechmirror-api"]
