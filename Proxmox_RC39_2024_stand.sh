#!/bin/bash
ex() { echo; exit; }
trap ex INT

comp_name='Competitor1'
comp_passwd='Competitor1'
stand_name='RC39_2024_stand_1'
bame_vm_id=100

declare -A Networking=(
	['ISP<=>RTR-HQ']='vmbr1'      ['ISP<=>RTR-BR']='vmbr11'
	['RTR-HQ<=>SW-HQ']='vmbr2'    ['RTR-BR<=>SW-BR']='vmbr12'
	['SW-HQ<=>SRV-HQ']='vmbr3'    ['SW-BR<=>SRV-BR']='vmbr13'
	['SW-HQ<=>CLI-HQ']='vmbr4'    ['SW-BR<=>CLI-BR']='vmbr14'
	['SW-HQ<=>CICD-HQ']='vmbr5'
)

echo $'\nМинимально требуемое место в хранилище (только для развертывания): 100 ГБ\nРекомендуется: 200 ГБ\nСписок доступных хранилищ:'
sl=`pvesm status --enabled 1 --content images  | awk -F' ' 'NR>1{print $1" "$6" "$2}END{if(NR==1){exit 3}}' || (echo 'Ошибка: подходящих хранилищ не найдено'; exit 3)`
echo "$sl"|awk -F' ' 'BEGIN{split("К|М|Г|Т",x,"|")}{for(i=1;$2>=1024&&i<length(x);i++)$2/=1024;print NR"\t"$1"\t"$3"\t"int($2)" "x[i]"Б"; }'|column -t -s$'\t' -N'Номер,Имя хранилища,Тип хранилища,Свободное место' -o$'\t' -R1
count=`echo "$sl" | wc -l`;until read -p $'Чтобы прервать установку, нажмите Ctrl-C\nВыберите номер хранилища (default=1): ' switch; [[ "${switch:=1}" =~ ^[1-9][0-9]*$ ]] && [[ "${switch:=1}" -le $count ]] do true;done
STORAGE=`echo "$sl" | awk -F' ' -v nr=$switch 'NR==nr{print $1}'`

pveum role add Competitor -privs "VM.Audit VM.Monitor VM.Console VM.PowerMgmt VM.Snapshot.Rollback VM.Config.Network"
pvesh create access/users --userid $comp_name@pve --password $comp_passwd --comment "Competition account"
pveum pool add $stand_name
pveum acl modify /pool/$stand_name -user $comp_name -role Competitor

for i in "${!Networking[@]}"
do
  iface=${Networking[$i]}; desc=$i
  cat <<IFACE >> /etc/network/interfaces

auto ${iface}
iface ${iface} inet manual
        bridge-ports none
        bridge-stp off
        bridge-fd 0
#${desc}
IFACE
  ifup $iface
  pveum acl modify /sdn/zones/localnetwork/$iface -user $comp_name -role PVEAuditor
done

ya_url() { echo $(curl --silent -G --data-urlencode "public_key=$1" 'https://cloud-api.yandex.net/v1/disk/public/resources/download' | grep -Po '"href":"\K[^"]+'); }

