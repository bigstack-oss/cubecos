# CubeCOS (Cube Cloud Operating System)

## Prerequisites

1. Install git and git-lfs
```bash
$ sudo apt-get install git git-lfs
$ git lfs install
```

2. Clone repos
```bash
$ git clone --recursive git@github.com:bigstack-oss/cubecos.git
```

## Build Images

1. Create and enter jail (default PROJECT="centos9-jail")
```bash
$ cd cubecos
$ make [PROJECT=XXX] centos9-jail enter
```

2. Build various Cube install media (iso, usb, pxe, full, etc.) where full is everything
```bash
[root@centos9-jail centos9-jail]# make usb
```

### Troubleshoot
Other than git-lfs, make sure [hex](https://github.com/bigstack-oss/hex) (submodule) is properly cloned under your top source dir
```bash
$ ls -lt cubecos/hex
```

## License

Copyright (c) 2025 [Bigstack co., ltd](https://bigstack.co/)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
