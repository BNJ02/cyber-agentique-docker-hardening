FROM mitmproxy/mitmproxy:latest
COPY filter.py /opt/filter.py
# Run as a plain HTTP forward proxy on :8080 with our egress addon.
ENTRYPOINT ["mitmdump", "--listen-host", "0.0.0.0", "--listen-port", "8080", \
            "--set", "block_global=false", "-s", "/opt/filter.py"]
