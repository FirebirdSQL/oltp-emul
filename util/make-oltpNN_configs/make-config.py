import os
import sys
import msvcrt
import re

whoami = os.path.realpath(sys.argv[0])

for os_name in ('win', 'nix'):

    for fb in ('25', '30', '40'):

        os_suffix = '_'+os_name

        fb_suffix = '_'+fb+'x'

        cfgname='oltp' + fb + '_config.' + os_suffix[1:]

        if os.path.isfile( cfgname ):
            fc = open( os.path.join( os.path.split(whoami)[0], cfgname ), 'r' )
            cfgvalues = [ c.strip() for c in fc.readlines() if c.strip() and c.strip()[0] != '#' ]
            fc.close()
        else:
            cfgvalues = []


        fn = open( os.path.splitext(whoami)[0] + '.txt' )
        all_comments = fn.readlines()
        fn.close()

        # ['intro00', 'intro01', 'fbc', 'dbnm', ...,  'gather_hardware_info', 'intro08', 'use_mtee', 'is_embed']
        p_order = [ p[1:].strip() for p in all_comments if p.lstrip().startswith('#') ]
        #print(p_order)

        # fo = open( '.'.join( ( os.path.splitext(whoami)[0], fb, 'tmp' ) ), 'w' )
        fo = open(  os.path.join( os.path.split(whoami)[0],  'oltp' + fb + '_config.' + os_name + '.tmp' ), 'w' )

        if os_name == 'nix':
            msvcrt.setmode(fo.fileno(), os.O_BINARY)
        else:
            msvcrt.setmode(fo.fileno(), os.O_TEXT)

        indent = 0
        for p_name in p_order:

            prefix_for_comments = ( p_name + '_all', p_name + '_all' + os_suffix, p_name + fb_suffix + '_all', p_name + os_suffix, p_name + fb_suffix + os_suffix )
            prefix_for_defaults = ( p_name + '_def_all', p_name + '_def_all' + os_suffix, p_name + '_def' + fb_suffix, p_name + '_def' + os_suffix, p_name + '_def' + fb_suffix + os_suffix )
            
            p_comments = [ x for x in all_comments if x.split(':')[0] in ( prefix_for_comments ) ]
            p_defaults = [ x for x in all_comments if x.split(':')[0] in ( prefix_for_defaults ) ]

            DBGNAME = '' # 'separate_workers'
            if p_name == DBGNAME:
                print('prefix_for_defaults = ',prefix_for_defaults)
                print('prefix_for_comments = ',prefix_for_comments)
                print('p_defaults=',p_defaults)
                print('p_comments:')
                for p in p_comments:
                    print(' '*4, p.rstrip())

            c_text = ''
            for c in p_comments:
                c_pref = c.split(':')[0]
                c_text = c[ len(c_pref)+1 : ]
                
                if c_text[0] == ' ':
                    c_text = c_text[ 1 : ]

                #print(c_text)
                try:
                    fo.write(c_text % locals() )
                except TypeError as e:
                    fo.write(c_text)

                indent = len(c_text) - len(c_text.lstrip())
            
            p_value = ''.join( [c for c in cfgvalues if c.split('=')[0].strip() == p_name] )


            if p_value:
                fo.write( ' '*indent +  p_value+'\n' )
            elif not p_name.startswith('intro'):
                # WRONG ::: p_default = ''.join( [ d for d in p_defaults if d.split('_')[0] == p_name ] )
                p_default = ''.join( [ d for d in p_defaults if d.split(':')[0].startswith( p_name+'_def') ] )
                default_key = p_default.split(':')[0]

                if p_name == DBGNAME:
                    print('p_default=',p_default)
                    print('default_key=',default_key)

                p_default = p_default[ len(default_key)+1 : ].strip()
                if p_default:
                    try:
                        p_default = p_default % locals()
                    except TypeError as e:
                        pass
    
                if p_comments or p_defaults:
                    fo.write( ' '*indent + ( p_default if p_default else '# ' + p_name +' = <no value defined>' ) +'\n' )

            if c_text:
                fo.write('\n'*2)
            else:
                fo.write('\n')

            if p_name == DBGNAME:
                print('default p_value=',p_default)
                #exit(1)

            #print('>'+p_name+'<',':::',prefix_for_comments)

        fo.close()
