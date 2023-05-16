#!/bin/sh
#
DBG=${DBG:-0} && [ "0$DBG" -eq 0 ]; [ "$DBG" -eq 1 ] && set -x
export DBG

#
#
#
AWK_FUNCTIONS=$(cat <<- %E%O%T%
    function ltrim(s) { sub(/^[ \t\r\n]+/, "", s); return s }
    function rtrim(s) { sub(/[ \t\r\n]+$/, "", s); return s }
    function trim(s)  { return rtrim(ltrim(s)); }
    function rpad(s, i) { return sprintf("%s%*s", s, i, " ") }
    function squeeze(s)  { return gensub(/[[:space:]]/, "", "g", s); }

    # mktime() cannot handle character month
    #  swap day/month if needed
    function fixdate(s) {
        i = split(s, a)

        for (j = 1; j <= i; j++) {
            switch (a[j]) {
            case /^Jan/:
                a[j] = 1
                pos = j
                break
            case /^Feb/:
                a[j] = 2
                pos = j
                break
            case /^Mar/:
                a[j] = 3
                pos = j
                break
            case /^Apr/:
                a[j] = 4
                pos = j
                break
            case "May":
                a[j] = 5
                pos = j
                break
            case /^Jun/:
                a[j] = 6
                pos = j
                break
            case /^Jul/:
                a[j] = 7
                pos = j
                break
            case /^Aug/:
                a[j] = 8
                pos = j
                break
            case /^Sep/:
                a[j] = 9
                pos = j
                break
            case /^Oct/:
                a[j] = 10
                pos = j
                break
            case /^Nov/:
                a[j] = 11
                pos = j
                break
            case /^Dec/:
                a[j] = 12
                pos = j
            }
        }

        for (j = i; j <= 6; j++) {
            a[j] = 0
        }

        if (pos == 3)
            datespec = sprintf("%s %s %s %s %s %s", a[1], a[3], a[2], a[4], a[5], a[6])
        else
            datespec = sprintf("%s %s %s %s %s %s", a[1], a[2], a[3], a[4], a[5], a[6])

        timestamp = mktime(datespec)
        if (timestamp > 0)
            return(strftime("%Y-%m-%d", timestamp))
        else
            return("")
    }

%E%O%T%
)

