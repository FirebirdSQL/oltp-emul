fgds=open('fb-gds-codes.txt', 'r')
rgds=fgds.readlines()
fgds.close()

gds_map={}
for i in range(0, len(rgds) ):
    # {335544321, "arithmetic exception, numeric overflow, or string truncation"},            /* arith_except */
    #print(rgds[i])
    
    gdscode = int(rgds[i].split('}')[0].split(',')[0].split('{')[-1])
    errtext = rgds[i].split('}')[0].replace('335544321','').split('"')[1]
    errtext = errtext.replace("'","''")

    mnemona = rgds[i].split('}')[-1][1:].replace('/*','').replace('*/','').strip()

    gds_map[ gdscode ] = [ 0, mnemona, errtext ]



fsql=open('fb-sql-codes.txt', 'r')
rsql=fsql.readlines()
fsql.close()
for i in range(0,len(rsql)):
    # {335544321, -802}, /*   1 arith_except */
    #print(rsql[i])

    gdscode = int(rsql[i].split('}')[0].split(',')[0].split('{')[-1])
    sqlcode, mnemona, errtext = gds_map[ gdscode ]
    sqlcode = int(rsql[i].split('}')[0].split(',')[1])

    gds_map[ gdscode ] = [ sqlcode, mnemona, errtext ]

#########################################

sttm = "insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( %(sqlcode)s, %(gdscode)s, '%(mnemona)s', '%(errtext)s');"

for k,v in sorted(gds_map.items()):
    # print(k,':::',v)
    gdscode = k
    sqlcode, mnemona, errtext = v
    print( sttm % locals() )

print('commit;')
