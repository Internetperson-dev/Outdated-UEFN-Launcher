(Read the about section.)


The launch options I ended up using were `VKD3D_CONFIG=descriptor_heap MESA_SHADER_CACHE_MAX_SIZE=120G __GL_SHADER_DISK_CACHE_SIZE=120000000000 PROTON_NO_NTSYNC=0 PROTON_USE_NTSYNC=1 PROTON_NO_ESYNC=0 PROTON_NO_FSYNC=0 PROTON_DLSS_INDICATOR=0 PROTON_FSR4_UPGRADE=1 PROTON_XESS_UPGRADE=1 PROTON_DLSS_UPGRADE=1 PROTON_FSR4_RDNA3_UPGRADE=1 PROTON_DXVK_LOWLATENCY=1 PROTON_NVIDIA_LIBS=1 %command%`


For:

- Improving Nvidia performance (hopefully) - https://www.reddit.com/r/linux_gaming/comments/1u6l9gd/comment/ortbsro/
- Ensuring a large shader cache
- Ensuring NTSYNC is enabled
- Dealing with upscalers
- DXVK Low latency
- Ensuring Nvidia libraries are enabled.

No. I did not predict Fortnite on LInux. These are generic commands I used for most games.
