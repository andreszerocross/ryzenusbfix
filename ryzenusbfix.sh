#!/bin/bash
# ryzenusbfix
# XLNC
# 20/08/18

if ! [ "$(id -u)" = 0 ]; then
	sudo "$0" "$1"
	exit 0
fi

function quit(){
echo -e "\n[EXITING] ..."
sleep 5
rm -rf ~/Desktop/ryzenusbfix.sh /tmp/XLNC
exit 1
}

stty -echoctl
trap 'quit' SIGINT SIGTERM SIGHUP

#Save ass check for non-ryzen systems
sysctl -n machdep.cpu.brand_string | grep Ryzen &>/dev/null
if [ $? != 0 ]; then
	echo -e "\n[ERROR] Can't proceed, This fix only works for Ryzen CPU's."
	quit
fi

#START
printf '\e[9;1t' && clear
STD='\033[0;0;39m'
ITL='\x1b[3m'
echo
echo -e "${ITL} /** ${STD}"
echo -e "${ITL}  * - Name: ryzenusbfix ${STD}"
echo -e "${ITL}  * - Info: Script to fix USB ports on ryzen systems ${STD}"
echo -e "${ITL}  * - Auth: XLNC ${STD}"
echo -e "${ITL}  * - Date: 15/08/2018 ${STD}"
echo -e "${ITL}  */ ${STD}"
echo

echo -e "\n Starting ..." && sleep 3

if [ -e /tmp/XLNC ]; then
	rm -rf "/tmp/XLNC" && mkdir /tmp/XLNC
else
	mkdir /tmp/XLNC
fi

