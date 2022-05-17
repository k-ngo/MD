#!/bin/bash

#SBATCH --job-name="herg_oS631A"
#SBATCH --output="herg_oS631A.%j.%N.out"
#SBATCH -N 1    # Total number of nodes
#SBATCH -n 1    # Total number of mpi tasks
#SBATCH -p v100
#SBATCH -t 48:00:00
#SBATCH --mail-user=khoango@ucdavis.edu
#SBATCH --mail-type=ALL

module purge
module load gcc/7.3.0  mvapich2-gdr/2.3.6 cuda/10.2 amber/20.0

amberCPU=pmemd
amberGPU=pmemd.cuda

init=step5_input
mini_prefix=step6.0_minimization
equi_prefix=step6.%d_equilibration
prod_prefix=step7.%d_production

echo ">> Starting run at: `date`"

# Minimization
sed -e "s/FC/250.0/g" dihe.restraint > ${mini_prefix}.rest
${amberCPU} -O -i ${mini_prefix}.mdin -p ${init}.parm7 -c ${init}.rst7 -o ${mini_prefix}.mdout -r ${mini_prefix}.rst7 -inf ${mini_prefix}.mdinfo -ref ${init}.rst7

# Equilibration
cnt=1
cntmax=6
fc={'250.0','100.0','50.0','50.0','25.0'}

while [ ${cnt} -le ${cntmax} ]
do
    pcnt=$((cnt - 1))
    istep=`printf ${equi_prefix} ${cnt}`
    pstep=`printf ${equi_prefix} ${pcnt}`

    if [ ${cnt} -eq 1 ]; then
        pstep=${mini_prefix}
    fi

    if [[ -e dihe.restraint && ${cnt} -lt ${cntmax} ]]; then
        sed -e "s/FC/${fc[${cnt}]}/g" dihe.restraint > ${istep}.rest
    fi

    echo ">> Now running ${istep} using ${pstep}.rst7 as input"
    ${amberGPU} -O -i ${istep}.mdin -p ${init}.parm7 -c ${pstep}.rst7 -o ${istep}.mdout -r ${istep}.rst7 -inf ${istep}.mdinfo -ref ${init}.rst7 -x ${istep}.nc

    let "cnt++"
done

# Production
cnt=1
cntmax=90

while [ ${cnt} -le ${cntmax} ]
do
    pcnt=$((cnt - 1))
    istep=`printf ${prod_prefix} ${cnt}`
    pstep=`printf ${prod_prefix} ${pcnt}`

    if [ ${cnt} -eq 1 ]; then
        pstep=`printf ${equi_prefix} 6`
    fi

    # Restraint regime
    #   6.6         1.0 kcal/mol for bb CA 0.0 for sc
    #   7.1  - 7.4  1.0 kcal/mol for bb CA
    #   7.5  - 7.10 1.0 kcal/mol pore domain CA
    #   7.11 - 7.15 0.5 kcal/mol pore domain CA
    #   7.16 - 7.20 0.25 PD
    #   7.21 - 7.30 0.1 PD
    #   7.31 - 7.40 0.1 SF
    #   7.41 - .... no restraints

    if [[ ${cnt} -ge 1 && ${cnt} -le 4 ]]; then
        sed -e "s/RestraintForce/1/g" step7_production_restraints_all_CA.mdin > ${istep}.mdin

    elif [[ ${cnt} -ge 5 && ${cnt} -le 10 ]]; then
        sed -e "s/RestraintForce/1/g" step7_production_restraints_PD_CA.mdin > ${istep}.mdin

    elif [[ ${cnt} -ge 11 && ${cnt} -le 15 ]]; then
        sed -e "s/RestraintForce/0.5/g" step7_production_restraints_PD_CA.mdin > ${istep}.mdin

    elif [[ ${cnt} -ge 16 && ${cnt} -le 20 ]]; then
        sed -e "s/RestraintForce/0.25/g" step7_production_restraints_PD_CA.mdin > ${istep}.mdin

    elif [[ ${cnt} -ge 21 && ${cnt} -le 30 ]]; then
        sed -e "s/RestraintForce/0.1/g" step7_production_restraints_PD_CA.mdin > ${istep}.mdin

    elif [[ ${cnt} -ge 31 && ${cnt} -le 40 ]]; then
        sed -e "s/RestraintForce/0.1/g" step7_production_restraints_SF_CA.mdin > ${istep}.mdin

    # Regular simulation, no restraints
    elif [[ ${cnt} -ge 41 && ${cnt} -le 90 ]]; then
        cp step7_production.mdin ${istep}.mdin

    # Simulation with electric field in z (efz, units of kcal/mol/A/e)
    # Box Z can be found using "grep Box Z step7.90_production.mdout"
    # 1 electric field unit in kcal/mol/A/e = 0.0434 V/A
    # To apply voltage of 0.750 V:   0.75 / (0.0434 * Box Z) = efz
    elif [[ ${cnt} -ge 91 && ${cnt} -le 100 ]]; then
        eField=$(bc <<< "($cnt - 90) * 0.166662867 * 0.1")
        sed -e "s/ElectricField/${eField}/g" step7_production_eField.mdin > ${istep}.mdin

    elif [ ${cnt} -ge 101 ]; then
        eField=0.166662867
        sed -e "s/ElectricField/${eField}/g" step7_production_eField.mdin > ${istep}.mdin
    fi

    # Run simulation
    echo ">> Now running ${istep} using ${pstep}.rst7 as input"
    ${amberGPU} -O -i ${istep}.mdin -p ${init}.parm7 -c ${pstep}.rst7 -o ${istep}.mdout -r ${istep}.rst7 -inf ${istep}.mdinfo -x ${istep}.nc -ref ${init}.rst7

    let "cnt++"
done

echo ">> Finished at `date`"