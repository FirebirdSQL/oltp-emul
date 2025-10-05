RemoteServicePort = 30300

ServerMode=Super
BugCheckAbort = 1

# 25% of total phys memory = 12Gb:
# (0.25*12)*1024*1024*1024/8192 --> 384K
DefaultDbCachePages = 384K
FileSystemCacheThreshold = 99999K

LockHashSlots = 30011
LockMemSize = 10M

TempCacheLimit = 256M

UDFAccess = Restrict UDF
IpcName = oemul_hq30SS
