for f in /usr/bin/nvidia-smi /usr/sbin/hex_sdk; do
  if [ -f "$f.bak" ]; then
    mv "$f.bak" "$f"
  else
    rm -f "$f"
  fi
done

rm -f /etc/cube/cos/gpu/config.json /tmp/mock-hetero-capability
rm -f /tmp/gpu-order.log /tmp/gpu_order_case.log
rm -f /tmp/gpu-capability.log /tmp/mock-support-types /tmp/gpu_cap_case1.log /tmp/gpu_cap_case2.log
rm -f /etc/settings.txt
