#!/bin/sh

#  Matthias Strubel    (c) 2013-2014
#    licenced with GPL-3
#
# Generate severall configuration files out of piratebox.conf
#     conf/hosts_generated
#     conf/dnsmasq_generated.conf
#     conf/radvd_generated.conf
#     conf/lighttpd/env
#     conf/hosts_mesh
#
# There are files for default configuration or adding custom stuff:
#     conf/hosts
#     conf/dnsmasq_default.conf
#
#  it is using the following VARS out of piratebox.conf:
#    NET               = The network of your box  i.e. 192.168.1
#    IP_SHORT          = The ip of the piratebox  i.e. 1    results 192.168.1.1
#    START_LEASE       =   Range of dhcp leases  start  10
#    END_LEASE         =                         end    250
#    LEASE_DURATION    =    lease time           30min
#    HOSTNAME          =  piratebox.lan   - o'rly?  Maybe generate some additional stuff here
#  -
#    GLOBAL_CHAT       = Enable Broadcasts
#    GLOBAL_DEST       = Broadcast IP destinations
#    PYTHONPATH        = Path of PirateBox python libs
#    GEN_CHATFILE      = generated html chatfile
#    PIRATEBOX         = PirateBox Folder
#    CHATFILE          = data store for Shoutbox-content
#
#    NODE_CONFIG       = Config file for Mesh-Node parameters
#  -
#  ipv6.conf (loaded within piratebox.conf)
#    IPV6_ENABLE	= enables IPv6 config
#    IPV6_ADVERT	= which service for advertising IPv6 Prefix
#    IPV6_MASK		= Netmask
#    IPV6_PREFIX	= Which prefix should be announced.
#  -
#  node.conf
#    NODE_CONFIG_ACTIVE = if yes, configure special ipv6-node-hostname
#    NODE_IPV6_IP	= Device specific IP
#    NODE_NAME & NODE_GEN = Settings for setting up Hostname
#
#  Matthias Strubel    -- 08.06.2012
#    licenced with GPL-3

CONFIG_PATH="conf"
DNSMASQ_CONFIG=""
HOSTS_CONFIG=""
DEFAULT_HOSTS=""
LEASE_FILE=""
RADVD_CONFIG=""
LIGHTTPD_ENV_CONFIG=""
AVAHI_SRC=""
AVAHI_CONFIG=""

set_pathnames() {
  CONFIG_PATH=$1/conf
  DNSMASQ_CONFIG=$CONFIG_PATH/dnsmasq_generated.conf
  HOSTS_CONFIG=$CONFIG_PATH/hosts_generated
  HOSTS_MESH=$CONFIG_PATH/hosts_mesh
  DEFAULT_HOSTS=$CONFIG_PATH/hosts
  DEFAULT_DNSMASQ=$CONFIG_PATH/dnsmasq_default.conf
  RADVD_CONFIG=$CONFIG_PATH/radvd_generated.conf
  LEASE_FILE=$LEASE_FILE_LOCATION
  LIGHTTPD_ENV_CONFIG=$CONFIG_PATH/lighttpd/env
  AVAHI_CONFIG=$CONFIG_PATH/avahi/avahi-daemon.conf
  AVAHI_SRC=$CONFIG_PATH/avahi/avahi-daemon.conf.schema

}

generate_hosts() {
   set_hostname=$1
   set_ipv4=$2
   set_ipv6=$3
   echo "Generating hosts file .... "
   cat  $DEFAULT_HOSTS                 >  $HOSTS_CONFIG
   echo "$set_ipv4     $set_hostname " >> $HOSTS_CONFIG
   echo "$set_ipv6     $set_hostname " >> $HOSTS_CONFIG

}

