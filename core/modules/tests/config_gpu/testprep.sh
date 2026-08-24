# The module reaches nvidia-smi and hex_sdk by absolute path, so the mocks have
# to stand in for the real binaries for the duration of the test.
for f in /usr/bin/nvidia-smi /usr/sbin/hex_sdk; do
  if [ -f "$f" ]; then
    mv "$f" "$f.bak"
  fi
done

# gpu_resource_set refuses to run at all without the truth file
mkdir -p /etc/cube/cos/gpu
echo '[]' > /etc/cube/cos/gpu/config.json

touch /etc/settings.txt
