FROM python:3.12-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends ffmpeg ca-certificates curl unzip \
  && rm -rf /var/lib/apt/lists/* \
  && pip install --no-cache-dir -U yt-dlp bgutil-ytdlp-pot-provider \
  && arch="$(uname -m)" \
  && case "$arch" in \
       x86_64)  deno_arch=x86_64-unknown-linux-gnu ;; \
       aarch64) deno_arch=aarch64-unknown-linux-gnu ;; \
       *) echo "unsupported arch $arch" && exit 1 ;; \
     esac \
  && curl -fsSL "https://github.com/denoland/deno/releases/latest/download/deno-${deno_arch}.zip" -o /tmp/deno.zip \
  && unzip /tmp/deno.zip -d /usr/local/bin \
  && rm /tmp/deno.zip \
  && chmod +x /usr/local/bin/deno

COPY run.sh /usr/local/bin/run.sh
RUN chmod 0755 /usr/local/bin/run.sh

WORKDIR /data
ENTRYPOINT ["/usr/local/bin/run.sh"]