generate_dnsmasq() {
   net=$1
   lease_start=$3
   lease_end=$4
   lease_time=$5
   ip_pb=$2
   dnsmasq_interface=$6
   echo "Generating dnsmasq.conf ....."
   cat $DEFAULT_DNSMASQ                > $DNSMASQ_CONFIG

   #Add interface line if filled
   [ -n $dnsmasq_interface ] &&   echo "interface=$dnsmasq_interface" >> $DNSMASQ_CONFIG

   lease_line="$net.$lease_start,$net.$lease_end,$lease_time"
   echo  "dhcp-range=$lease_line"      >> $DNSMASQ_CONFIG
   #redirect every dns
   dns_redirect="/#/$net.$ip_pb"
   echo "address=$dns_redirect"        >> $DNSMASQ_CONFIG
   echo "dhcp-leasefile=$LEASE_FILE"   >> $DNSMASQ_CONFIG

   echo "addn-hosts=$HOSTS_CONFIG"     >>$DNSMASQ_CONFIG

   #Mesh hosts
   echo "addn-hosts=$HOSTS_MESH" 	>> $DNSMASQ_CONFIG

   if [ "$IPV6_ENABLE" = "yes" ] && [ "$IPV6_ADVERT" = "dnsmasq" ] ; then
     echo "Do additional v6 stuff in dnsmasq.conf"
     echo "#----- V6 Stuff"                     >> $DNSMASQ_CONFIG
     echo "dchp-range=$ipv6_call::, ra-stateless" >> $DNSMASQ_CONFIG
   fi

}

generate_radvd(){
  prefix=$1
  mask=$2
  interface=$3

  echo "Generating config for radvd.."
  echo "#---- generated file ---"               > $RADVD_CONFIG
  echo "
    interface $interface {
       AdvSendAdvert on;
       MinRtrAdvInterval 3;
       MaxRtrAdvInterval 10;
       prefix $prefix::/$mask {
           AdvOnLink on;
	   AdvAutonomous on;
	   AdvRouterAddr on;
       };
    };
       "                                        >>  $RADVD_CONFIG

}

#------------ lighttpd env config - Start ---------------------

generate_lighttpd_env() {
        local GLOBAL_CHAT=$1
        local GLOBAL_DEST="$2"
	local PYTHONPATH=$3
	local SHOUTBOX_GEN_HTMLFILE=$4
	local PIRATEBOX=$5
	local SHOUTBOX_CHATFILE=$6
	local SHOUTBOX_CLIENT_TIMESTAMP=$7
	local IN_UPLOAD_PATH=$8
  	local DISK_GEN_HTMLFILE=$9
    local HOSTNAME=$10

        echo "Generating Environment-config for lighttpd ....."

        LIGHTTPD_ENV_BR_LINE=""
	if [ "$GLOBAL_CHAT" = "yes" ] ; then
	     LIGHTTPD_ENV_BR_LINE="   \"SHOUTBOX_BROADCAST_DESTINATIONS\" => \"$GLOBAL_DEST\" , "
	fi

	echo "setenv.add-environment = (
	   \"PYTHONPATH\"             => \"$PYTHONPATH:$PIRATEBOX/python_lib\",
	   \"SHOUTBOX_GEN_HTMLFILE\"  => \"$SHOUTBOX_GEN_HTMLFILE\" ,
	   \"SHOUTBOX_CHATFILE\"      => \"$SHOUTBOX_CHATFILE\" ,
	   \"SHOUTBOX_CLIENT_TIMESTAMP\" => \"$SHOUTBOX_CLIENT_TIMESTAMP\" ,
	   \"UPLOAD_PATH\" => \"$IN_UPLOAD_PATH\" ,
	   \"PIRATEBOX_HOSTNAME\" => \"$HOSTNAME\" ,
     	   \"DISK_GEN_HTMLFILE\"      => \"$DISK_GEN_HTMLFILE\" ,
	   $LIGHTTPD_ENV_BR_LINE

        )
        var.PIRATEBOX_HOSTNAME = \"$HOSTNAME\"
        var.CONFDIR = \"$CONFIG_PATH\"
        "  > $LIGHTTPD_ENV_CONFIG
}

#------------ lighttpd env config - End   ---------------------

