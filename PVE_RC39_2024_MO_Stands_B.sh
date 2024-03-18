#!/bin/bash
ex() { echo; exit; }
trap ex INT

# exec:		sh='PVE_RC39_2024_MO_Stands_B.sh';curl -sOLH 'Cache-Control: no-cache' "https://raw.githubusercontent.com/PavelAF/REGCHAMP2024/111/$sh"&&chmod +x $sh&&./$sh;rm -f $sh

# бридж для подключения ВМ (address DHCP, с доступом в интернет через NAT):
INET_BRIDGE='vmbr0'

comp_name='Competitor'
stand_name='RCMO39-2024_stand_B-'
take_snapshot=true
mk_tmpfs_imgdir='/root/tmpfs_IMGDIR'

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

until read -p $'\nДействие: 1 - Развертывание стенда, 2 - Управление развертыванием: ' switch; [[ "$switch" =~ ^[1-2]$ ]]; do true;done
if [[ "$switch" == 2 ]]; then
	until read -p $'Стартовый номер участника: ' switch; [[ "$switch" =~ ^[0-9]*$ ]] && [[ $switch -le 100 ]]; do true;done
	until read -p $'Конечный номер участника: ' switch2; [[ "$switch2" =~ ^[0-9]*$ ]] && [[ $switch2 -le 100 && $switch2 -ge $switch ]]; do true;done
	until read -p $'Действие: 1 - активировать пользователей, 2 - отключить аккаунты, 3 - установить пароли, 4 - удалить пользователей, \n\t5 - (Пере)установить права участиков на ВМ/пулы, 6 - восстановить ВМ по снапшоту Start, 7 - Удалить созданные стенды/бриджи/пользователей, 8 - Добавить SSL-аутентификацию\nВыберите действие: ' switch3; [[ "$switch3" =~ ^[1-8]$ ]]; do true;done

	for ((stand=$switch; stand<=$switch2; stand++))
	{
		[ $switch3 == 1 ] && pveum user modify $comp_name$stand@pve --enable 1
		[ $switch3 == 2 ] && pveum user modify $comp_name$stand@pve --enable 0
		[ $switch3 == 3 ] && \
		(
			psswd=`tr -dc 'a-z\_\-1-9' </dev/urandom | head -c 5`
			pvesh set /access/password --userid $comp_name$stand@pve --password $psswd
			echo $'\n'"$comp_name$stand : $psswd"
		)
		[ $switch3 == 4 ] && pveum user delete $comp_name$stand@pve
  		[ $switch3 == 5 ] && \
		{
  			[ ! -z ${switch4+x} ] || \
     			{
				read -n 1 -p $'Занулить все права, пользователей, пулы, реалмсы? [y|д|1]: ' switch4; echo
				[[ "$switch4" =~ [yд1] ]] && > /etc/pve/user.cfg && pvesh get /access/users >/dev/null;
   			}
  			[ ! -z ${start_num+x} ] || until read -p $'Ввведите начальный идентификатор ВМ: ' start_num; [[ "$start_num" =~ ^[1-9][0-9]*$ ]] && [[ $start_num -lt 3900 && $start_num -ge 100 ]]; do true;done
  			pveum role add Competitor 2> /dev/null
			pveum role modify Competitor -privs 'Pool.Audit VM.Audit VM.Console VM.PowerMgmt VM.Snapshot.Rollback VM.Config.Network'
			pveum role add Competitor_ISP 2> /dev/null
			pveum role modify Competitor_ISP -privs 'VM.Audit VM.Console VM.PowerMgmt VM.Snapshot.Rollback'

			pveum user add $comp_name$stand@pve 2> /dev/null
   			pveum user modify $comp_name$stand@pve --comment 'Учетная запись участника соревнований'
			pveum pool add $stand_name$stand 2> /dev/null
   			pveum pool modify $stand_name$stand --comment 'Стенд участника регионального этапа Чемпионата «Профессионалы» компетенции Сетевое и системное администрирование, модуль Б'
			pveum acl modify /pool/$stand_name$stand --users $comp_name$stand@pve --roles PVEAuditor --propagate 0
		
			id=$((start_num+stand*100))
			for i in "${!Networking[@]}"; do pveum acl modify /sdn/zones/localnetwork/vmbr$((id+i+1)) --users $comp_name$stand@pve --roles PVEAuditor; done
   			
			for ((i=1; i<=9; i++)) { pveum acl modify /vms/$((id+i)) --roles Competitor --users $comp_name$stand@pve; }
 			pveum acl modify /vms/$id --roles Competitor_ISP --users $comp_name$stand@pve;

     			pvesh set /pools/$stand_name$stand -vms "`seq -s, $id 1 $((id+9))`"
		}
  		[ $switch3 == 6 ] && \
		{
			[ ! -z ${start_num+x} ] || until read -p $'Ввведите начальный идентификатор ВМ: ' start_num; [[ "$start_num" =~ ^[1-9][0-9]*$ ]] && [[ $start_num -lt 3900 && $start_num -ge 100 ]]; do true;done
			for ((i=$start_num; i<=$start_num+9; i++)) { qm rollback $((start_num+stand*100+i)) Start; }
		}
  		[ $switch3 == 7 ] && \
		{
			[ ! -z ${start_num+x} ] || until read -p $'Ввведите начальный идентификатор ВМ: ' start_num; [[ "$start_num" =~ ^[1-9][0-9]*$ ]] && [[ $start_num -lt 3900 && $start_num -ge 100 ]]; do true;done
			id=$((start_num+stand*100))
   			for ((i=0; i<=9; i++)) { qm destroy $((id+i)) --destroy-unreferenced-disks 1 --purge 1 --skiplock 1; }
   			pvesh get "/nodes/`hostname`/network" --type bridge | grep '│' | awk -F'│' -v id=$id -v host="`hostname`" -v x="$(printf '%s\n' "${Networking[@]}")" 'BEGIN{split(x, a,"\n"); for(i in a) dict[a[i]]=i}NR==1{s[1]="comments";s[2]="iface"; for(i=1;i<=NF;i++){ if ($i~s[1]) n1=i;if ($i~s[2]) n2=i } }NR>1{n=$n1; gsub(/(^[ \t\r\n]+)|([ \t\r\n]+$)/, "", n);i=$n2;gsub(/(^[ \t\r\n]+)|([ \t\r\n]+$)/, "", i)}n in dict && match(i, /^vmbr[0-9]+$/) && match(i, /[0-9]+/) { v=substr( i, RSTART, RLENGTH ); if (v>=id && v<id+100) system("pvesh delete /nodes/"host"/network/"i) }'
			pvesh set "/nodes/`hostname`/network"
   			pveum pool delete $stand_name$stand
			pveum user delete $comp_name$stand@pve 
		}
    		[ $switch3 == 8 ] && \
		(
			apt install nginx-light -y
			ip_i=`ip route get 1 |& grep -Po '\ src\ \K[0-9\.]+'`
			ip6_i=`ip route get 1::1 |& grep -Po '\ src\ \K[0-9a-f\:]+'`
			listen=`echo $ip_i$'\n'$ip6_i | awk 'BEGIN{t="    listen %s:%s ssl;\n"}NF{if($0~/:/)$0="["$0"]";printf t t,$0,443,$0,8006;}'`

			rm -f /etc/nginx/sites-enabled/default
			cat <<CONF > /etc/nginx/conf.d/pve-proxy.conf
server {
${listen}
    server_name _;
    ssl_certificate /etc/pve/local/pve-nginx-ssl.pem;
    ssl_certificate_key /etc/pve/local/pve-nginx-ssl.key;
    ssl_client_certificate /etc/pve/pve-root-ca.pem;
    ssl_verify_client on;
    keepalive_timeout 70;
	
    proxy_redirect off;
    location / {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade"; 
        proxy_pass https://localhost:8006;
        proxy_buffering off;
        client_max_body_size 0;
        proxy_connect_timeout  3600s;
        proxy_read_timeout  3600s;
        proxy_send_timeout  3600s;
        send_timeout  3600s;
    }
}
CONF
			SYSTEMD_EDITOR=tee systemctl edit nginx.service <<EOF
[Unit]
Requires=pve-cluster.service
After=pve-cluster.service
EOF
			systemctl enable nginx.service
			
			echo 'LISTEN_IP="127.0.0.1"' > /etc/default/pveproxy

			ip_e=`dig @resolver1.opendns.com myip.opendns.com +short -4 2>/dev/null | grep -v \;`
			ip6_e=`dig @resolver1.ipv6-sandbox.opendns.com myip.opendns.com +short -6 aaaa 2>/dev/null | grep -v \;`
			
			ipNames=$'127.0.0.1\n::1\n'$ip_e$'\n'$ip6_e
			
			until read -p $'Введите DNS-имя сервера (или оставьте пустым): ' dns_name; echo "$dns_name" | grep -Poqi '(^([а-я\w\d]{1,64}(|-+[а-я\w\d]+)(\.|$)){2,}$)|^$'; do true;done
			
			altNames=`echo "$ipNames" | awk 'BEGIN{n=1}NF{print "IP."n"="$0;n++}'; echo $'localhost\n'$(hostname --all-fqdns)$'\n'${dns_name,,} | awk 'BEGIN{n=1}NF{print "DNS."n"="$0;n++}'`
			
			rm -f /etc/pve/local/pve-nginx-ssl.*
			openssl req -subj "/CN=`hostname --fqdn`" -new -nodes -newkey rsa:2048 -out pve-ssl.csr -keyout /etc/pve/local/pve-nginx-ssl.key
			
			openssl x509 -req -days 3650 -in pve-ssl.csr -CA /etc/pve/pve-root-ca.pem -CAkey /etc/pve/priv/pve-root-ca.key -CAserial /etc/pve/priv/pve-root-ca.srl -out /etc/pve/local/pve-nginx-ssl.pem -extensions EXT \
			-extfile <(echo $'\n[EXT]\nnsComment="PVE server certificate for Prof RCMO39-2024"\nbasicConstraints=CA:FALSE\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid,issuer:always\nextendedKeyUsage=serverAuth\nkeyUsage=critical, digitalSignature, keyEncipherment\nnsCertType = server\nsubjectAltName = @alt_names\n[alt_names]'; echo "$altNames")
			rm -f pve-ssl.csr
   			
			openssl req -subj /CN=RCMO39-SSL-Auth -new -nodes -newkey rsa:2048 -out pve-ssl-auth.csr -keyout /etc/pve/priv/pve-ssl-auth.key
   
			openssl x509 -req -days 3650 -in pve-ssl-auth.csr -CA /etc/pve/pve-root-ca.pem -CAkey /etc/pve/priv/pve-root-ca.key -CAserial /etc/pve/priv/pve-root-ca.srl -out /etc/pve/priv/pve-ssl-auth.pem -extensions EXT \
			-extfile <(echo $'\n[EXT]\nnsComment="Competition participant authentication Prof RCMO39-2024"\nbasicConstraints=CA:FALSE\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid,issuer:always\nextendedKeyUsage=clientAuth\nkeyUsage=digitalSignature')
			rm -f pve-ssl-auth.csr
			
			openssl pkcs12 -name 'Сертификат участника соревнований Prof RCMO39-2024' -caname 'Центр сертификации соревнований Prof RCMO39-2024' -export -in /etc/pve/priv/pve-ssl-auth.pem -inkey /etc/pve/priv/pve-ssl-auth.key -certfile /etc/pve/pve-root-ca.pem -out RCMO39-ssl-auth.p12
			

			clear; cat RCMO39-ssl-auth.p12 | base64
			echo $'\n\nСохраните строку выше как файл encode.txt, откройте cmd и введите команду:\n\ncertutil -f -decode encode.txt RCMO39-ssl-auth.p12'
			echo $'\nЗатем разместите файл RCMO39-ssl-auth.p12 на машинах участников и установите сертификаты для текущего пользователя'

			read -n1 -s -p $'Нажмите любую клавишу, чтобы завершить выполнение скрипта\n'
			systemctl restart pveproxy.service spiceproxy.service nginx.service
   			exit
		)
	}
	echo ; exit
