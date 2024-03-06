#!/bin/bash
ex() { echo; exit; }
trap ex INT

comp_name='Competitor'
stand_name='RCMO39_2024_stand_B_'

Networking=(
	'ISP<=>RTR-HQ'
	'RTR-HQ<=>SW-HQ'    
	'SW-HQ<=>SRV-HQ'    
	'SW-HQ<=>CLI-HQ'    
	'SW-HQ<=>CICD-HQ'
	'ISP<=>RTR-BR'
	'RTR-BR<=>SW-BR'
	'SW-BR<=>SRV-BR'
	'SW-BR<=>CLI-BR'
)

until read -p $'Действие: 1 - Развертывание стенда, 2 - Управление пользователями\nВыберите действие: ' switch; [[ "$switch" =~ ^[1-2]$ ]]; do true;done
if [[ "$switch" == 2 ]]; then
	until read -p $'Стартовый номер участника: ' switch; [[ "$switch" =~ ^[0-9]*$ ]] && [[ "$switch" -le 100 ]]; do true;done
	until read -p $'Конечный номер участника: ' switch2; [[ "$switch2" =~ ^[0-9]*$ ]] && [[ "$switch2" -le 100 && "$switch2" -le $switch ]]; do true;done
	until read -p $'Действие: 1 - активировать пользователей, 2 - отключить аккаунты, 3 - установить пароли, 4 - удалить пользователей\nВыберите действие: ' switch3; [[ "$switch3" =~ ^[1-4]$ ]]; do true;done
	
	list=''
	for ((stand=$switch; stand<=$switch2; stand++))
	{
		[ $switch3 == 1 ] && pveum user modify $comp_name$stand@pve --enable 1
		[ $switch3 == 2 ] && pveum user modify $comp_name$stand@pve --enable 0
		[ $switch3 == 3 ] && \
		( 
			psswd=`tr -dc 'A-Za-z1-9' </dev/urandom | head -c 20`
			pvesh set /access/users/ --userid $comp_name$stand@pve --password $psswd
			list+=$'\n'"$comp_name$stand : $psswd"
		)
		[ $switch3 == 4 ] && pveum user delete $comp_name$stand@pve
	}
	echo "$list"
fi

echo $'\nМинимально требуемое место в хранилище (только для развертывания): 100 ГБ\nРекомендуется: 200 ГБ\nСписок доступных хранилищ:'
sl=`pvesm status --enabled 1 --content images  | awk -F' ' 'NR>1{print $1" "$6" "$2}END{if(NR==1){exit 3}}' || (echo 'Ошибка: подходящих хранилищ не найдено'; exit 3)`
echo "$sl"|awk -F' ' 'BEGIN{split("К|М|Г|Т",x,"|")}{for(i=1;$2>=1024&&i<length(x);i++)$2/=1024;print NR"\t"$1"\t"$3"\t"int($2)" "x[i]"Б"; }'|column -t -s$'\t' -N'Номер,Имя хранилища,Тип хранилища,Свободное место' -o$'\t' -R1
count=`echo "$sl" | wc -l`;until read -p $'Чтобы прервать установку, нажмите Ctrl-C\nВыберите номер хранилища: ' switch; [[ "$switch" =~ ^[1-9][0-9]*$ ]] && [[ "$switch" -le $count ]]; do true;done
STORAGE=`echo "$sl" | awk -F' ' -v nr=$switch 'NR==nr{print $1}'`

until read -p $'Ввведите начальный идентификатор ВМ и bridge: ' switch; [[ "$switch" =~ ^[1-9][0-9]*$ ]] && [[ "$switch" -lt 3900 && "$switch" -ge 100 ]]; do true;done
start_num=$switch

until read -p $'Ввведите стартовый номер стенда: ' switch; [[ "$switch" =~ ^[0-9]*$ ]] && [[ "$switch" -le 100 ]]; do true;done
until read -p $'Ввведите конечный номер стенда: ' switch2; [[ "$switch2" =~ ^[0-9]*$ ]] && [[ "$switch2" -le 100 && "$switch2" -le $switch ]]; do true;done

