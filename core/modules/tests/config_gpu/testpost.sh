for f in /usr/bin/nvidia-smi /usr/sbin/hex_sdk; do
  if [ -f "$f.bak" ]; then
    mv "$f.bak" "$f"
  else
    rm -f "$f"
  fi
done

rm -f /etc/cube/cos/gpu/config.json /tmp/mock-hetero-capability
rm -f /tmp/gpu-order.log /tmp/gpu_order_case.log
rm -f /etc/settings.txt