fi

echo $'\nМинимально требуемое место в хранилище (только для развертывания): 50 ГБ\nРекомендуется: 100 ГБ\nСписок доступных хранилищ:'
sl=`pvesm status --enabled 1 --content images  | awk -F' ' 'NR>1{print $1" "$6" "$2}END{if(NR==1){exit 3}}' || (echo 'Ошибка: подходящих хранилищ не найдено'; exit 3)`
echo "$sl"|awk -F' ' 'BEGIN{split("К|М|Г|Т",x,"|")}{for(i=1;$2>=1024&&i<length(x);i++)$2/=1024;print NR"\t"$1"\t"$3"\t"int($2)" "x[i]"Б"; }'|column -t -s$'\t' -N'Номер,Имя хранилища,Тип хранилища,Свободное место' -o$'\t' -R1
count=`echo "$sl" | wc -l`;until read -p $'Чтобы прервать установку, нажмите Ctrl-C\nВыберите номер хранилища: ' switch; [[ "$switch" =~ ^[1-9][0-9]*$ ]] && [[ $switch -le $count ]]; do true;done
STORAGE=`echo "$sl" | awk -F' ' -v nr=$switch 'NR==nr{print $1}'`

until read -p $'Ввведите начальный идентификатор ВМ и bridge: ' switch; [[ "$switch" =~ ^[1-9][0-9]*$ ]] && [[ $switch -lt 3900 && $switch -ge 100 ]]; do true;done
start_num=$switch
until read -p $'Ввведите имя бриджа для виртуальной машины ISP\nvmbr-интерфейс с выходом в интернет+DHCP (default='$INET_BRIDGE'): ' switch; [[ "$switch" =~ ^[a-z0-9\n]*$|^$ ]]; do true;done
INET_BRIDGE=${switch:=$INET_BRIDGE}

