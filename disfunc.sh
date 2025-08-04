#!/bin/sh
#file: /usr/bin/dis
#disassemble a function
#author: jusse@2013.12.12
#editor: song

routine=$1
func=$2

if [ -z "$routine" ]; then
    exit
fi

address=$(nm -n $routine | grep -A1 "\w\s$func" | cut -d' ' -f1)
start=$(echo $address | cut -d' ' -f1)
end=$(echo $address | cut -d' ' -f2)

if [ -z "$func" ]; then
    objdump -d $routine
else
    echo "address: 0x${start} ~ 0x${end}"
    objdump -d $routine --start-address="0x${start}" --stop-address="0x${end}"
fi
