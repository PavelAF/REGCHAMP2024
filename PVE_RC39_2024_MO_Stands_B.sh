#!/bin/bash
ex() { echo; exit; }
trap ex INT

# exec:		sh='PVE_RC39_2024_MO_Stands_B.sh';curl -sOLH 'Cache-Control: no-cache' "https://raw.githubusercontent.com/PavelAF/REGCHAMP2024/111/$sh"&&chmod +x $sh&&./$sh;rm -f $sh

comp_name='Competitor'
stand_name='RCMO39_2024_stand_B_'
vm_opts=( '--serial0' socket '--agent' 1 '--ostype' l26 '--scsihw' virtio-scsi-single '--cpu' 'cputype=host' )
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
	until read -p $'Стартовый номер участника: ' switch; [[ "$switch" =~ ^[0-9]*$ ]] && [[ $switch -le 100 ]]; do true;done
	until read -p $'Конечный номер участника: ' switch2; [[ "$switch2" =~ ^[0-9]*$ ]] && [[ $switch2 -le 100 && $switch2 -ge $switch ]]; do true;done
	until read -p $'Действие: 1 - активировать пользователей, 2 - отключить аккаунты, 3 - установить пароли, 4 - удалить пользователей\nВыберите действие: ' switch3; [[ "$switch3" =~ ^[1-4]$ ]]; do true;done

	for ((stand=$switch; stand<=$switch2; stand++))
	{
		[ $switch3 == 1 ] && pveum user modify $comp_name$stand@pve --enable 1
		[ $switch3 == 2 ] && pveum user modify $comp_name$stand@pve --enable 0
		[ $switch3 == 3 ] && \
		(
			psswd=`tr -dc 'A-Za-z1-9' </dev/urandom | head -c 20`
			pvesh set /access/password --userid $comp_name$stand@pve --password $psswd
			echo $'\n'"$comp_name$stand : $psswd"
		)
		[ $switch3 == 4 ] && pveum user delete $comp_name$stand@pve
	}
	exit
fi

echo $'\nМинимально требуемое место в хранилище (только для развертывания): 100 ГБ\nРекомендуется: 200 ГБ\nСписок доступных хранилищ:'
sl=`pvesm status --enabled 1 --content images  | awk -F' ' 'NR>1{print $1" "$6" "$2}END{if(NR==1){exit 3}}' || (echo 'Ошибка: подходящих хранилищ не найдено'; exit 3)`
echo "$sl"|awk -F' ' 'BEGIN{split("К|М|Г|Т",x,"|")}{for(i=1;$2>=1024&&i<length(x);i++)$2/=1024;print NR"\t"$1"\t"$3"\t"int($2)" "x[i]"Б"; }'|column -t -s$'\t' -N'Номер,Имя хранилища,Тип хранилища,Свободное место' -o$'\t' -R1
count=`echo "$sl" | wc -l`;until read -p $'Чтобы прервать установку, нажмите Ctrl-C\nВыберите номер хранилища: ' switch; [[ "$switch" =~ ^[1-9][0-9]*$ ]] && [[ $switch -le $count ]]; do true;done
STORAGE=`echo "$sl" | awk -F' ' -v nr=$switch 'NR==nr{print $1}'`

until read -p $'Ввведите начальный идентификатор ВМ и bridge: ' switch; [[ "$switch" =~ ^[1-9][0-9]*$ ]] && [[ $switch -lt 3900 && $switch -ge 100 ]]; do true;done
start_num=$switch

until read -p $'Ввведите стартовый номер стенда: ' switch; [[ "$switch" =~ ^[0-9]*$ ]] && [[ $switch -le 100 ]]; do true;done
until read -p $'Ввведите конечный номер стенда: ' switch2; [[ "$switch2" =~ ^[0-9]*$ ]] && [[ $switch2 -le 100 && $switch2 -ge $switch ]]; do true;done

