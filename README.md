# REGCHAMP2024
1.  Открываем Proxmox, выбираем нужную Node и переходим в раздел
    “Shell”.

2. Для того, чтобы развернуть стенд, скачайте исполняемый скрипт и запустите:  
```
sh='Proxmox_RC39_2024_stand.sh';curl -OL "https://raw.githubusercontent.com/PavelAF/REGCHAMP2024/111/$sh" && chmod +x $sh && ./$sh; rm -f $sh
```
При запуске скрипта выведется список доступных хранилищ и свободное место на них

3. Указываем имя хранилища, которое будем использовать (по умолчанию - первое в списке)

<img src="screenshots/1.png" style="width:3.57292in;height:3.22917in" />


> После этого ждем.

4.  Стенд развернут!