#------------  change php ini ---------------------------------
work_php_ini=""
php_ini_entry(){
    in_parm=$1
    in_val=$2

    if grep -q "$in_parm" "$work_php_ini" ; then
        old_val=$( grep  "$in_parm" "$work_php_ini" | head -n 1 )
        sed -i -e "s|${old_val}|${in_parm} = ${in_val}|g" "$work_php_ini"
    else
        echo "ERROR php.ini : Old val. $in_parm not found"
    fi

}
generate_php_ini(){
    echo "Generating custom php.ini ... "
    test -e /etc/php.ini && cp /etc/php.ini "${PIRATEBOX_FOLDER}/tmp/php.ini.original"
    test -e /etc/php/php.ini && cp /etc/php/php.ini "${PIRATEBOX_FOLDER}/tmp/php.ini.original"
    # Comment original statements
    sed -e 's|^upload_tmp_dir|;upload_tmp_dir|g' \
        -e 's|^upload_max_filesize|;upload_max_filesize|g' \
        -e 's|^post_max_size|;post_max_size|g' \
        -e 's|^max_file_uploads|;max_file_uploads|g' \
        "${PIRATEBOX_FOLDER}/tmp/php.ini.original" > "$CONFIG_PATH/php.ini"
    work_php_ini="$CONFIG_PATH/php.ini"

    php_ini_entry 'upload_tmp_dir' "$UPLOAD_TMP_FOLDER"
    php_ini_entry 'upload_max_filesize' "$UPLOAD_MAX_SIZE"
    php_ini_entry 'post_max_size'   "0"
    php_ini_entry 'max_file_uploads' "10"

}
##------------- piratebox_config.php -----------------
generate_piratebox_php(){
    echo "Generate piratebox_config.php"
    sed -e "s|####UPLOAD_ENABLED####|${UPLOAD_ENABLED}|g"    \
        -e "s|####UPLOAD_FOLDER####|${UPLOADFOLDER}|g"       \
        -e "s|####OVERWRITE####|${UPLOAD_ALLOW_OVERWRITE}|g" \
        -e "s|####DO_CHMOD####|${UPLOAD_DO_CHMOD}|g"         \
        -e "s|####CHMOD####|${UPLOAD_CHMOD}|g"               \
        "$CONFIG_PATH/piratebox_config.php.template" >  "${PIRATEBOX_FOLDER}/www/piratebox_config.php"
}

if [ -z  $1 ] ; then
  echo "Usage is
      generate_config_files.sh /opt/piratebox/conf/piratebox.conf
   "
   exit 255
fi

if [ !  -f $1 ] ; then
  echo "Config-File $1 not found..."
  exit 255
fi

. $1

. $NODE_CONFIG
. $PIRATEBOX_FOLDER/lib/node_name_generation.sh

IPV6="#"

set_pathnames  $PIRATEBOX_FOLDER

ipv6_call=''
if [ "$IPV6_ENABLE" = "yes" ] ; then
   ipv6_call=$IPV6_PREFIX
   IPV6=$IPV6_IP
   [[ "$IPV6_ADVERT" = "radvd" ]] && generate_radvd $IPV6_PREFIX  $IPV6_MASK $DNSMASQ_INTERFACE
fi
generate_hosts $HOST  $IP  $IPV6
generate_dnsmasq  $NET $IP_SHORT  $START_LEASE  $END_LEASE $LEASE_DURATION $DNSMASQ_INTERFACE
generate_lighttpd_env $GLOBAL_CHAT "$GLOBAL_DEST" $PIRATEBOX_PYTHONPATH $GEN_CHATFILE $PIRATEBOX_FOLDER  $CHATFILE $SHOUTBOX_CLIENT_TIMESTAMP $UPLOADFOLDER $GEN_DISKFILE $HOST

COMPLETE_HOST=$HOST

if [ "$NODE_CONFIG_ACTIVE" = "yes" ] ; then
     echo -n "Appending local node-name hosts entry "
     if generate_node_name "$HOST" "$NODE_NAME" "$NODE_GEN" ; then
	echo $NODE_GEN_OUTPUT
	echo "$NODE_IPV6_IP   $NODE_GEN_OUTPUT  " >> $HOSTS_CONFIG
	COMPLETE_HOST=$NODE_GEN_OUTPUT
     else
	 echo "Error: No valid node-name-config found, skipping"
     fi
fi

#We want a long hostname and not only the hostname itself...
### PirateBox Scripts generates its own config in  /opt/piratebox/conf/avahi
###   but, the daemon works per default only on /etc/avahi
### If you want to enable avahi, then you have to link /etc/avahi to /opt/piratebox/conf/avahi
### On OpenWRT this should happen, if avahi is available before installing the piratebox
###  automtically.
AVAHI_HOST=$( echo $COMPLETE_HOST | sed 's|\.|_|g' )
sed "s|#####MASKED_HOSTNAME#####|$AVAHI_HOST|" $AVAHI_SRC > $AVAHI_CONFIG

generate_php_ini
generate_piratebox_php
