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


```
```text
[user@host ~]$ find /tmp "$HOME" -maxdepth 2 -type f \
  \( -name 'steam-*.log' -o -name 'steam-proton.log' \) \
  -mmin -5 -print 2>/dev/null

(no output)

[user@host ~]$ find "$HOME" -type f \
  \( -name 'steam-*.log' -o -name 'steam-proton.log' \) \
  -mmin -30 -print 2>/dev/null

(no output)

[user@host ~]$ ps -eo pid,args | grep -Ei '\.exe|wine|wineserver' | grep -v grep

135701 python3 [GE-Proton path]/proton waitforexitandrun \
  [Fortnite path]/FortniteGame/Binaries/Win64/UnrealEditorFortnite-Win64-Shipping.exe \
  [Epic launch arguments redacted] \
  PROTON_LOG=1 PROTON_LOG_DIR=/tmp PROTON_USE_NTSYNC=1 %command%

135790 C:\windows\system32\steam.exe \
  [Fortnite executable and launch arguments redacted]

135792 [GE-Proton path]/files/bin/wineserver
135797 C:\windows\system32\services.exe
135800 C:\windows\system32\winedevice.exe
135815 C:\windows\system32\svchost.exe -k LocalServiceNetworkRestricted
135820 C:\windows\system32\plugplay.exe
135827 C:\windows\system32\winedevice.exe
135846 C:\windows\system32\explorer.exe /desktop
135852 C:\windows\system32\rpcss.exe
135862 C:\windows\system32\tabtip.exe
135864 [GE-Proton path]/files/share/wine/../xalia/xalia.exe
135869 [Fortnite executable] [Epic launch arguments redacted]
135888 [Fortnite crash reporter] [arguments redacted]

[user@host ~]$ tr '\0' '\n' < /proc/GAME_PID/environ | sort \
  | grep -E '^(VKD3D_CONFIG|MESA_SHADER_CACHE_MAX_SIZE|__GL_SHADER_DISK_CACHE_SIZE|PROTON_)='

zsh: no such file or directory: /proc/GAME_PID/environ

[user@host ~]$ tr '\0' '\n' < /proc/135888/environ | sort \
  | grep -E '^(VKD3D_CONFIG|MESA_SHADER_CACHE_MAX_SIZE|__GL_SHADER_DISK_CACHE_SIZE|PROTON_[^=]*)='

__GL_SHADER_DISK_CACHE_SIZE=120000000000
MESA_SHADER_CACHE_MAX_SIZE=120G
PROTON_DLL_COPY=*
PROTON_DLSS_INDICATOR=0
PROTON_DLSS_UPGRADE=1
PROTON_DXVK_LOWLATENCY=1
PROTON_FSR4_RDNA3_UPGRADE=1
PROTON_FSR4_UPGRADE=1
PROTON_NO_ESYNC=0
PROTON_NO_FSYNC=0
PROTON_NO_NTSYNC=0
PROTON_NVIDIA_LIBS=1
PROTON_USE_NTSYNC=1
PROTON_USE_XALIA=1
PROTON_XESS_UPGRADE=1
VKD3D_CONFIG=descriptor_heap
```

I found out that unlike Steam, the command line options do not deal with Proton.

You can pass values through environment.d

```
[user@computer ~]$ ls .config/environment.d/gaming.conf 
.config/environment.d/gaming.conf
[user@computer ~]$ cat .config/environment.d/gaming.conf 
# Increase AMD's shader cache size to 120GB
MESA_SHADER_CACHE_MAX_SIZE=120G

# Increase Nvidia's shader cache size to 120GB
__GL_SHADER_DISK_CACHE_SIZE=120000000000

# Improved Nvidia DX12 performance
VKD3D_CONFIG=descriptor_heap

# https://www.reddit.com/r/linux_gaming/comments/1so95fj/psa_you_need_to_add_another_command_now_to/
# https://www.reddit.com/r/linux_gaming/comments/1vgc4ww/comment/p1wi3sb/

# Ensure NTSync is enabled
PROTON_NO_NTSYNC=0
PROTON_USE_NTSYNC=1

# Esync/Fsync
PROTON_NO_ESYNC=0
PROTON_NO_FSYNC=0

# Upgrade Upscalers
PROTON_DLSS_INDICATOR=0
PROTON_FSR4_UPGRADE=1
PROTON_XESS_UPGRADE=1
PROTON_DLSS_UPGRADE=1
PROTON_FSR4_RDNA3_UPGRADE=1

# DXVK Low Latency
PROTON_DXVK_LOWLATENCY=1

# Nvidia libraries
PROTON_NVIDIA_LIBS=1
```
