This directory contains auxiliary Python script for generating OLTP-EMUL config files.
All generated files with have names like: 'oltp<NN>_config.win.tmp' and 'oltp<NN>_config.nix.tmp',
where <NN> is 25, 30 and 40.

If you put here your actual config file then corresponding .tmp will create your actual values,
but comments will be overwritten. Original config file will be untouched.

Example:

    c:\python3x\python.exe make-config.py 
    /usr/bin/python make-config.py 

To make copy of all generated .tmp files one may to use command:

    for /f %a in ('dir /b *.tmp') do copy %a %OLTP_EMUL_HOME%\src\%~na
