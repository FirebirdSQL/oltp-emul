WINDOWS ONLY. NOT IMPLEMENTED FOR LINUX.

This folder contains packed executables for make console output be supplied with
timestamp prefix before it will be saved to some log file.
It is useful when there is need to get precise timestamp of raised exceptions because
Firebird does not provide such information and any exception contains only lines with
error messages.
Currently this is implemented only for Windows.
See description of <use_mtee> parameter in any of "oltpNN_config.win" files.

You do not have to install any package to decompress from .zip: extraction will be done
by %systemroot%\system32\cscript utility (by generating temporary .vbs script).
