RemoteServicePort = 3333

ServerMode=Super
BugCheckAbort = 1

# 25% of total phys memory = 4Gb:
# (0.25*4)*1024*1024*1024/8192 --> 131072
DefaultDbCachePages = 128K
FileSystemCacheThreshold = 99999K

LockHashSlots = 30011
LockMemSize = 10M

TempCacheLimit = 256M

UDFAccess = Restrict UDF
IpcName = oemul_fb30SS