for ((stand=$switch; stand<=$switch2; stand++))
{
	pveum role add Competitor -privs 'Pool.Audit VM.Audit VM.Monitor VM.Console VM.PowerMgmt VM.Snapshot.Rollback VM.Config.Network'
	pveum user add $comp_name$stand@pve --comment 'Учетная запись участника соревнований'
	pveum pool add $stand_name$stand
	pveum acl modify /pool/$stand_name$stand -user $comp_name$stand -role Competitor

	ya_url() { echo $(curl --silent -G --data-urlencode "public_key=$1" 'https://cloud-api.yandex.net/v1/disk/public/resources/download' | grep -Po '"href":"\K[^"]+'); }
	curl -L $(ya_url https://disk.yandex.ru/d/lyptnAHegU3ehA) -o ISP.vmdk
	curl -L $(ya_url https://disk.yandex.ru/d/xlvUKh4LTK_Pog) -o ALT_Server.vmdk
	curl -L $(ya_url https://disk.yandex.ru/d/Vf9gwcrzDPE1FQ) -o ALT_Workstation.vmdk

	for i in "${Networking[@]}"
	do
	  iface=vmbr$((start_num+(stand-switch)*100+i)); desc=$i
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

	qm create $((start_num+(stand-switch)*100+0)) --name "ISP" --cores 1 --memory 1024 --startup order=1,up=10,down=30 --net0 virtio,bridge=vmbr0 --net1 virtio,bridge=${Networking['ISP<=>RTR-HQ']} --net2 virtio,bridge=${Networking['ISP<=>RTR-BR']} --vga serial0 --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single 
	qm importdisk $((start_num+(stand-switch)*100+0)) ISP.vmdk $STORAGE --format qcow2 
	qm set $((start_num+(stand-switch)*100+0)) --scsi0 $STORAGE:vm-100-disk-0 --boot order=scsi0
	echo "$stand_name$stand: ISP is done!!!"

	qm create $((start_num+(stand-switch)*100+1)) --name "RTR-HQ" --cores 2 --memory 1536 --tags 'alt_server' --startup order=2,up=20,down=0 --net0 virtio,bridge=${Networking['ISP<=>RTR-HQ']} --net1 virtio,bridge=${Networking['RTR-HQ<=>SW-HQ']} --serial0 socket --acpi 0 --ostype l26 --scsihw virtio-scsi-single
	qm importdisk $((start_num+(stand-switch)*100+1)) vESR.vmdk $STORAGE --format qcow2 
	qm set $((start_num+(stand-switch)*100+1)) --scsi0 $STORAGE:vm-101-disk-0 --boot order=scsi0
	echo "$stand_name$stand: RTR-HQ is done!!!"

	qm create $((start_num+(stand-switch)*100+2)) --name "SW-HQ" --cores 1 --memory 1024 --tags 'alt_server' --startup order=3,up=15,down=30 --net0 virtio,bridge=${Networking['RTR-HQ<=>SW-HQ']} --net1 virtio,bridge=${Networking['SW-HQ<=>CLI-HQ']} --net2 virtio,bridge=${Networking['SW-HQ<=>CICD-HQ']} --net3 virtio,bridge=${Networking['SW-HQ<=>SRV-HQ']} --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
	qm importdisk $((start_num+(stand-switch)*100+2)) ALT_Server.vmdk $STORAGE --format qcow2 
	qm set $((start_num+(stand-switch)*100+2)) --scsi0 $STORAGE:vm-102-disk-0 --boot order=scsi0
	echo "$stand_name$stand: SW-HQ is done!!!"

	qm create $((start_num+(stand-switch)*100+3)) --name "SRV-HQ" --cores 2 --memory 4096 --tags 'alt_server' --startup order=4,up=15,down=60 --net0 virtio,bridge=${Networking['SW-HQ<=>SRV-HQ']} --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
	qm importdisk $((start_num+(stand-switch)*100+3)) ALT_Server.vmdk $STORAGE --format qcow2
	qm set $((start_num+(stand-switch)*100+3)) --scsi0 $STORAGE:vm-103-disk-0 --scsi1 $STORAGE:1 --scsi2 $STORAGE:1 --boot order=scsi0
	echo "$stand_name$stand: SRV-HQ is done!!!"

	qm create $((start_num+(stand-switch)*100+6)) --name "RTR-BR" --cores 2 --memory 1536 --tags 'alt_server' --startup order=2,up=20,down=0 --net0 virtio,bridge=${Networking['ISP<=>RTR-BR']} --net1 virtio,bridge=${Networking['RTR-BR<=>SW-BR']} --serial0 socket --acpi 0 --ostype l26 --scsihw virtio-scsi-single
	qm importdisk $((start_num+(stand-switch)*100+6)) vESR.vmdk $STORAGE --format qcow2 
	qm set $((start_num+(stand-switch)*100+6)) --scsi0 $STORAGE:vm-106-disk-0 --boot order=scsi0
	echo "$stand_name$stand: RTR-BR is done!!!"

	qm create $((start_num+(stand-switch)*100+7)) --name "SW-BR" --cores 1 --memory 1024 --tags 'alt_server' --startup order=3,up=15,down=30 --net0 virtio,bridge=${Networking['RTR-BR<=>SW-BR']} --net1 virtio,bridge=${Networking['SW-BR<=>SRV-BR']} --net2 virtio,bridge=${Networking['SW-BR<=>CLI-BR']} --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
	qm importdisk $((start_num+(stand-switch)*100+7)) ALT_Server.vmdk $STORAGE --format qcow2 
	qm set $((start_num+(stand-switch)*100+7)) --scsi0 $STORAGE:vm-107-disk-0 --boot order=scsi0
	echo "$stand_name$stand: SW-BR is done!!!"

	qm create $((start_num+(stand-switch)*100+8)) --name "SRV-BR" --cores 2 --memory 2048 --tags 'alt_server' --startup order=4,up=15,down=60 --net0 virtio,bridge=${Networking['SW-BR<=>SRV-BR']} --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
	qm importdisk $((start_num+(stand-switch)*100+8)) ALT_Server.vmdk $STORAGE --format qcow2
	qm set $((start_num+(stand-switch)*100+8)) --scsi0 $STORAGE:vm-108-disk-0 --scsi1 $STORAGE:1 --scsi2 $STORAGE:1 --boot order=scsi0
	echo "$stand_name$stand: SRV-BR is done!!!"

	qm create $((start_num+(stand-switch)*100+4)) --name "CLI-HQ" --cores 2 --memory 2048 --tags 'alt_workstation' --startup order=5,up=20,down=30 --net0 virtio,bridge=${Networking['SW-HQ<=>CLI-HQ']} --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
	qm importdisk $((start_num+(stand-switch)*100+4)) ALT_Workstation.vmdk $STORAGE --format qcow2
	qm set $((start_num+(stand-switch)*100+4)) --scsi0 $STORAGE:vm-104-disk-0 --boot order=scsi0
	echo "$stand_name$stand: CLI-HQ is done!!!"

	qm create $((start_num+(stand-switch)*100+5)) --name "CICD-HQ" --cores 2 --memory 2048 --tags 'alt_workstation' --startup order=5,up=20,down=30 --net0 virtio,bridge=${Networking['SW-HQ<=>CICD-HQ']} --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
	qm importdisk $((start_num+(stand-switch)*100+5)) ALT_Workstation.vmdk $STORAGE --format qcow2 
	qm set $((start_num+(stand-switch)*100+5)) --scsi0 $STORAGE:vm-105-disk-0 --boot order=scsi0
	echo "$stand_name$stand: CICD-HQ is done!!!"

	qm create $((start_num+(stand-switch)*100+9)) --name "CLI-BR" --cores 2 --memory 2048 --tags 'alt_workstation' --startup order=5,up=20,down=30 --net0 virtio,bridge=${Networking['SW-BR<=>CLI-BR']} --serial0 socket --agent 1 --ostype l26 --scsihw virtio-scsi-single
	qm importdisk $((start_num+(stand-switch)*100+9)) ALT_Workstation.vmdk $STORAGE --format qcow2 
	qm set $((start_num+(stand-switch)*100+9)) --scsi0 $STORAGE:vm-109-disk-0 --boot order=scsi0
	echo "$stand_name$stand: CLI-BR is done!!!"
	
	pvesh set /pool/$stand_name$stand -vms "`seq -s, $((start_num+(stand-switch)*100)) 1 $((start_num+(stand-switch)*100+9))`"

	echo "ALL DONE $stand_name$stand!!!"
	
}

rm -f ISP.vmdk ALT_Server.vmdk ALT_Workstation.vmdk

