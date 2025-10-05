RemoteServicePort = 3400

ServerMode=Super
BugCheckAbort = 1

# 25% of total phys memory = 12Gb:
# (0.25*12)*1024*1024*1024/8192 --> 384K
DefaultDbCachePages = 384K

# deprecated in FB 4.x since 12-nov-2020, see:
# https://github.com/FirebirdSQL/firebird/commit/7e61b9f6985934cd84108549be6e2746475bb8ca
# Introduce new virtual table RDB$CONFIG.
# Implement CORE-6332 : Get rid of FileSystemCacheThreshold parameter
#   new boolean setting UseFileSystemCache overrides legacy FileSystemCacheThreshold,
#   FileSystemCacheThreshold will be removed in the next major Firebird release.
# FileSystemCacheThreshold = 99999K

UseFileSystemCache = true

LockHashSlots = 30011
LockMemSize = 10M

TempCacheLimit = 512M

UDFAccess = Restrict UDF
IpcName = oemul_fb40SS
