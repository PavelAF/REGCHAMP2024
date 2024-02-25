#!/bin/bash
trap exit INT

comp_name='Competitor1'
comp_passwd='Competitor1'
stand_name='RC39_2024_stand_1'

Networking=(
	['vmbr1']='ISP<=>RTR-HQ'	['vmbr11']='ISP<=>RTR-BR'
	['vmbr2']='RTR-HQ<=>SW-HQ'	['vmbr12']='RTR-BR<=>SW-BR'
	['vmbr3']='SW-HQ<=>SRV-HQ'	['vmbr13']='SW-BR<=>SRV-BR'
	['vmbr4']='SW-HQ<=>CLI-HQ'	['vmbr14']='SW-BR<=>CLI-BR'
	['vmbr5']='SW-HQ<=>CICD-HQ'
)

echo $'\nМинимально требуемое место в хранилище (только для развертывания): 100 ГБ\nРекомендуется: 200 ГБ\nСписок доступных хранилищ:'
sl=`pvesm status --enabled 1 --content images  | awk -F' ' 'NR>1{print $1" "$6}END{if(NR==1){exit 3}}' || (echo 'Ошибка: подходящих хранилищ не найдено'; exit 3)`
echo "$sl"|awk -F' ' 'BEGIN{split("К|М|Г|Т",x,"|")}{for(i=1;$2>=1024&&i<length(x);i++)$2/=1024;print NR"\t"$1"\t"int($2)" "x[i]"Б"; }'|column -t -s$'\t' -N'Номер,Имя хранилища,Свободное место' -o$'\t' -R1
count=`echo "$sl" | wc -l`;until read -p $'Чтобы прервать установку, нажмите Ctrl-C\nВыберите номер хранилища (default=1): ' switch; [[ "${switch:=1}" =~ ^[1-9][0-9]*$ ]] && [[ "${switch:=1}" -le $count ]] do true;done
STORAGE=`echo "$sl" | awk -F' ' -v nr=$switch 'NR==nr{print $1}'`

pveum role add Competitor -privs "VM.Audit VM.Monitor VM.Console VM.PowerMgmt VM.Snapshot.Rollback VM.Config.Network"
pvesh create access/users --userid $comp_name@pve --password $comp_passwd --comment "Competition account"
pveum pool add $stand_name
pveum acl modify /pool/$stand_name -user $comp_name -role Competitor

for i in "${!Networking[@]}"
do
  iface=$i; desc=${Networking[$i]}
  cat <<IFACE >> /etc/network/interfaces

auto ${iface}
iface ${iface} inet manual
        bridge-ports none
        bridge-stp off
        bridge-fd 0
#${desc}
IFACE
  ifup $i
  pveum acl modify /sdn/zones/localnetwork/$i -user $comp_name -role PVEAuditor
done

ya_url() { echo $(curl --silent -G --data-urlencode "public_key=$1" 'https://cloud-api.yandex.net/v1/disk/public/resources/download' | grep -Po '"href":"\K[^"]+'); }

