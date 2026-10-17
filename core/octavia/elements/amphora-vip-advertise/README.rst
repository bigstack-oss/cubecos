=======================
amphora-vip-advertise
=======================

Sends a gratuitous ARP (IPv4) or unsolicited neighbor advertisement (IPv6) for
every address in the ``amphora-haproxy`` namespace, 20 s after boot and every
30 s after that. A SINGLE-topology amphora otherwise announces its VIP only when
the controller plugs it, so after a reboot or a cold start OVN leaves the VIP's
virtual port unbound and the load balancer is unreachable.
