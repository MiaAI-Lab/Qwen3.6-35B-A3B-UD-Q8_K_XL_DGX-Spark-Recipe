FROM nvidia/cuda:13.0.0-devel-ubuntu24.04 AS llama-cpp

ARG DEBIAN_FRONTEND=noninteractive
ARG LLAMA_CPP_REF=master
ARG CMAKE_CUDA_ARCHITECTURES=121

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    cmake \
    curl \
    git \
    build-essential \
    libcurl4-openssl-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --depth 1 --branch "${LLAMA_CPP_REF}" https://github.com/ggml-org/llama.cpp.git

WORKDIR /opt/llama.cpp
RUN set -eu; \
  cuda_stub_dir=""; \
  for dir in /usr/local/cuda/targets/*/lib/stubs; do \
    if [ -f "${dir}/libcuda.so" ]; then \
      cuda_stub_dir="${dir}"; \
      break; \
    fi; \
  done; \
  if [ -z "${cuda_stub_dir}" ]; then \
    echo "CUDA driver stub libcuda.so not found" >&2; \
    exit 1; \
  fi; \
  ln -sf "${cuda_stub_dir}/libcuda.so" "${cuda_stub_dir}/libcuda.so.1"; \
  cmake -B build \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES="${CMAKE_CUDA_ARCHITECTURES}" \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath-link,${cuda_stub_dir} -L${cuda_stub_dir}" \
    -DCMAKE_BUILD_TYPE=Release \
  && cmake --build build --config Release -j"$(nproc)" --target llama-server

FROM nvidia/cuda:13.0.0-runtime-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    libgomp1 \
    python3 \
    python3-pip \
    procps \
  && pip3 install --break-system-packages --no-cache-dir 'huggingface_hub[cli]' \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=llama-cpp /opt/llama.cpp/build/bin/llama-server /usr/local/bin/llama-server
COPY --from=llama-cpp /opt/llama.cpp/build/bin/*.so* /usr/local/lib/
COPY start.sh stop.sh docker-entrypoint.sh ./

RUN ldconfig \
  && chmod +x /usr/local/bin/llama-server /app/start.sh /app/stop.sh /app/docker-entrypoint.sh

ENV LLAMA_SERVER_BIN=/usr/local/bin/llama-server
EXPOSE 8888

ENTRYPOINT ["/app/docker-entrypoint.sh"]
