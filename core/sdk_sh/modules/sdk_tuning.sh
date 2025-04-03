# HEX SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

TMP_TUNGINS_RAW=/tmp/tunings.raw
_tuning_dump()
{
    [ -e $TMP_TUNGINS_RAW ] || Error "no $TMP_TUNGINS_RAW"

    if [ "x$FORMAT" = "xjson" ] ; then
        printf "[ "
    else
        printf "%s\n" "Published Tunings"
        printf "%s\n" "----------------------------------------------------------------"
        printf "%-30s%-100s%s\n" "Name" "Description" "Type|Default|Min|Max|Regex"
    fi

    local cnt=0
    while read line_raw ; do
        line="$(echo $line_raw | tr -d '"')" # remove '"' that leads to jq parsing errors
        name="$(echo $line | cut -d'|' -f1)"
        desc="$(echo $line | cut -d'|' -f2)"
        type="$(echo $line | cut -d'|' -f3)"
        dflt="$(echo $line | cut -d'|' -f4)"
        minv="$(echo $line | cut -d'|' -f5)"
        maxv="$(echo $line | cut -d'|' -f6)"
        regx="$(echo $line | cut -d'|' -f7)"

        if [ "x$FORMAT" = "xjson" ] ; then
            [ $cnt -le 0 ] || printf ","
            (( cnt++ ))
            printf "{ "
            printf "\"name\": \"%s\"," "$name"
            printf "\"description\": \"%s\"," "$desc"
            printf "\"limitation\": { \"type\": \"%s\",\"default\": \"%s\",\"min\": \"%s\",\"max\": \"%s\",\"regex\": \"%s\" }" "$type" "$dflt" "$minv" "$maxv" "$regx"
            printf " }"
        else
            printf "%-30s%-100s[%s|%s|%s|%s|%s]\n" "$name" "$desc" "$type" "$dflt" "$minv" "$maxv" "$regx"
        fi
    done < $TMP_TUNGINS_RAW

    if [ "x$FORMAT" = "xjson" ] ; then
        printf " ]\n"
    fi
}

tuning_dump()
{
    local preamble="Quiet -n"

    [ "x$FORMAT" = "xjson" ] || preamble=
    if [ "x$1" = "x-P" -o "x$1" = "x--pub_tuning" -o "x$1" = "x-T" ] ; then
        $preamble $HEX_CFG $1
    else
        $preamble $HEX_CFG --pub_tuning
    fi
    _${FUNCNAME[0]}
}