until read -p $'Ввведите стартовый номер стенда: ' switch; [[ "$switch" =~ ^[0-9]*$ ]] && [[ $switch -le 100 ]]; do true;done
until read -p $'Ввведите конечный номер стенда: ' switch2; [[ "$switch2" =~ ^[0-9]*$ ]] && [[ $switch2 -le 100 && $switch2 -ge $switch ]]; do true;done

pveum role add Competitor 2> /dev/null
pveum role modify Competitor -privs 'Pool.Audit VM.Audit VM.Console VM.PowerMgmt VM.Snapshot.Rollback VM.Config.Network'
pveum role add Competitor_ISP 2> /dev/null
pveum role modify Competitor_ISP -privs 'VM.Audit VM.Console VM.PowerMgmt VM.Snapshot.Rollback'

pveum realm modify pam --comment 'System'
pveum realm modify pve --comment 'Аутентификация участника соревнований' --default 1
pvesh set /cluster/options --tag-style 'color-map=alt_server:ffcc14;alt_workstation:ac58e4,ordering=config,shape=none'

awk '/MemFree/ {if($2<12582912) {print "Ошибка: Недостаточо свободной оперативной памяти!\nДля развертывания стенда необходимо как минимум 12 ГБ свободоной ОЗУ";exit 1} }' /proc/meminfo || exit
mkdir -p $mk_tmpfs_imgdir && ((mountpoint -q $mk_tmpfs_imgdir || mount -t tmpfs tmpfs $mk_tmpfs_imgdir -o size=8G) || ( echo 'Ошибка при создании временного хранилища tmpfs' && exit 1 ))
ya_url() { echo $(curl --silent -G --data-urlencode "public_key=$1" --data-urlencode "path=/$2" 'https://cloud-api.yandex.net/v1/disk/public/resources/download' | grep -Po '"href":"\K[^"]+'); }
[ "$(file -b --mime-type $mk_tmpfs_imgdir/ISP.qcow2)" == application/x-qemu-disk ] || curl -L $(ya_url https://disk.yandex.ru/d/xPK-Kt3E7Slmbg ISP.qcow2) -o $mk_tmpfs_imgdir/ISP.qcow2
[ "$(file -b --mime-type $mk_tmpfs_imgdir/Alt-Server.qcow2)" == application/x-qemu-disk ] || curl -L $(ya_url https://disk.yandex.ru/d/xPK-Kt3E7Slmbg Alt-Server.qcow2) -o $mk_tmpfs_imgdir/Alt-Server.qcow2
[ "$(file -b --mime-type $mk_tmpfs_imgdir/Alt-Workstation.qcow2)" == application/x-qemu-disk ] || curl -L $(ya_url https://disk.yandex.ru/d/xPK-Kt3E7Slmbg Alt-Workstation.qcow2) -o $mk_tmpfs_imgdir/Alt-Workstation.qcow2

netifs() { printf '%s\n' "$@" | awk -v x="$(printf '%s\n' "${Networking[@]}")" -v id=$id 'BEGIN{n=0;split(x, a); for (i in a) dict[a[i]]="vmbr"i+id} $0 in dict || $0~/^vmbr[0-9]+/{br=(dict[$1])? dict[$1] : $1;printf " --net" n " virtio,bridge=" br;n++ }'; }

for ((stand=$switch; stand<=$switch2; stand++))
{
	pveum user add $comp_name$stand@pve --comment 'Учетная запись участника соревнований'
	pveum pool add $stand_name$stand
	pveum acl modify /pool/$stand_name$stand --users $comp_name$stand@pve --roles PVEAuditor --propagate 0

	id=$((start_num+stand*100))
	for i in "${!Networking[@]}"
	do
		iface=vmbr$((id+i+1)); desc=${Networking[$i]}
		pvesh create "/nodes/`hostname`/network" --iface $iface --type bridge --autostart 1 --comments $desc \
  			|| read -n 1 -p "Интерфейс $iface ($desc) уже существует! Стенд уже был развернут?"$'\nНажмите Ctrl-C для остановки или любую клавишу для продолжения'
		pveum acl modify /sdn/zones/localnetwork/$iface --users $comp_name$stand@pve --roles PVEAuditor
	done
 	pvesh set "/nodes/`hostname`/network"

 	vmid=$id
	qm create $vmid --name "ISP" --cores 1 --memory 1024 --startup order=1,up=10,down=30 $(netifs $INET_BRIDGE,firewall=1 'ISP<=>RTR-HQ' 'ISP<=>RTR-BR') "${vm_opts[@]}" || read -n 1 -p "Виртуальная машина $vmid (ISP) уже существует! Стенд уже был развернут?"$'\nНажмите Ctrl-C для остановки или любую клавишу для продолжения'
	qm importdisk $vmid $mk_tmpfs_imgdir/ISP.qcow2 $STORAGE --format qcow2 | tail -n3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
 	pvesh set "/nodes/`hostname`/qemu/$vmid/firewall/options" --enable 1 --dhcp 1
	echo "$stand_name$stand: ISP is done!!!"

	((vmid++))
	qm create $vmid --name "RTR-HQ" --cores 2 --memory 1536 --tags 'alt_server' --startup order=2,up=20,down=30 $(netifs 'ISP<=>RTR-HQ' 'RTR-HQ<=>SW-HQ') "${vm_opts[@]}"
	qm importdisk $vmid $mk_tmpfs_imgdir/Alt-Server.qcow2 $STORAGE --format qcow2 | tail -n3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: RTR-HQ is done!!!"

	((vmid++))
	qm create $vmid --name "SW-HQ" --cores 1 --memory 1536 --tags 'alt_server' --startup order=3,up=15,down=30 $(netifs 'RTR-HQ<=>SW-HQ' 'SW-HQ<=>SRV-HQ' 'SW-HQ<=>CLI-HQ' 'SW-HQ<=>CICD-HQ') "${vm_opts[@]}"
	qm importdisk $vmid $mk_tmpfs_imgdir/Alt-Server.qcow2 $STORAGE --format qcow2 | tail -n3
 	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: SW-HQ is done!!!"

	((vmid++))
	qm create $vmid --name "SRV-HQ" --cores 2 --memory 4096 --tags 'alt_server' --startup order=4,up=15,down=60 $(netifs 'SW-HQ<=>SRV-HQ') "${vm_opts[@]}"
	qm importdisk $vmid $mk_tmpfs_imgdir/Alt-Server.qcow2 $STORAGE --format qcow2 | tail -n3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --scsi1 $STORAGE:1,iothread=1 --scsi2 $STORAGE:1,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: SRV-HQ is done!!!"

	((vmid++))
	qm create $vmid --name "CLI-HQ" --cores 2 --memory 2048 --tags 'alt_workstation' --startup order=5,up=20,down=30 $(netifs 'SW-HQ<=>CLI-HQ') "${vm_opts[@]}"
	qm importdisk $vmid $mk_tmpfs_imgdir/Alt-Workstation.qcow2 $STORAGE --format qcow2 | tail -n3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: CLI-HQ is done!!!"

	((vmid++))
	qm create $vmid --name "CICD-HQ" --cores 2 --memory 2048 --tags 'alt_workstation' --startup order=5,up=20,down=30 $(netifs 'SW-HQ<=>CICD-HQ') "${vm_opts[@]}"
	qm importdisk $vmid $mk_tmpfs_imgdir/Alt-Workstation.qcow2 $STORAGE --format qcow2 | tail -n3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: CICD-HQ is done!!!"
 
	((vmid++))
	qm create $vmid --name "RTR-BR" --cores 2 --memory 1536 --tags 'alt_server' --startup order=2,up=20,down=30 $(netifs 'ISP<=>RTR-BR' 'RTR-BR<=>SW-BR') "${vm_opts[@]}"
	qm importdisk $vmid $mk_tmpfs_imgdir/Alt-Server.qcow2 $STORAGE --format qcow2 | tail -n3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
 	
	echo "$stand_name$stand: RTR-BR is done!!!"

	((vmid++))
	qm create $vmid --name "SW-BR" --cores 1 --memory 1536 --tags 'alt_server' --startup order=3,up=15,down=30 $(netifs 'RTR-BR<=>SW-BR' 'SW-BR<=>SRV-BR' 'SW-BR<=>CLI-BR') "${vm_opts[@]}"
	qm importdisk $vmid $mk_tmpfs_imgdir/Alt-Server.qcow2 $STORAGE --format qcow2 | tail -n3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: SW-BR is done!!!"

	((vmid++))
	qm create $vmid --name "SRV-BR" --cores 2 --memory 2048 --tags 'alt_server' --startup order=4,up=15,down=60 $(netifs 'SW-BR<=>SRV-BR') "${vm_opts[@]}"
	qm importdisk $vmid $mk_tmpfs_imgdir/Alt-Server.qcow2 $STORAGE --format qcow2 | tail -n3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --scsi1 $STORAGE:1,iothread=1 --scsi2 $STORAGE:1,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: SRV-BR is done!!!"

	((vmid++))
	qm create $vmid --name "CLI-BR" --cores 2 --memory 2048 --tags 'alt_workstation' --startup order=5,up=20,down=30 $(netifs 'SW-BR<=>CLI-BR') "${vm_opts[@]}"
	qm importdisk $vmid $mk_tmpfs_imgdir/Alt-Workstation.qcow2 $STORAGE --format qcow2 | tail -n3
	qm set $vmid --scsi0 $STORAGE:vm-$vmid-disk-0,iothread=1 --boot order=scsi0
	echo "$stand_name$stand: CLI-BR is done!!!"

	pvesh set /pools/$stand_name$stand -vms "`seq -s, $id 1 $vmid`"
	for ((i=$id; i<=$vmid; i++))
 	{
  		$take_snapshot && qm snapshot $i Start --description 'Исходное состояние ВМ' | tail -n2
  		pveum acl modify /vms/$i --roles Competitor --users $comp_name$stand@pve;
    	}
 	pveum acl modify /vms/$id --roles Competitor_ISP --users $comp_name$stand@pve;
  
	echo "ALL DONE $stand_name$stand!!!"

}

read -n 1 -p $'Удалить временный раздел со скачанными образами ВМ ('$mk_tmpfs_imgdir')? [y|д|1]: ' switch; echo
[[ "$switch" =~ [yд1] ]] && ( umount -q $mk_tmpfs_imgdir; rmdir $mk_tmpfs_imgdir )