parse_visa () {
    local file=$1
    local header=$2 && header=${header:-0}
    
    cat $file | awk -v header=$header -v filename="$file" -e "$AWK_FUNCTIONS" -e '
        function dbg(s) { if (ENVIRON["DBG"] ~ "2") printf("DBG \"%s\" : %s\n", s, $0) > "/dev/stderr" }

        function process_lines() {
            while (getline > 0) {
                if (match($0, /Date[[:space:]]+Description/) > 0) {
                    col1 = RSTART
                    col2 = match($0, /Description[[:space:]]+/)
                    col3 = match($0, /Withdrawals[[:space:]]+/)
                    col4 = match($0, /Deposits[[:space:]]+/)
                    col5 = match($0, /Balance[[:space:]]*/)

                    start = 1

                    continue
                }

                date = trim(substr($0, col1, col2 - col1))
                activity = trim(substr($0, col2, col3 - col2))
                desc2 = ""
                withdrawal = trim(substr($0, col3, col4 - col3))
                deposit = trim(substr($0, col4, col5 - col4))

                if (save == 1 && length($0) == 0) {
                    dbg(" > end")
                    save = 0
                    start = 0

                    break
                } else if (start == 1 && save == 0) {
                    if (match($0, "Opening Balance") > 1)
                        continue

                    if (length(date) > 0) {
                        isodate = fixdate(sprintf("%s %s 0 0 0", fromyear, date))
                        if (length(isodate) > 0) {
                            dbg(" > save")
                            save = 1
                            lastdate = date

                            if (length(withdrawal) == 0 && length(deposit) == 0) {
                                # 2 line activity
                                dbg(" > 2line")
                                if (getline > 0) {
                                    desc2 = trim(substr($0, col2, col3 - col2))
                                    withdrawal = trim(substr($0, col3, col4 - col3))
                                    deposit = trim(substr($0, col4, col5 - col4))
                                } else {
                    
                                    break;
                                }
                            }

                            if (length(withdrawal) > 1)
                                amount = sprintf("-%s", withdrawal)
                            else
                                amount = deposit

                            text[++line] = sprintf("%s^%s^%s^%s", date, activity, desc2, amount)
                            dbg(sprintf(">%s^%s^%s^%s<", date, activity, desc2, amount))
                        }
                    
                        continue
                    }
                } else if (save == 1) {
                    if (match($0, "Closing Balance") > 1) {
                        dbg(" > end2")
                        save = 0
                        start = 0

                        break
                    }

                    if (length(withdrawal) == 0 && length(deposit) == 0) {
                        # 2 line activity
                        dbg(" > 2line")
                        if (getline > 0) {
                            desc2 = trim(substr($0, col2, col3 - col2))
                            withdrawal = trim(substr($0, col3, col4 - col3))
                            deposit = trim(substr($0, col4, col5 - col4))
                        } else {
                    
                            break;
                        }
                    }

                    if (length(withdrawal) > 1)
                        amount = sprintf("-%s", withdrawal)
                    else
                        amount = deposit

                    if (length(date) == 0) date = lastdate

                    text[++line] = sprintf("%s^%s^%s^%s", date, activity, desc2, amount)
                    dbg(sprintf(">%s^%s^%s^%s<", date, activity, desc2, amount))
                }
            }
        }

        BEGIN {
            visa = 0
            account = ""
            save = 0
            line = 0

            while (getline > 0) {
                if (match($0, /^RBC[\(R\)]*[[:space:]].*Visa/) > 0) {
                    visa = 1

                    while (getline > 0) {
                        if (match($0, /[[:digit:]][0123456789 \*]*[[:digit:]]*/) > 0) {
                            account = squeeze(substr($0, RSTART, RLENGTH))

                            break
                        }
                    }

                    continue
                }

                if (match($0, /^STATEMENT FROM /) > 0) {
                    split($0, a, ",")

                    if (length(a) == 3) {
                        toyear = trim(a[3])

                        split(a[2],b)
                        fromyear = trim(b[1])
                    } else {
                        toyear = ""
                        fromyear = trim(a[2])
                    }

                    continue
                }

                if (match($0, /^TRANSACTION.*\(\$\)/) > 0) {
                    reclen = RSTART + RLENGTH

                    while (save == 0 && getline > 0) {
                        switch (substr($0, 1, reclen)) {
                        case /^DATE[[:space:]]*DATE[[:space:]]*$/:
                            break
                        case /^[[:space:]]*$/:
                            break
                        default:
                            save = 1
                        }
                    }
                }

                if (save == 1) {
                    rec = substr($0, 1, reclen)
                    junk = substr($0, reclen + 1)

                    split(rec, a)
                    if (match(rec, /[[:graph:]]/) == 0 && length(junk) > 0) {
                        continue
                    }

                    if (length(a) > 1 && length(a) < 5) {
                        save = 0

                        continue
                    }

                    text[line++] = rec
                }
            }
        }

        END {
            lines = line

            if (visa == 0 || lines == 0) {
                printf("Error: \"%s\" does not appear to be a valid VISA statement\n", filename) > "/dev/stderr"

                exit(1)
            }

            if ( header == 1 )
                printf("\"Account Type\",\"Account Number\",\"Transaction Date\",\"Cheque Number\",\"Description 1\",\"Description 2\",\"CAD$\",\"USD$\"\n")

            for (line = 0; line <= lines; line++) {
                split(text[line], a)
                if (length(a) == 1)
                    desc2[line - 1] = a[1]
            }

            for (line = 0; line <= lines; line++) {
                split(text[line], a)
                if (length(a) >= 6) {
                    word1 = a[5]
                    gsub(/[\\.^$(){}\[\]|*+?]/, "\\\\&", word1)
                    if (length(a) > 6) {
                        word2 = a[6]
                        gsub(/[\\.^$(){}\[\]|*+?]/, "\\\\&", word2)
                        regex = sprintf("%s[[:space:]]+%s", word1, word2)
                    } else
                        regex = word1

                    astart = match(text[line], regex)
                    aend = index(text[line], a[length(a)])

                    activity = trim(substr(text[line], astart, aend - astart))
                    amount = trim(gensub(/\$/, "", 1, substr(text[line], aend)))

                    if (length(toyear) > 0) {
                        if (match(date, /[Dd][Ee][Cc]/) > 0)
                            isodate = fixdate(sprintf("%s %s 0 0 0", fromyear, date))
                        else
                            isodate = fixdate(sprintf("%s %s 0 0 0", toyear, date))
                    } else 
                        isodate = fixdate(sprintf("%s %s 0 0 0", fromyear, date))

                    printf("\"Visa\",\"%s\",%s,\"\",\"%s\",\"%s\",%s,\"\"\n", \
                        account, isodate, activity, desc2[line], amount)
                }
            }
        }'

    return $?
}

