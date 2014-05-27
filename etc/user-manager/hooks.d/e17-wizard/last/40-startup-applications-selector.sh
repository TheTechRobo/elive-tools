#!/bin/bash
source /usr/lib/elive-tools/functions
#el_make_environment
. gettext.sh
TEXTDOMAIN="elive-tools"
export TEXTDOMAIN


main(){
    # pre {{{
    local file menu message_gui

    RAM_TOTAL_SIZE_bytes="$(grep MemTotal /proc/meminfo | tr ' ' '\n' | grep "^[[:digit:]]*[[:digit:]]$" | head -1 )"
    RAM_TOTAL_SIZE_mb="$(( $RAM_TOTAL_SIZE_bytes / 1024 ))"
    RAM_TOTAL_SIZE_mb="${RAM_TOTAL_SIZE_mb%.*}"


    # }}}

    while read -ru 3 file
    do
        unset name comment
        #echo "$file"

        # checks {{{
        if [[ ! -s "$file" ]] ; then
            continue
        fi

        filename="$(basename "$file" )"

        # - checks }}}
        # un-needed / blacklisted ones {{{
        if echo "$filename" | grep -qsEi "^(kde|glipper-|nm-applet|wicd-|print-applet|notification-daemon)" ; then
            # glipper: we want to enable it in a different way: if ctrl+alt+c si pressed, run it for 8 hours long and close/kill it to save mem
            # nm-applet: already integrated in elive correctly and saving mem
            # wicd-: deprecated and not needed for elive
            # print-applet: useless
            # notification-daemon: dont include it if we are going to use e17's one
            continue
        fi
        # - un-needed ones }}}
        # default to enabled/disabled {{{

        if [[ "$RAM_TOTAL_SIZE_mb" -gt 900 ]] ; then
            if echo "$filename" | grep -qsEi "^(polkit|gdu-notif|gnome-|user-dirs-update)" ; then
                menu+=("TRUE")
                el_debug "state: TRUE"
            else
                menu+=("FALSE")
                el_debug "state: FALSE"
            fi
        else
            if echo "$filename" | grep -qsEi "^(polkit|gdu-notif|user-dirs-update)" ; then
                menu+=("TRUE")
                el_debug "state: TRUE"
            else
                menu+=("FALSE")
                el_debug "state: FALSE"
            fi
        fi

        # - default to enabled/disabled }}}

        # include file
        menu+=("$file")
        el_debug "file: $file"

        # include name {{{
        name="$( grep "^Name\[${LANG%%.*}\]" "$file" )"
        if [[ -z "$name" ]] ; then
            name="$( grep "^Name\[${LANG%%.*}" "$file" )"
            if [[ -z "$name" ]] ; then
                name="$( grep "^Name\[${LANG%%_*}\]" "$file" )"
                if [[ -z "$name" ]] ; then
                    name="$( grep "^Name\[${LANG%%_*}" "$file" )"
                    if [[ -z "$name" ]] ; then
                        name="$( basename "${file%.*}" )"
                    fi
                fi
            fi
        fi

        # empty?
        if [[ -z "$name" ]] ; then
            name="(empty)"
        fi
        # add name
        menu+=("${name#*]=}")
        el_debug "name: ${name#*]=}"

        # }}}
        # include comment {{{
        comment="$( grep "^Comment\[${LANG%%.*}\]" "$file" )"
        if [[ -z "$comment" ]] ; then
            comment="$( grep "^Comment\[${LANG%%.*}" "$file" )"
            if [[ -z "$comment" ]] ; then
                comment="$( grep "^Comment\[${LANG%%_*}\]" "$file" )"
                if [[ -z "$comment" ]] ; then
                    comment="$( grep "^Comment\[${LANG%%_*}" "$file" )"
                fi
            fi
        fi

        # empty?
        if [[ -z "$comment" ]] ; then
            comment="(empty)"
        fi
        # add comment
        menu+=("${comment#*]=}")
        el_debug "comment: ${comment#*]=}"

        el_debug "       (loop)"
        # }}}

    done 3<<< "$( find /etc/xdg/autostart/ -type f -iname '*'.desktop )"

    el_dependencies_check "zenity"

    if [[ "$RAM_TOTAL_SIZE_mb" -lt 700 ]] ; then
        message_gui="$( printf "$( eval_gettext "Select the services that you want to have enabled on your desktop. Note that you don't have much RAM memory and they will use it." )" )"
    else
        message_gui="$( printf "$( eval_gettext "Select the services that you want to have enabled on your desktop." )" )"
    fi

    answer="$( zenity --list --checklist --height=580 --width=630 --text="$message_gui"  --column="" --column="" --column="$( eval_gettext "Name" )" --column="$( eval_gettext "Comment" )" "${menu[@]}" --print-column=2 --hide-column=2 || echo cancel )"

    while read -ru 3 file
    do
        if [[ -s "$file" ]] ; then
            filename="$(basename "$file" )"

            # verify the needed ones
            if [[ "$filename" = polkit*authentication* ]] ; then
                is_polkit_auth_included=1
            fi

            if [[ "$filename" = gdu*notifica* ]] ; then
                is_gdu_notif_included=1
            fi

            if ! grep -qs "$file" "$HOME/.e/e/applications/startup/.order" ; then
                echo "$file" >> "$HOME/.e/e/applications/startup/.order"
            fi
        fi
    done 3<<< "$( echo "$answer" | tr '|' '\n' )"

    # polkit auth
    if ! ((is_polkit_auth_included)) ; then
        if zenity --question --text="$( eval_gettext "You have not included Polkit authentication agent, but is very important for the correct work of your system, it allows you to use media devices or mount hard disks. But Elive can add a special configuration that can allows you to still use perfectly the disks, are you sure that you want to disable it ?" )" ; then
            if zenity --question --text="$( eval_gettext "Do you want to have full access to the hard disks for this user ?" )" ; then
#cat > /var/lib/polkit-1/localauthority/10-vendor.d/10-live-cd.pkla << EOF
                cat > /tmp/.$(basename $0 )-${USER}.txt << EOF
# Policy to allow the user $USER to bypass policykit
[Elive special user permissions]
Identity=unix-user:${USER}
Action=*
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

                el_dependencies_check "gksu"
                gksu "cp /tmp/.$( basename $0 )-${USER}.txt /var/lib/polkit-1/localauthority/10-vendor.d/10-elive-user-${USER}.pkla"
            fi
        else
            # re-enable it
            file="$( echo "$answer" | tr '|' '\n' | grep "/polkit.*authentication" | head -1 )"
            if [[ -s "$file" ]] ; then
                if ! grep -qs "$file" "$HOME/.e/e/applications/startup/.order" ; then
                    echo "$file" >> "$HOME/.e/e/applications/startup/.order"
                fi
            else
                el_error "Polkit startup file not found"
                sleep 2
            fi

        fi
    fi

    # gdu
    if ! ((is_gdu_notif_included)) ; then
        if zenity --question --text="$( eval_gettext "You have not included Gdu Notification, this one is useful for alert you in case that it is discovered an error in your hard disk, are you sure that you want to disable it ?" )" ; then
            true
        else
            # re-enable it
            file="$( echo "$answer" | tr '|' '\n' | grep "/gdu.*notification" | head -1 )"
            if [[ -s "$file" ]] ; then
                if ! grep -qs "$file" "$HOME/.e/e/applications/startup/.order" ; then
                    echo "$file" >> "$HOME/.e/e/applications/startup/.order"
                fi
            else
                el_error "Gdu startup file not found"
                sleep 2
            fi
        fi
    fi

}

#
#  MAIN
#
main "$@"

# vim: set foldmethod=marker :
