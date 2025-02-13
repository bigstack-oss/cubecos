// CUBE SDK

#ifndef OPENSTACK_COMMON_H
#define OPENSTACK_COMMON_H

// Process extended API requires C++
#ifdef __cplusplus

enum OpenStackE {
    ENDPOINT = 0x1,
};

#define ENDPOINT_E(x)   (ENDPOINT << 16 | x)
#define ERR_TYPE(x)   (x >> 16)
#define ERR_CODE(x)   (x & 0xFFFF)

void OpenstackInit(const char* env);

#endif // __cplusplus

#endif /* endif OPENSTACK_COMMON_H */

