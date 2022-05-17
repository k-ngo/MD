import subprocess as sp
import glob
import os


def get_consecutive_numbers(input_file):
    input_list = list(map(int, open(input_file, 'r').readline().split()))
    ranges = sum((list(t) for t in zip(input_list, input_list[1:]) if t[0] + 1 != t[1]), [])
    iranges = iter(input_list[0:1] + ranges + input_list[-1:])
    return ','.join([str(n) + '-' + str(next(iranges)) for n in iranges])


os.makedirs('restraints', exist_ok=True)
vmd_cmd_file = 'vmd_cmd.tcl'

with open(vmd_cmd_file, 'w+') as f:
    # Load PDB
    f.write('mol new ' + glob.glob('*.pdb')[0] + ' type pdb waitfor all\n')

    # All resid
    f.write('set all_file [open "' + os.path.join('restraints', 'all.restraints') + '" w]\n')
    f.write('puts $all_file "[[ atomselect top "protein and name CA" ] get resid]"\n')
    f.write('close $all_file\n')

    # Selectivity Filter resid
    f.write('set SF_file [open "' + os.path.join('restraints', 'SF.restraints') + '" w]\n')
    f.write('puts $SF_file "[[ atomselect top "protein and name CA and sequence \'SVGFG\'" ] get resid]"\n')
    f.write('close $SF_file\n')

    # Pore Domain resid
    f.write('set PD_file [open "' + os.path.join('restraints', 'PD.restraints') + '" w]\n')
    f.write('puts $PD_file "[[ atomselect top "protein and ( resid 144 to 264 or resid 408 to 528 or resid 672 to 792 or resid 936 to 1056 ) and name CA" ] get resid]"\n')
    f.write('close $PD_file\n')

    f.write('exit')

sp.call(['/bin/bash', '-i', '-c', 'vmd -dispdev text -e ' + vmd_cmd_file], stdin=sp.PIPE)
print()

all = '(:' + get_consecutive_numbers(os.path.join('restraints', 'all.restraints')) + ')\&(@CA)'
sp.call('sed -e "s/ResIDList/' + all + '/g" step7_production_restraints_template.mdin > step7_production_restraints_all_CA.mdin', shell=True)
print('All:', all)

SF = '(:' + get_consecutive_numbers(os.path.join('restraints', 'SF.restraints')) + ')\&(@CA)'
sp.call('sed -e "s/ResIDList/' + SF + '/g" step7_production_restraints_template.mdin > step7_production_restraints_SF_CA.mdin', shell=True)
print('SF :', SF)

PD = '(:' + get_consecutive_numbers(os.path.join('restraints', 'PD.restraints')) + ')\&(@CA)'
sp.call('sed -e "s/ResIDList/' + PD + '/g" step7_production_restraints_template.mdin > step7_production_restraints_PD_CA.mdin', shell=True)
print('PD :', PD)
