#!/bin/python3
import os
import re
import json
try_chiplab_home = os.getenv('CHIPLAB_HOME')
try_fpga_home = os.getenv('FPGA_DIST')
target_path = '../dist'
if try_fpga_home != '' and try_fpga_home is not None:
    target_path = try_fpga_home
if try_chiplab_home != '' and try_chiplab_home is not None:
    target_path = try_chiplab_home + '/IP/myCPU/'
print("target_path: " + target_path)

module_def = {}
with open('compile_settings.json') as f:
    module_def = json.load(f)

print(module_def)

# sv_file_list = {'./inst/decoder.sv':os.path.join(target_path, 'decoder.sv'),'./inst/decoder.svh':os.path.join(target_path, 'decoder.svh')}
sv_file_list = {'./simple-decoder/rtl/decoder.sv':os.path.join(target_path, 'decoder.sv'),'./simple-decoder/rtl/decoder.svh':os.path.join(target_path, 'decoder.svh')}
# os.system("cd inst/ && python3 gen_decoder.py")
for root, dirs, files in os.walk('../rtl'):
    for file_name in files:
        path = os.path.join(root, file_name)
        ext_name = os.path.splitext(path)[1]
        if (ext_name == '.sv' or ext_name == '.svh' or ext_name == '.v' or ext_name == '.vh') and 'deperated' not in path and 'logs/annotated/' not in path and 'decoder.sv' not in path and 'decoder.svh' not in path:
            with open(path) as f:
                f = f.read()
                f = re.findall(r'--JSON--(.*)--JSON--',f)
                if len(f) != 0:
                    print(f)
                    describe = json.loads(f[0])
                    if(module_def.get(describe['module_name']) != None):
                        m_def = module_def[describe['module_name']]
                        if(m_def['module_ver'] == describe['module_ver']):
                            sv_file_list[path] = os.path.join(target_path, describe['module_name'] + ext_name)
                else:
                    sv_file_list[path] = os.path.join(target_path, file_name)

os.system("rm -r " + target_path + " && mkdir " + target_path)
for file_path in sv_file_list:
    print(file_path+ ': '+sv_file_list[file_path])
    os.system("cp " + file_path + " " + sv_file_list[file_path])
