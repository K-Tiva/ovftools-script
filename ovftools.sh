#!/bin/sh

# 仮想マシンの電源断
shutdown_vm() {
  local VMID=
  local FLAG=

  # vSphere上の仮想マシンのVMIDを変数に代入
  VMID=$( \
    sshpass -p password ssh root@${1} \
    "vim-cmd vmsvc/getallvms | egrep '^[0-9]+' | awk '{ print "\$1" }'" \
  )

  # VMIDの数だけループ
  for id in ${VMID}
  do
    # 仮想マシンの電源があがっているかチェック(FLAGがonだと電源があげっている、offだと電源断状態)
    FLAG=$( \
      sshpass -p password ssh root@${1} \
      "vim-cmd vmsvc/power.getstate ${id} | awk 'NR>1 { print "\$2" }'" \
    )
    # 電源があがっていれば電源断
    if [ ${FLAG} = "on" ];
    then
      sshpass -p password ssh root@${1} "vim-cmd vmsvc/power.shutdown ${id}"
      echo "${id} is shutdown"
    fi
  done
}

# 仮想マシンを削除する
delete_vm() {
  local VMID=
  local FLAG=

  # vSphere上の仮想マシンのVMIDを変数に代入
  VMID=$( \
    sshpass -p password ssh root@${1} \
    "vim-cmd vmsvc/getallvms | egrep '^[0-9]+' | awk '{ print "\$1" }'" \
  )

  # VMIDの数だけループ
  for id in ${VMID}
  do
    # 仮想マシンの電源断するまでループ
    while :
    do
      # 仮想マシンの電源があがっているかチェック(FLAGがonだと電源があげっている、offだと電源断状態)
      FLAG=$( \
        sshpass -p password ssh root@${1} \
        "vim-cmd vmsvc/power.getstate ${id} | awk 'NR>1 { print "\$2" }'" \
      )

      # 電源が断していれば仮想マシンを削除、ループをぬける
      if [ ${FLAG} = "off" ];
      then
        sshpass -p password ssh root@${1} "vim-cmd vmsvc/destroy ${id}"
        echo "${id} is destroy"
        break
      fi

      sleep 5
    done
  done
}

# 自動起動を設定
autostart_vm() {
  local VMID=
  local ORDER=1

  # vSphere上の仮想マシンのVMIDを変数に代入
  VMID=$( \
    sshpass -p password ssh root@${1} \
    "vim-cmd vmsvc/getallvms | egrep '^[0-9]+' | awk '{ print "\$1" }'" \
  )

  # VMIDの数だけループ
  for id in ${VMID}
  do
    sshpass -p password ssh root@${1} \
    "vim-cmd hostsvc/autostartmanager/update_autostartentry ${id} PowerOn 120 ${ORDER} systemDefault systemDefault systemDefault"
    ORDER=$((${ORDER}+1))
  done
}

# OVFファイルを持つサーバを指定
ovf_sv=192.168.1.100

# 変数チェック
if [ $# -ne 1 ];
then
  echo "ovftool.sh <csv file>"
fi

# 仮想マシンの電源断
for i in $(cat ${1} | awk -F , '{ print $4 }' | awk '!a[$0]++')
do
  shutdown_vm ${i}
done

# 仮想マシンの削除
for i in $(cat ${1} | awk -F , '{ print $4 }' | awk '!a[$0]++')
do
  delete_vm ${i}
done

# 仮想マシンのデプロイ
for line in $(cat ${1} |grep -v ^#)
do
  # 仮想マシン名
  name=$(echo ${line} | cut -d ',' -f 1)
  # ネットワーク名
  network=$(echo ${line} | cut -d ',' -f 2)
  # ovfファイル名
  ovf=$(echo ${line} | cut -d ',' -f 3)
  # DCx5またはDCx6のIPアドレス
  dc=$(echo ${line} | cut -d ',' -f 4)

  # ovftoolによるデプロイ
  ovftool --overwrite -dm=thin -ds=datastore1 --name=${name} --net:TCN=TCN --net:${network}=${network} --powerOn http://${ovf_sv}/${ovf} vi://root:password@${dc}
done

# 仮想マシンの自動起動設定
for i in $(cat ${1} | awk -F , '{ print $4 }' | awk '!a[$0]++')
do
  autostart_vm ${i}
done
