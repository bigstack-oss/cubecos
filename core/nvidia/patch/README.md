# Patches to the NVIDIA open kernel modules

nvidia.mk applies these to the `kernel-open` sources of `NVIDIA-Linux-x86_64-580.105.06-vgpu-kvm-aie.run`
after extracting the installer, before it builds `nvidia.ko` and `nvidia-vgpu-vfio.ko`. Each
`kernel-open/<path>.patch` modifies `kernel-open/<path>`. A pristine `<path>.orig` sits beside a patch when
the file is the same as in NVIDIA's public open-gpu-kernel-modules release of that driver (580.105.08), to
pin what the patch was made against. The files only the vGPU package carries, or carries in its own
version (`Kbuild`, `conftest.sh` and `nvidia-vgpu-vfio/`), have the patch alone.

What they carry, so the modules build and run on the Linux 7.2 kernel as well as on 6.12:

- The kernel compatibility changes of NVIDIA's own later 580 release, 580.178.04: conftest compiles its
  probes with `-fms-extensions` as the kernel now does, and probes `vm_flags_set`, `vma_flags_set_word`,
  `__is_vma_write_locked`, `pci_resize_resource`'s `exclude_bars`, `dma_map_ops.map_phys` and
  `linux/of_gpio.h`, with the code that uses them; `nv_in_hardirq` for the removed `in_irq`. Only
  compatibility hunks are taken: nothing that changes the interface to the driver's prebuilt core
  (`nv-kernel.o_binary`), which stays 580.105.06's.
- `strncpy`, gone from the kernel: `memcpy` where NVIDIA's later release has it, and a local copy loop in
  `nvswitch_os_strncpy`, which the prebuilt core still imports.
- `nvidia-vgpu-vfio`, which NVIDIA does not publish, adapted by hand:
  - `get_region_info_caps` (Linux 6.19): the VFIO core answers `VFIO_DEVICE_GET_REGION_INFO` through this
    op and no longer passes it to `.ioctl`, so without it QEMU cannot read a vGPU's regions.
  - The irq bypass producer (Linux 6.17) takes its eventfd and IRQ at registration. `enable_apicv` is
    exported to kvm-amd and kvm-intel only on current kernels, so with that API the producer is
    registered unconditionally, as vfio-pci does, and KVM decides whether to post the interrupt.
  - The memory-failure handling written against `pfn_address_space.ops` stays compiled out on upstream's
    structure, which has no `ops`, as it is on kernels without the structure.

Every change is behind a conftest probe, so the same patched sources build for 6.12 and for 7.2.

## License

The patches are released under the terms of the files they modify. Those under `nvidia-vgpu-vfio/` are
under the MIT license below. The others are under the MIT license below and, like the modules built from
them (`MODULE_LICENSE("Dual MIT/GPL")`), may alternatively be used under the GNU General Public License,
version 2. Portions are taken from NVIDIA's open-gpu-kernel-modules 580.178.04.

```
Copyright (c) NVIDIA CORPORATION & AFFILIATES. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
```