curl -L $(ya_url https://disk.yandex.ru/d/lyptnAHegU3ehA) -o ISP.vmdk
qm create 100 --name "ISP" --cores 1 --memory 1024 --net0 virtio,bridge=vmbr0 --net1 virtio,bridge=vmbr1 --net2 virtio,bridge=vmbr11 --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single 
qm importdisk 100 ISP.vmdk $STORAGE --format qcow2 
qm set 100 --scsi0 $STORAGE:vm-100-disk-0 --boot order=scsi0
rm -f ISP.vmdk
echo "ISP is done!!!"

curl -L $(ya_url https://disk.yandex.ru/d/RTO6rzQCgoi_2w) -o vESR.vmdk
qm create 101 --name "RTR-HQ" --cores 4 --memory 4096 --net0 e1000,bridge=vmbr1 --net1 e1000,bridge=vmbr2 --serial0 socket --acpi 0 --ostype l26 --scsihw virtio-scsi-single
qm importdisk 101 vESR.vmdk $STORAGE --format qcow2 
qm set 101 --scsi0 $STORAGE:vm-101-disk-0 --boot order=scsi0
echo "RTR-HQ is done!!!"

qm create 106 --name "RTR-BR" --cores 4 --memory 4096 --net0 e1000,bridge=vmbr11 --net1 e1000,bridge=vmbr12 --serial0 socket --acpi 0 --ostype l26 --scsihw virtio-scsi-single
qm importdisk 106 vESR.vmdk $STORAGE --format qcow2 
qm set 106 --scsi0 $STORAGE:vm-106-disk-0 --boot order=scsi0
rm -f vESR.vmdk
echo "RTR-BR is done!!!"

curl -L $(ya_url https://disk.yandex.ru/d/xlvUKh4LTK_Pog) -o ALT_Server.vmdk
qm create 102 --name "SW-HQ" --cores 1 --memory 1024 --net0 virtio,bridge=vmbr2 --net1 virtio,bridge=vmbr4 --net2 virtio,bridge=vmbr5 --net3 virtio,bridge=vmbr3 --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
qm importdisk 102 ALT_Server.vmdk $STORAGE --format qcow2 
qm set 102 --scsi0 $STORAGE:vm-102-disk-0 --boot order=scsi0
echo "SW-HQ is done!!!"

qm create 103 --name "SRV-HQ" --cores 2 --memory 4096 --net0 virtio,bridge=vmbr3 --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
qm importdisk 103 ALT_Server.vmdk $STORAGE --format qcow2
qm set 103 --scsi0 $STORAGE:vm-103-disk-0 --scsi1 $STORAGE:1 --scsi2 $STORAGE:1 --boot order=scsi0
echo "SRV-HQ is done!!!"

qm create 107 --name "SW-BR" --cores 1 --memory 1024 --net0 virtio,bridge=vmbr12 --net1 virtio,bridge=vmbr13 --net2 virtio,bridge=vmbr14 --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
qm importdisk 107 ALT_Server.vmdk $STORAGE --format qcow2 
qm set 107 --scsi0 $STORAGE:vm-107-disk-0 --boot order=scsi0
echo "SW-BR is done!!!"

qm create 108 --name "SRV-BR" --cores 2 --memory 2048 --net0 virtio,bridge=vmbr13 --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
qm importdisk 108 ALT_Server.vmdk $STORAGE --format qcow2
qm set 108 --scsi0 $STORAGE:vm-108-disk-0 --scsi1 $STORAGE:1 --scsi2 $STORAGE:1 --boot order=scsi0
rm -f ALT_Server.vmdk
echo "SRV-BR is done!!!"

curl -L $(ya_url https://disk.yandex.ru/d/Vf9gwcrzDPE1FQ) -o ALT_Workstation.vmdk
qm create 104 --name "CLI-HQ" --cores 2 --memory 2048 --net0 virtio,bridge=vmbr4 --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
qm importdisk 104 ALT_Workstation.vmdk $STORAGE --format qcow2
qm set 104 --scsi0 $STORAGE:vm-104-disk-0 --boot order=scsi0
echo "CLI-HQ is done!!!"

qm create 105 --name "CICD-HQ" --cores 2 --memory 2048 --net0 virtio,bridge=vmbr5 --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
qm importdisk 105 ALT_Workstation.vmdk $STORAGE --format qcow2 
qm set 105 --scsi0 $STORAGE:vm-105-disk-0 --boot order=scsi0
echo "CICD-HQ is done!!!"

qm create 109 --name "CLI-BR" --cores 2 --memory 2048 --net0 virtio,bridge=vmbr14 --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
qm importdisk 109 ALT_Workstation.vmdk $STORAGE --format qcow2 
qm set 109 --scsi0 $STORAGE:vm-109-disk-0 --boot order=scsi0
echo "CLI-BR is done!!!"
rm -f ALT_Workstation.vmdk

pvesh set /pool/$stand_name -vms "100,101,102,103,104,105,106,107,108,109"

echo "ALL DONE!!!"