pveum role add Competitor 2> /dev/null
pveum role modify Competitor -privs 'Pool.Audit VM.Audit VM.Monitor VM.Console VM.PowerMgmt VM.Snapshot.Rollback VM.Config.Network'
ya_url() { echo $(curl --silent -G --data-urlencode "public_key=$1" --data-urlencode "path=/$2" 'https://cloud-api.yandex.net/v1/disk/public/resources/download' | grep -Po '"href":"\K[^"]+'); }
[ "$(file -b --mime-type ISP.qcow2)" == application/x-qemu-disk ] || curl -L $(ya_url https://disk.yandex.ru/d/xPK-Kt3E7Slmbg ISP.qcow2) -o ISP.qcow2
[ "$(file -b --mime-type Alt-Server.qcow2)" == application/x-qemu-disk ] || curl -L $(ya_url https://disk.yandex.ru/d/xPK-Kt3E7Slmbg Alt-Server.qcow2) -o Alt-Server.qcow2
[ "$(file -b --mime-type Alt-Workstation.qcow2)" == application/x-qemu-disk ] || curl -L $(ya_url https://disk.yandex.ru/d/xPK-Kt3E7Slmbg Alt-Workstation.qcow2) -o Alt-Workstation.qcow2

netifs() { printf '%s\n' "$@" | awk -v x="$(printf '%s\n' "${Networking[@]}")" -v id=$id 'BEGIN{n=0;split(x, a); for (i in a) dict[a[i]]="vmbr"i+id} $0 in dict || $0~/^vmbr[0-9]+$/{br=(dict[$1])? dict[$1] : $1;printf " --net" n " virtio,bridge=" br;n++ }'; }

for ((stand=$switch; stand<=$switch2; stand++))
{
	pveum user add $comp_name$stand@pve --comment 'Учетная запись участника соревнований'
	pveum pool add $stand_name$stand
	pveum acl modify /pool/$stand_name$stand --users $comp_name$stand@pve --roles Competitor

	id=$((start_num+(stand-switch)*100))
	for i in "${!Networking[@]}"
	do
		iface=vmbr$((id+i+1)); desc=${Networking[$i]}
		cat <<IFACE >> /etc/network/interfaces

auto ${iface}
iface ${iface} inet manual
	bridge-ports none
	bridge-stp off
	bridge-fd 0
#${desc}
IFACE
		ifup $iface
		pveum acl modify /sdn/zones/localnetwork/$iface --users $comp_name$stand@pve --roles PVEAuditor
	done

 	vmid=$id
	qm create $vmid --name "ISP" --cores 1 --memory 1024 --startup order=1,up=10,down=30 $(netifs vmbr0 'ISP<=>RTR-HQ' 'ISP<=>RTR-BR') "${vm_opts[@]}"
	qm importdisk $vmid ISP.qcow2 $STORAGE --format qcow2 | tail -n -3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: ISP is done!!!"

	((vmid++))
	qm create $vmid --name "RTR-HQ" --cores 2 --memory 1536 --tags 'alt_server' --startup order=2,up=20,down=30 $(netifs 'ISP<=>RTR-HQ' 'RTR-HQ<=>SW-HQ') "${vm_opts[@]}"
	qm importdisk $vmid Alt-Server.qcow2 $STORAGE --format qcow2 | tail -n -3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: RTR-HQ is done!!!"

	((vmid++))
	qm create $vmid --name "SW-HQ" --cores 1 --memory 1536 --tags 'alt_server' --startup order=3,up=15,down=30 $(netifs 'RTR-HQ<=>SW-HQ' 'SW-HQ<=>SRV-HQ' 'SW-HQ<=>CLI-HQ' 'SW-HQ<=>CICD-HQ') "${vm_opts[@]}"
	qm importdisk $vmid Alt-Server.qcow2 $STORAGE --format qcow2 | tail -n -3
 	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: SW-HQ is done!!!"

	((vmid++))
	qm create $vmid --name "SRV-HQ" --cores 2 --memory 4096 --tags 'alt_server' --startup order=4,up=15,down=60 $(netifs 'SW-HQ<=>SRV-HQ') "${vm_opts[@]}"
	qm importdisk $vmid Alt-Server.qcow2 $STORAGE --format qcow2 | tail -n -3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --scsi1 $STORAGE:1,iothread=1 --scsi2 $STORAGE:1,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: SRV-HQ is done!!!"

	((vmid++))
	qm create $vmid --name "CLI-HQ" --cores 2 --memory 2048 --tags 'alt_workstation' --startup order=5,up=20,down=30 $(netifs 'SW-HQ<=>CLI-HQ') "${vm_opts[@]}"
	qm importdisk $vmid Alt-Workstation.qcow2 $STORAGE --format qcow2 | tail -n -3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: CLI-HQ is done!!!"

	((vmid++))
	qm create $vmid --name "CICD-HQ" --cores 2 --memory 2048 --tags 'alt_workstation' --startup order=5,up=20,down=30 $(netifs 'SW-HQ<=>CICD-HQ') "${vm_opts[@]}"
	qm importdisk $vmid Alt-Workstation.qcow2 $STORAGE --format qcow2 | tail -n -3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: CICD-HQ is done!!!"
 
	((vmid++))
	qm create $vmid --name "RTR-BR" --cores 2 --memory 1536 --tags 'alt_server' --startup order=2,up=20,down=30 $(netifs 'ISP<=>RTR-BR' 'RTR-BR<=>SW-BR') "${vm_opts[@]}"
	qm importdisk $vmid Alt-Server.qcow2 $STORAGE --format qcow2 | tail -n -3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: RTR-BR is done!!!"

	((vmid++))
	qm create $vmid --name "SW-BR" --cores 1 --memory 1536 --tags 'alt_server' --startup order=3,up=15,down=30 $(netifs 'RTR-BR<=>SW-BR' 'SW-BR<=>SRV-BR' 'SW-BR<=>CLI-BR') "${vm_opts[@]}"
	qm importdisk $vmid Alt-Server.qcow2 $STORAGE --format qcow2 | tail -n -3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: SW-BR is done!!!"

	((vmid++))
	qm create $vmid --name "SRV-BR" --cores 2 --memory 2048 --tags 'alt_server' --startup order=4,up=15,down=60 $(netifs 'SW-BR<=>SRV-BR') "${vm_opts[@]}"
	qm importdisk $vmid Alt-Server.qcow2 $STORAGE --format qcow2 | tail -n -3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --scsi1 $STORAGE:1,iothread=1 --scsi2 $STORAGE:1,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: SRV-BR is done!!!"

	((vmid++))
	qm create $vmid --name "CLI-BR" --cores 2 --memory 2048 --tags 'alt_workstation' --startup order=5,up=20,down=30 $(netifs 'SW-BR<=>CLI-BR') "${vm_opts[@]}"
	qm importdisk $vmid Alt-Workstation.qcow2 $STORAGE --format qcow2 | tail -n -3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: CLI-BR is done!!!"

	pvesh set /pools/$stand_name$stand -vms "`seq -s, $id 1 $vmid`"

	echo "ALL DONE $stand_name$stand!!!"

}

#rm -f ISP.qcow2 Alt-Server.qcow2 Alt-Workstation.qcow2