echo -e "\n\n[RUNNING] Getting files \n[ALERT] Might need internet connection if required files not present on system.\n"
FILES=(
	patchmatic
	iasl
	k2p
	patch.txt
)
DIR=${0%/*}
for FILE in "${FILES[@]}"; do
	if [ -e "$DIR"/Files/"$FILE" ]; then
		cp -rf "$DIR"/Files/"$FILE" /tmp/XLNC/"$FILE"
	else
		curl -s -o /tmp/XLNC/"$FILE" https://raw.githubusercontent.com/XLNCs/ryzenusbfix/master/Files/"$FILE"
		if ! [ $? = 0 ]; then
			echo -e "\n[ERROR] Cant Download "$FILE""
			quit
		fi
	fi
done

echo -e "\n[RUNNING] Mounting EFI."
vol="/"
DRIVE="$(diskutil info $vol | grep 'Part of Whole' | cut -d : -f 2 | sed 's/^ *//g' | sed 's/ *$//g')"
diskutil mount /dev/"$DRIVE"s1 >/dev/null 2>&1

#PRE-RUN CHECK
if ! [ -e /Volumes/EFI/ ]; then
	echo -e "\n[ERROR] EFI not mounted or not present"
	echo -e "\n[ALERT] Mount your EFI partition manually using Terminal and try again."
	quit
fi
if ! [ -e /Volumes/EFI/EFI/CLOVER ]; then
	echo -e "\n[ERROR] Clover not installed."
	quit
fi
if [ -e /Volumes/EFI/EFI/CLOVER/ACPI/patched/DSDT.aml ]; then
	echo -e "\n[RUNNING] Existing DSDT.aml detected in EFI \n[DELETING] ..."
	rm -rf /Volumes/EFI/EFI/CLOVER/ACPI/patched/DSDT.aml
	echo -e "\n[ALERT] Now reboot the system and re-run the ryzenusbfix"
	quit
fi
for folders in /Volumes/EFI/EFI/CLOVER/kexts/*; do
	if [ -e $folders/DummyUSBXHCIPCI.kext ] || [ -e $folders/DummyUSBEHCIPCI.kext ] || [ -e $folders/GenericUSBXHCI.kext ]; then
		echo -e "\n[RUNNING] Detected old USB files in EFI. \n[DELETING] ..."
		rm -rf $folders/DummyUSB*
		rm -rf $folders/GenericUSB*
	fi
done
if [ -e /System/Library/Extensions/DummyUSBXHCIPCI.kext ] || [ -e /System/Library/Extensions/DummyUSBEHCIPCI.kext ] || [ -e /System/Library/Extensions/GenericUSBXHCI.kext ] || [ -e /Library/Extensions/DummyUSBXHCIPCI.kext ] || [ -e /Library/Extensions/DummyUSBEHCIPCI.kext ] || [ -e /Library/Extensions/GenericUSBXHCI.kext ]; then
	echo -e "\n[RUNNING] Detected old USB files in S/L/E or L/E. \n[DELETING] ..."
	rm -rf /System/Library/Extensions/DummyUSB* /Library/Extensions/DummyUSB*
	rm -rf /System/Library/Extensions/GenericUSB* /Library/Extensions/GenericUSB*
	echo -e "\n[RUNNING] Rebuilding caches."
	chown -R 0:0 /System/Library/Extensions/ /Library/Extensions/
	chmod -R 755 /System/Library/Extensions/ /Library/Extensions/
	touch /System/Library/Extensions/ /Library/Extensions/ /System/Library/Kernels/kern*
	rm -rf /System/Library/PrelinkedKernels/pre*
	killall kextcache
	# kextcache -i / && kextcache -u /
	kextcache -Boot -U /
fi

chmod +x /tmp/XLNC/patchmatic /tmp/XLNC/iasl /tmp/XLNC/k2p
PATCH="/tmp/XLNC/patchmatic"
CONV="/tmp/XLNC/iasl"
KEXTTOPATCH="/tmp/XLNC/k2p"

echo -e "\n\n[RUNNING] Extracting DSDT Table."
$PATCH -extract /tmp/XLNC/
function method1() {
	echo -e "\n[RUNNING] Decompiling DSDT.\n"
	$CONV -e /tmp/XLNC/SSDT*.aml -d /tmp/XLNC/DSDT.aml
	if ! [ -e /tmp/XLNC/DSDT.dsl ]; then
		echo -e "\n[ERROR] DSDT could not be decompiled using method #1. \n[RUNNING] Trying method #2."
		RUN=1
	else
		echo -e "\n[ALERT] DSDT decompiled successfully."
		echo -e "\n[RUNNING] Patching DSDT Table.\n"
		$PATCH /tmp/XLNC/DSDT.dsl /tmp/XLNC/patch.txt /tmp/XLNC/PATCHED.dsl
		if ! [ -e /tmp/XLNC/PATCHED.dsl ]; then
			echo -e "\n[ERROR] Patched DSDT could not be generated using method #1. \n[RUNNING] Trying method #2."
			RUN=1
		else
			echo -e "\n[ALERT] Patched DSDT generated successfully.\n"
			$CONV -ve /tmp/XLNC/PATCHED.dsl
			if ! [ -e /tmp/XLNC/PATCHED.aml ]; then
				echo -e "\n[ERROR] Patched DSDT could not be compiled using method #1. \n[RUNNING] Trying method #2."
				RUN=1
			fi
		fi
	fi

}

function Method2() {
	rm -rf /tmp/XLNC/DSDT.dsl /tmp/XLNC/PATCHED.dsl
	echo -e "\n[RUNNING] Decompiling DSDT using method #2.\n"
	$CONV /tmp/XLNC/DSDT.aml
	if ! [ -e /tmp/XLNC/DSDT.dsl ]; then
		echo -e "\n[ERROR] DSDT could not be decompiled using method #2."
		quit
	else
		echo -e "\n[ALERT] DSDT decompiled successfully using method #2."
		echo -e "\n[RUNNING] Patching DSDT Table\n"
		$PATCH /tmp/XLNC/DSDT.dsl /tmp/XLNC/patch.txt /tmp/XLNC/PATCHED.dsl
		if ! [ -e /tmp/XLNC/PATCHED.dsl ]; then
			echo -e "\n[RUNNING] Patched DSDT could not be generated using method #2."
			quit
		else
			echo -e "\n[ALERT] Patched DSDT generated successfully using method #2.\n"
			$CONV -ve /tmp/XLNC/PATCHED.dsl
			if ! [ -e /tmp/XLNC/PATCHED.aml ]; then
				echo -e "\n[ERROR] Patched DSDT could not be compiled using method #2."
				quit
			fi
		fi
	fi
}

method1
if [ "$RUN" = "1" ]; then
	Method2
fi

cp -Rf /tmp/XLNC/PATCHED.aml /Volumes/EFI/EFI/CLOVER/ACPI/patched/DSDT.aml

if ! [ -e /Volumes/EFI/EFI/CLOVER/xlnc_backup_config.plist ]; then
	cp -Rf /Volumes/EFI/EFI/CLOVER/config.plist /Volumes/EFI/EFI/CLOVER/xlnc_backup_config.plist
	echo -e "\n[ALERT] config.plist backup created successfully"
fi

if [ -e /Volumes/EFI/EFI/CLOVER/config.plist ]; then
	config="/Volumes/EFI/EFI/CLOVER/config.plist"
	echo -e "\n[RUNNING] Patching config.plist"
	if [[ $(sw_vers -productVersion) =~ (10.13|10.13.0|10.13.1|10.13.2|10.13.3)$ ]]; then
	        $KEXTTOPATCH $config Has -find "21F281FA 000002" -replace "21F281FA 000011" -name com.apple.driver.usb.AppleUSBXHCI || $KEXTTOPATCH $config add -find "21F281FA 000002" -replace "21F281FA 000011" -name com.apple.driver.usb.AppleUSBXHCI
	        $KEXTTOPATCH $config Has -find "D1000000 83F901" -replace "D1000000 83F910" -name com.apple.driver.usb.AppleUSBXHCI || $KEXTTOPATCH $config add -find "D1000000 83F901" -replace "D1000000 83F910" -name com.apple.driver.usb.AppleUSBXHCI
	        $KEXTTOPATCH $config Has -find "83BD7CFF FFFF0F" -replace "83BD7CFF FFFF1F" -name com.apple.driver.usb.AppleUSBXHCI || $KEXTTOPATCH $config add -find "83BD7CFF FFFF0F" -replace "83BD7CFF FFFF1F" -name com.apple.driver.usb.AppleUSBXHCI
	elif [[ $(sw_vers -productVersion) =~ (10.13.4|10.13.5|10.13.6)$ ]]; then
	        $KEXTTOPATCH $config Has -find "C8000000 83FB02" -replace "C8000000 83FB11" -name com.apple.driver.usb.AppleUSBXHCI || $KEXTTOPATCH $config add -find "C8000000 83FB02" -replace "C8000000 83FB11" -name com.apple.driver.usb.AppleUSBXHCI
	elif [[ $(sw_vers -productVersion) =~ (10.14.1|10.14.2)$ ]]; then
		$KEXTTOPATCH $config Has -find "00E083FB 0F0F8716 0400" -replace "00E083FB 3F0F8716 0400" -name IOUSBHostFamily || $KEXTTOPATCH $config add -find "00E083FB 0F0F8716 0400" -replace "00E083FB 3F0F8716 0400" -name IOUSBHostFamily
	fi
	if [[ $(sw_vers -productVersion) =~ (10.13|10.13.0|10.13.1|10.13.2|10.13.3)$ ]]; then
		$KEXTTOPATCH $config Has -find "837D8C10" -replace "837D8C1B" -name com.apple.driver.usb.AppleUSBXHCIPCI || $KEXTTOPATCH $config add -find "837D8C10" -replace "837D8C1B" -name com.apple.driver.usb.AppleUSBXHCIPCI
	elif [[ $(sw_vers -productVersion) =~ (10.13.4|10.13.5)$ ]]; then
		$KEXTTOPATCH $config Has -find "837D940F 0F839704 0000" -replace "837D940F 90909090 9090" -name com.apple.driver.usb.AppleUSBXHCI || $KEXTTOPATCH $config add -find "837D940F 0F839704 0000" -replace "837D940F 90909090 9090" -name com.apple.driver.usb.AppleUSBXHCI
	elif [[ $(sw_vers -productVersion) == 10.13.6 ]]; then
		$KEXTTOPATCH $config Has -find "837D880F 0F83A704 0000" -replace "837D880F 90909090 9090" -name com.apple.driver.usb.AppleUSBXHCI || $KEXTTOPATCH $config add -find "837D880F 0F83A704 0000" -replace "837D880F 90909090 9090" -name com.apple.driver.usb.AppleUSBXHCI
	elif [[ $(sw_vers -productVersion) =~ (10.14.1|10.14.2)$ ]]; then
		$KEXTTOPATCH $config Has -find "83FB0F0F 83030500 00" -replace "83FB0F90 90909090 90" -name com.apple.driver.usb.AppleUSBXHCI || $KEXTTOPATCH $config add -find "83FB0F0F 83030500 00" -replace "83FB0F90 90909090 90" -name com.apple.driver.usb.AppleUSBXHCI
	fi
else
	echo -e "\n[ERROR] Installed clover have config.plist missing \n[ALERT] USB ports might not work completely."
	quit
fi

echo -e "\n[ALERT] Patching completed successfully, Please reboot the system ! \n[ALERT] You might also need to un-plug and re-plug all your USB devices."
rm -rf ~/Desktop/ryzenusbfix.sh /tmp/XLNC 
sleep 5 && exit 0