curl -L $(ya_url https://disk.yandex.ru/d/lyptnAHegU3ehA) -o ISP.vmdk
qm create $bame_vm_id --name "ISP" --cores 1 --memory 1024 --startup order=1,up=10,down=30 --net0 virtio,bridge=vmbr0 --net1 virtio,bridge=${Networking['ISP<=>RTR-HQ']} --net2 virtio,bridge=${Networking['ISP<=>RTR-BR']} --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single 
qm importdisk $bame_vm_id ISP.vmdk $STORAGE --format qcow2 
qm set $bame_vm_id --scsi0 $STORAGE:vm-100-disk-0 --boot order=scsi0
rm -f ISP.vmdk
echo "ISP is done!!!"

curl -L $(ya_url https://disk.yandex.ru/d/RTO6rzQCgoi_2w) -o vESR.vmdk
qm create $((bame_vm_id+1)) --name "RTR-HQ" --cores 4 --memory 4096 --tags 'eltex_vesr' --startup order=2,up=20,down=0 --net0 e1000,bridge=${Networking['ISP<=>RTR-HQ']} --net1 e1000,bridge=${Networking['RTR-HQ<=>SW-HQ']} --serial0 socket --acpi 0 --ostype l26 --scsihw virtio-scsi-single
qm importdisk $((bame_vm_id+1)) vESR.vmdk $STORAGE --format qcow2 
qm set $((bame_vm_id+1)) --scsi0 $STORAGE:vm-101-disk-0 --boot order=scsi0
echo "RTR-HQ is done!!!"

qm create $((bame_vm_id+6)) --name "RTR-BR" --cores 4 --memory 40966 --tags 'eltex_vesr' --startup order=2,up=20,down=0 --net0 e1000,bridge=${Networking['ISP<=>RTR-BR']} --net1 e1000,bridge=${Networking['RTR-BR<=>SW-BR']} --serial0 socket --acpi 0 --ostype l26 --scsihw virtio-scsi-single
qm importdisk $((bame_vm_id+6)) vESR.vmdk $STORAGE --format qcow2 
qm set $((bame_vm_id+6)) --scsi0 $STORAGE:vm-106-disk-0 --boot order=scsi0
rm -f vESR.vmdk
echo "RTR-BR is done!!!"

curl -L $(ya_url https://disk.yandex.ru/d/xlvUKh4LTK_Pog) -o ALT_Server.vmdk
qm create $((bame_vm_id+2)) --name "SW-HQ" --cores 1 --memory 1024 --tags 'alt_server' --startup order=3,up=15,down=30 --net0 virtio,bridge=${Networking['RTR-HQ<=>SW-HQ']} --net1 virtio,bridge=${Networking['SW-HQ<=>CLI-HQ']} --net2 virtio,bridge=${Networking['SW-HQ<=>CICD-HQ']} --net3 virtio,bridge=${Networking['SW-HQ<=>SRV-HQ']} --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
qm importdisk $((bame_vm_id+2)) ALT_Server.vmdk $STORAGE --format qcow2 
qm set $((bame_vm_id+2)) --scsi0 $STORAGE:vm-102-disk-0 --boot order=scsi0
echo "SW-HQ is done!!!"

qm create $((bame_vm_id+3)) --name "SRV-HQ" --cores 2 --memory 4096 --tags 'alt_server' --startup order=4,up=15,down=60 --net0 virtio,bridge=${Networking['SW-HQ<=>SRV-HQ']} --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
qm importdisk $((bame_vm_id+3)) ALT_Server.vmdk $STORAGE --format qcow2
qm set $((bame_vm_id+3)) --scsi0 $STORAGE:vm-103-disk-0 --scsi1 $STORAGE:1 --scsi2 $STORAGE:1 --boot order=scsi0
echo "SRV-HQ is done!!!"

qm create $((bame_vm_id+7)) --name "SW-BR" --cores 1 --memory 1024 --tags 'alt_server' --startup order=3,up=15,down=30 --net0 virtio,bridge=${Networking['RTR-BR<=>SW-BR']} --net1 virtio,bridge=${Networking['SW-BR<=>SRV-BR']} --net2 virtio,bridge=${Networking['SW-BR<=>CLI-BR']} --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
qm importdisk $((bame_vm_id+7)) ALT_Server.vmdk $STORAGE --format qcow2 
qm set $((bame_vm_id+7)) --scsi0 $STORAGE:vm-107-disk-0 --boot order=scsi0
echo "SW-BR is done!!!"

qm create $((bame_vm_id+8)) --name "SRV-BR" --cores 2 --memory 2048 --tags 'alt_server' --startup order=4,up=15,down=60 --net0 virtio,bridge=${Networking['SW-BR<=>SRV-BR']} --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
qm importdisk $((bame_vm_id+8)) ALT_Server.vmdk $STORAGE --format qcow2
qm set $((bame_vm_id+8)) --scsi0 $STORAGE:vm-108-disk-0 --scsi1 $STORAGE:1 --scsi2 $STORAGE:1 --boot order=scsi0
rm -f ALT_Server.vmdk
echo "SRV-BR is done!!!"

curl -L $(ya_url https://disk.yandex.ru/d/Vf9gwcrzDPE1FQ) -o ALT_Workstation.vmdk
qm create $((bame_vm_id+4)) --name "CLI-HQ" --cores 2 --memory 2048 --tags 'alt_workstation' --startup order=5,up=20,down=30 --net0 virtio,bridge=${Networking['SW-HQ<=>CLI-HQ']} --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
qm importdisk $((bame_vm_id+4)) ALT_Workstation.vmdk $STORAGE --format qcow2
qm set $((bame_vm_id+4)) --scsi0 $STORAGE:vm-104-disk-0 --boot order=scsi0
echo "CLI-HQ is done!!!"

qm create $((bame_vm_id+5)) --name "CICD-HQ" --cores 2 --memory 2048 --tags 'alt_workstation' --startup order=5,up=20,down=30 --net0 virtio,bridge=${Networking['SW-HQ<=>CICD-HQ']} --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
qm importdisk $((bame_vm_id+5)) ALT_Workstation.vmdk $STORAGE --format qcow2 
qm set $((bame_vm_id+5)) --scsi0 $STORAGE:vm-105-disk-0 --boot order=scsi0
echo "CICD-HQ is done!!!"

qm create $((bame_vm_id+9)) --name "CLI-BR" --cores 2 --memory 2048 --tags 'alt_workstation' --startup order=5,up=20,down=30 --net0 virtio,bridge=${Networking['SW-BR<=>CLI-BR']} --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
qm importdisk $((bame_vm_id+9)) ALT_Workstation.vmdk $STORAGE --format qcow2 
qm set $((bame_vm_id+9)) --scsi0 $STORAGE:vm-109-disk-0 --boot order=scsi0
echo "CLI-BR is done!!!"
rm -f ALT_Workstation.vmdk

pvesh set /pool/$stand_name -vms "`seq -s, $bame_vm_id 1 $((bame_vm_id+9))`"

echo "ALL DONE!!!"
