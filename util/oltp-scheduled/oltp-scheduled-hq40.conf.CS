RemoteServicePort = 30444

ServerMode=Classic
BugCheckAbort = 1
DefaultDbCachePages = 2048

# deprecated in FB 4.x since 12-nov-2020, see:
# https://github.com/FirebirdSQL/firebird/commit/7e61b9f6985934cd84108549be6e2746475bb8ca
# Introduce new virtual table RDB$CONFIG.
# Implement CORE-6332 : Get rid of FileSystemCacheThreshold parameter
#   new boolean setting UseFileSystemCache overrides legacy FileSystemCacheThreshold,
#   FileSystemCacheThreshold will be removed in the next major Firebird release.
# FileSystemCacheThreshold = 99999K

UseFileSystemCache = true

LockHashSlots =  49999
LockMemSize = 50M

TempCacheLimit = 64M

UdfAccess = Restrict UDF
IpcName = oemul_hq40CS
