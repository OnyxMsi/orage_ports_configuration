#!/bin/sh
set -e

SCRIPTNAME=$(basename $0)
SCRIPTDIR=$(dirname $(realpath $0))
VERBOSITY_LEVEL=0

SYSTEM_ETC=/usr/local/etc
SYSTEM_POUDRIERE_D="$SYSTEM_ETC/poudriere.d"
SYSTEM_POUDRIERE_CONF="$SYSTEM_ETC/poudriere.conf"
DEFAULT_ETCDIR=/tmp/etcdir
DEFAULT_POUDRIERE_D="${SCRIPTIDR:-.}/poudriere.d"
DEFAULT_SET=workstation
CURRENT_USER=$(id -u -n)
CURRENT_GROUP=$(id -g -n)

log() {
    LVL=$1
    HDR=$2
    OUT=$3
    shift 3
    [ $VERBOSITY_LEVEL -ge $LVL ] && echo "$SCRIPTNAME [$HDR] $*" >> $OUT
}

LOG_STDOUT=/dev/stdout
LOG_STDERR=/dev/stderr


err() {
    log 0 ERR $LOG_STDERR $*
}
wrn() {
    log 0 WRN $LOG_STDOUT $*
}
inf() {
    log 1 INF $LOG_STDOUT $*
}
dbg() {
    log 2 DBG $LOG_STDOUT $*
}
_cmd() {
    log 3 CMD $LOG_STDOUT $*
}
cmd() {
    COMMAND=$*
    _cmd "$COMMAND"
    eval $COMMAND > /dev/null
    ret=$?
    if [ $ret -ne 0 ] ; then
        err "$COMMAND"
        err "Failed with code $ret"
        exit 3
    fi
}
crt_invalid_command_line() {
    err "Invalid command line: $*"
    exit 1
}
check_argument_count() {
    local count=$1 ; shift
    if [ $# -lt $count ] ; then
        err "Not enough arguments. See help."
        exit 1
    fi
}

is_in_list() {
    local i=$1 ; shift
    for l in $* ; do
        if [ $l = $i ] ; then
            return 0
        fi
    done
    return 1
}

COMMAND_CONFIGURE=configure
COMMAND_BUILD=build
COMMAND_LIST=list
COMMAND_LIST_JAIL=jail
COMMAND_LIST_TREE=tree
COMMAND_LIST_SET=workspace

help() {
    echo "$SCRIPTNAME [-v][-h][-j][-t][-w] command ..."
    echo "A tool to build configure FreeBSD port tree"
    echo " -h Show this and quit"
    echo " -v increase verbosity level, can be set multiple times"
    echo " -j Jail to use, can be set multiple times"
    echo " -t Port tree to use, can be set multiple times"
    echo " -s Set to use, can be set multiple times"
    echo " -e etcdir. See poudriere(8). Default is $DEFAULT_ETCDIR"
    echo " -f force"
    echo "$SCRIPTNAME command $COMMAND_CONFIGURE port ..."
    echo "Configure specified ports"
    echo " If -f is set then previous configuration will be overwritten"
    echo "$SCRIPTNAME command $COMMAND_BUILD port ..."
    echo "Build specified ports"
    echo "$SCRIPTNAME command $COMMAND_LIST ..."
    echo "Utilities command to list stuff"
    echo "$SCRIPTNAME command $COMMAND_LIST $COMMAND_LIST_JAIL"
    echo "List available jails"
    echo "$SCRIPTNAME command $COMMAND_LIST $COMMAND_LIST_TREE"
    echo "List available trees"
}

install_configuration_directory() {
    dbg "Install configuration directory from $DEFAULT_POUDRIERE_D into $ETCDIR"
    if [ -e "$ETCDIR" ] ; then
        wrn "Remove previous content in $ETCDIR"
        cmd sudo rm -rf $ETCDIR
    fi
    dbg "Create configuration directory $ETCDIR"
    cmd mkdir -p $ETCDIR
    # First thing is to use system configuration
    dbg "Import system poudriere.conf from $SYSTEM_POUDRIERE_CONF"
    cmd cp $SYSTEM_POUDRIERE_CONF $ETCDIR/
    dbg "Import system poudriere.d from $SYSTEM_POUDRIERE_D"
    cmd cp -R $SYSTEM_POUDRIERE_D $ETCDIR/
    if [ -d $DEFAULT_POUDRIERE_D ] ; then
        cmd cp -R $DEFAULT_POUDRIERE_D/* $ETCDIR/poudriere.d/
    fi
    inf "$ETCDIR is ready to proceed"
}

command_build() {
    local ports=$*
    check_argument_count 1 $*
    dbg "Build ports $ports"
    install_configuration_directory
    for j in $JAILS_CHOICES ; do
        for t in $TREES_CHOICES ; do
            for s in $SETS_CHOICES ; do
                dbg "Build ports on jail $j from ports tree $t using set $s"
                cmd sudo poudriere -e $ETCDIR bulk -j $j -p $t -z $s $ports
                inf "Ports built on jail $j from ports tree $t using set $s"
            done
        done
    done
    inf "Building is done"
}
command_configure() {
    local ports=$*
    local dirname
    local repo_dir
    local etc_dir
    check_argument_count 1 $*
    dbg "Configure ports $ports"
    install_configuration_directory
    [ $FORCE -ne 0 ] && wrn "Force is set, previous configuration will be overwritten"
    for j in $JAILS_CHOICES ; do
        for t in $TREES_CHOICES ; do
            for s in $SETS_CHOICES ; do
                dbg "Configure ports on jail $j from ports tree $t using set $s"
                if [ $FORCE -ne 0 ] ; then
                    cmd sudo poudriere -e $ETCDIR options -j $j -p $t -z $s -r $ports
                else
                    cmd sudo poudriere -e $ETCDIR options -j $j -p $t -z $s $ports
                fi
                inf "Ports were configured on jail $j from ports tree $t using set $s"
                # Make sure current user has permissions to copy this
                cmd sudo chown -R $CURRENT_USER:$CURRENT_GROUP $ETCDIR
                dirname="$j-$t-$s-options"
                repo_dir="$DEFAULT_POUDRIERE_D/$dirname"
                etc_dir="$ETCDIR/poudriere.d/$dirname"
                if [ -e $repo_dir ] ; then
                    dbg "Remove previous configuration for $j $t $s at $repo_dir"
                    cmd rm -rf $repo_dir
                fi
                dbg "Import configuration from $etc_dir into $repo_dir"
                cmd cp -R $etc_dir $repo_dir
            done
        done
    done
}
command_list_jail() {
    poudriere jail -l | cut -f 1 -d " "
}
command_list_tree() {
    poudriere ports -l | cut -f 1 -d " "
}
command_list() {
    if [ $# -lt 1 ] ; then
        crt_invalid_command_line "No list command, see help"
    fi
    local COMMAND=$1 ; shift
    case $COMMAND in
        $COMMAND_LIST_JAIL) command_list_jail $*;;
        $COMMAND_LIST_TREE) command_list_tree $*;;
        --) break ;;
        *) crt_invalid_command_line "Unknown list command $COMMAND" ;;
    esac
}

FORCE=0
ETCDIR=$DEFAULT_ETCDIR
while getopts hve:j:t:w: ARG ; do
    shift
    case "$ARG" in
        h) help ; exit 0;;
        j) JAILS_CHOICES="$JAILS_CHOICES $1" ; shift ;;
        t) TREES_CHOICES="$TREES_CHOICES $1" ; shift ;;
        s) SETS_CHOICES="$SETS_CHOICES $1" ; shift ;;
        v) VERBOSITY_LEVEL=$(($VERBOSITY_LEVEL + 1)) ;;
        f) FORCE=1 ;;
        e) ETCDIR=$1 ; shift ;;
        --) break ;;
        *) crt_invalid_command_line "Unknown option $ARG" ;;
    esac
done
if [ $# -lt 1 ] ; then
    crt_invalid_command_line "No command, see help"
fi
COMMAND=$1 ; shift

EVERY_JAIL=$(command_list_jail)
if [ "$JAILS_CHOICES" = "" ] ; then
    dbg "No jail in parameters, work on every jails"
    JAILS_CHOICES=$EVERY_JAIL
else
    for j in $JAILS_CHOICES ; do
        test ! is_in_list $j "$EVERY_JAIL" && err "Unknown jail $j" ; exit 1
    done
fi
EVERY_TREE=$(command_list_tree)
if [ "$TREES_CHOICES" = "" ] ; then
    dbg "No tree in parameters, work on every trees"
    TREES_CHOICES=$EVERY_TREE
else
    for j in $TREES_CHOICES ; do
        test ! is_in_list $j "$EVERY_TREE" && err "Unknown tree $j" ; exit 1
    done
fi
if [ "$SETS_CHOICES" = "" ] ; then
    wrn "Use default set $DEFAULT_SET"
    SETS_CHOICES="$DEFAULT_SET"
fi

case $COMMAND in
    $COMMAND_BUILD) command_build $*;;
    $COMMAND_CONFIGURE) command_configure $*;;
    $COMMAND_LIST) command_list $*;;
    --) break ;;
    *) crt_invalid_command_line "Unknown command $COMMAND" ;;
esac
dbg Success
exit 0