parse_chequing () {
    local file=$1
    local header=$2 && header=${header:-0}
    
    cat $file | awk -v header=$header -v filename="$file" -e "$AWK_FUNCTIONS" -e '
        function dbg(s) { if (ENVIRON["DBG"] ~ "3") printf("DBG \"%s\" : %s\n", s, $0) > "/dev/stderr" }

        function process_lines() {
            while (getline > 0) {
                if (match($0, /Date[[:space:]]+Description/) > 0) {
                    col1 = RSTART
                    col2 = match($0, /Description[[:space:]]+/)
                    col3 = match($0, /Withdrawals[[:space:]]+/)
                    col4 = match($0, /Deposits[[:space:]]+/)
                    col5 = match($0, /Balance[[:space:]]*/)

                    start = 1

                    continue
                }

                date = trim(substr($0, col1, col2 - col1))
                activity = trim(substr($0, col2, col3 - col2))
                desc2 = ""
                withdrawal = trim(substr($0, col3, col4 - col3))
                deposit = trim(substr($0, col4, col5 - col4))

                if (save == 1 && length($0) == 0) {
                    dbg(" > end")
                    save = 0
                    start = 0

                    break
                } else if (start == 1 && save == 0) {
                    if (match($0, "Opening Balance") > 1)
                        continue

                    if (length(date) > 0) {
                        isodate = fixdate(sprintf("%s %s 0 0 0", fromyear, date))
                        if (length(isodate) > 0) {
                            dbg(" > save")
                            save = 1
                            lastdate = date

                            if (length(withdrawal) == 0 && length(deposit) == 0) {
                                # 2 line activity
                                dbg(" > 2line")
                                if (getline > 0) {
                                    desc2 = trim(substr($0, col2, col3 - col2))
                                    withdrawal = trim(substr($0, col3, col4 - col3))
                                    deposit = trim(substr($0, col4, col5 - col4))
                                } else {
                    
                                    break;
                                }
                            }


                            if (length(withdrawal) > 1)
                                amount = sprintf("-%s", withdrawal)
                            else
                                amount = deposit

                            text[++line] = sprintf("%s^%s^%s^%s", date, activity, desc2, amount)
                            dbg(sprintf(">%s^%s^%s^%s<", date, activity, desc2, amount))
                        }
                    
                        continue
                    }
                } else if (save == 1) {
                    if (match($0, "Closing Balance") > 1) {
                        dbg(" > end2")
                        save = 0
                        start = 0

                        break
                    }

                    if (length(withdrawal) == 0 && length(deposit) == 0) {
                        # 2 line activity
                        dbg(" > 2line")
                        if (getline > 0) {
                            desc2 = trim(substr($0, col2, col3 - col2))
                            withdrawal = trim(substr($0, col3, col4 - col3))
                            deposit = trim(substr($0, col4, col5 - col4))
                        } else {
                    
                            break;
                        }
                    }

                    if (length(withdrawal) > 1)
                        amount = sprintf("-%s", withdrawal)
                    else
                        amount = deposit

                    if (length(date) == 0) date = lastdate

                    text[++line] = sprintf("%s^%s^%s^%s", date, activity, desc2, amount)
                    dbg(sprintf(">%s^%s^%s^%s<", date, activity, desc2, amount))
                }
            }
        }

        BEGIN {
            chequing = 0
            account = ""
            col1 = -1
            start = 0
            save = 0
            line = 0

            while (getline > 0) {
                if (match($0, /Your RBC personal banking/) > 0) {
                    dbg("1  chequing")
                    chequing = 1

                    while (getline > 0) {
                        if (match($0, /From[[:space:]]+.*to[[:space:]]+/) > 0) {
                            dbg("2  start/end dates")
                            dates = substr($0, RSTART)

                            split(dates, a, /to[[:space:]]+/)
                            split(a[2], b, /,[[:space:]]/)
                            toyear = b[2]

                            split(substr(dates, 1, match(dates, /[[:space:]]+to[[:space:]]+/) - 1), a, /From[[:space:]]+/)
                            split(a[2], b, /,[[:space:]]/)
                            fromyear = b[2]

                            break
                        }
                    }

                    continue
                }

                if (match($0, /Your account number:[[:space:]]+/) > 0) {
                    dbg("3  account")
                    split(substr($0, RSTART), a, /:[[:space:]]*/)
                    account = gensub(/..-.../, "**-***", 1, a[2])

                    continue
                }

                if (match($0, /Details of your account activity$/) > 0) {
                    dbg("4  page 1")
                    process_lines()

                    continue
                }

                if (match($0, /Details of your account activity - continued$/) > 0) {
                    dbg("5  page n")
                    process_lines()

                    continue
                }
            }
        }


        END {
            lines = line

            if (chequing == 0 || lines == 0) {
                printf("Error: \"%s\" does not appear to be a valid account statement\n", filename) > "/dev/stderr"

                exit(1)
            }

            if (header > 0)
                printf("\"Account Type\",\"Account Number\",\"Transaction Date\",\"Cheque Number\",\"Description 1\",\"Description 2\",\"CAD$\",\"USD$\"\n")

            for (line = 1; line <= lines; line++) {
                split(text[line], a, "^")

                date = a[1]
                activity = a[2]
                desc2 = a[3]
                amount = a[4]

                if (length(toyear) > 0) {
                    if (match(date, /[Dd][Ee][Cc]/) > 0)
                        isodate = fixdate(sprintf("%s %s 0 0 0", fromyear, date))
                    else
                        isodate = fixdate(sprintf("%s %s 0 0 0", toyear, date))
                } else 
                    isodate = fixdate(sprintf("%s %s 0 0 0", fromyear, date))

                printf("\"Chequing\",\"%s\",%s,\"\",\"%s\",\"%s\",%s,\"\"\n", \
                        account, isodate, activity, desc2, amount)
            }
        }'

    return $?
}

#
#
#

IDIR=$1
ODIR=$2
HEADER=0

if [ -z "$IDIR" ]; then
    echo 2>&1 "Error: Need to specify directory for input .pdf files"

    exit
fi

[ -z "$ODIR" ] && ODIR="."

ls -1 $IDIR | grep -E '[Pp][Dd][Ff]$' | sed 's/ /^/g' | while read file junk; do
	infile=$(echo $file | sed 's/\^/ /g')
	outfile=$(echo "$file" | sed -e 's/\^/_/g' -e's/\.[Pp][Dd][Ff]$/.txt/')
	
	pdftotext -enc ASCII7 -layout -q "${IDIR}/$infile" $ODIR/$outfile

    if [ -f $ODIR/$outfile ]; then
        if [ $HEADER -eq 0 ]; then
            parse_visa $ODIR/$outfile 1
            RC=$?

            if [ $RC -ne 0 ]; then
                parse_chequing $ODIR/$outfile 1
                RC=$?
            fi

            [ $RC -eq 0 ] && HEADER=1
        else
            parse_visa $ODIR/$outfile
            [ $? -ne 0 ] && parse_chequing $ODIR/$outfile
        fi
    fi
done
