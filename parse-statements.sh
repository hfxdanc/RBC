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
			case /^[Jj][Aa][Nn]/:
				a[j] = 1
				pos = j
				break
			case /^[Ff][Ee][Bb]/:
				a[j] = 2
				pos = j
				break
			case /^[Mm][Aa][Rr]/:
				a[j] = 3
				pos = j
				break
			case /^[Aa][Pp][Rr]/:
				a[j] = 4
				pos = j
				break
			case /^[Mm][Aa][Yy]/:
				a[j] = 5
				pos = j
				break
			case /^[Jj][Uu][Nn]/:
				a[j] = 6
				pos = j
				break
			case /^[Jj][Uu][Ll]/:
				a[j] = 7
				pos = j
				break
			case /^[Aa][Uu][Gg]/:
				a[j] = 8
				pos = j
				break
			case /^[Ss][Ee][Pp]/:
				a[j] = 9
				pos = j
				break
			case /^[O][Cc][Tt]/:
				a[j] = 10
				pos = j
				break
			case /^[Nn][Oo][Vv]/:
				a[j] = 11
				pos = j
				break
			case /^[Dd][Ee][Cc]/:
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

	function writecsv() {
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
	}

%E%O%T%
)

parse_visa () {
	# shellcheck disable=SC3043
	local file="$1"
	# shellcheck disable=SC3043
	local header="$2" && header=${header:-0}

	# shellcheck disable=SC2002
	cat "$file" | awk -v header="$header" -v filename="$file" -e "$AWK_FUNCTIONS" -e '
		function dbg(s) { if (ENVIRON["DBG"] >= 2) printf("DBG \"%s\" : %s\n", s, $0) > "/dev/stderr" }
		function dbg2(s) { if (ENVIRON["DBG"] == 3) printf("DBG \"%s\" : %s\n", s, $0) > "/dev/stderr" }

		function process_lines() {
			col1 = -1
			save = 0
			start = 0

			while (getline > 0) {
				if (match($0, /DATE[[:space:]]+DATE/) > 0) {
					dbg(" > start")
					col1 = RSTART

					start = 1

					continue
				}

				dbg2(">>> REC")
				col2 = index($0, $2) + length($2) + 1
				date = trim(substr($0, col1, col2 - col1))

				if (save == 1 && length($0) == 0) {
					dbg(" > end")
					start = 0

					break
				} else if (start == 1) {
					if (length(date) > 0) {
						isodate = fixdate(sprintf("%s %s 0 0 0", fromyear, date))
						if (length(isodate) > 0) {
							dbg(" > save")
							save = 1

							buff = substr($0, col2)
							split(buff , a)
							col3 = col2 + index(buff, a[2]) + length(a[2])
							col4 = col2 + match(buff, /[-]*\$[[:digit:]]+/) - 1

							buff = substr($0, col4)
							split(buff , a)
							col5 = col4 + length(a[1]) + 1

							pdate = trim(substr($0, col2, col3 - col2))
							activity = trim(substr($0, col3, col4 - col3))
							amount = trim(gensub(/[\$,]/, "", "g", substr($0, col4, col5 - col4))) * -1

							# Always 2 line activity
							if (getline > 0) {
								dbg(" > 2line")
								desc2 = trim(substr($0, col3, col4 - col3))
							} else {
								dbg("??? unxpected EOF")
								rc = 99

								break;
							}

							text[++line] = sprintf("%s^%s^%s^%s", pdate, activity, desc2, amount)
							dbg2(sprintf(">%s^%s^%s^%s<", pdate, activity, desc2, amount))
						}
					}
				}
			}
		}

		BEGIN {
			visa = 0
			account = ""
			regex = "NeVeRmAtCh"
			fromyear = ""
			toyear = ""
			page = 0
			line = 0
			rc = 0

			while (getline > 0) {
				if (visa == 0 && match($0, /^[[:space:]]*RBC[\(R\)]*[[:space:]].*Visa/) > 0) {
					dbg("1  visa")
					visa = 1

					while (getline > 0) {
						if (match($0, /[[:digit:]]+[0123456789 \*]+[[:digit:]]+/) > 0) {
							dbg("2  account")
							account = substr($0, RSTART, RLENGTH)

							if (regex ~ /^NeVeRmAtCh$/)
								regex = gensub(/\*/, "\\\\*", "g", sprintf("%s - PRIMARY", account))

							break
						}
					}

					continue
				}

				if (length(fromyear) == 0 && match($0, /^STATEMENT FROM /) > 0) {
					dbg("3  start/end dates")
					split($0, a, ",")

					if (length(a) == 3) {
						split(a[3], b)
						toyear = trim(b[1])

						split(a[2], b)
						fromyear = trim(b[1])
					} else {
						split(a[2], b)
						fromyear = trim(b[1])
					}

					continue
				}

				if (match($0, regex) > 0) {
					dbg(sprintf("4  page %d", ++page))
					process_lines()

					if (page == 1)
						regex = sprintf("%s \\(continued\\)", regex)

					continue
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

			writecsv()

			exit(rc)
		}'

	return $?
}

parse_chequing () {
	# shellcheck disable=SC3043
	local file="$1"
	# shellcheck disable=SC3043
	local header="$2" && header=${header:-0}

	# shellcheck disable=SC2002
	cat "$file" | awk -v header="$header" -v filename="$file" -e "$AWK_FUNCTIONS" -e '
		function dbg(s) { if (ENVIRON["DBG"] >= 2) printf("DBG \"%s\" : %s\n", s, $0) > "/dev/stderr" }
		function dbg2(s) { if (ENVIRON["DBG"] == 3) printf("DBG \"%s\" : %s\n", s, $0) > "/dev/stderr" }

		function process_lines() {
			while (getline > 0) {
				if (match($0, /Date[[:space:]]+Description/) > 0) {
					dbg(" > start")
					col1 = RSTART
					col2 = match($0, /Description[[:space:]]+/)
					col3 = match($0, /Withdrawals[[:space:]]+/)
					col4 = match($0, /Deposits[[:space:]]+/)
					col5 = match($0, /Balance[[:space:]]*/)

					start = 1

					continue
				}

				dbg2(">>> REC")
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
									dbg("??? unxpected EOF")
									rc = 99

									break;
								}
							}


							if (length(withdrawal) > 1)
								amount = sprintf("-%s", withdrawal)
							else
								amount = deposit

							text[++line] = sprintf("%s^%s^%s^%s", date, activity, desc2, amount)
							dbg2(sprintf(">%s^%s^%s^%s<", date, activity, desc2, amount))
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
							dbg("??? unxpected EOF")
							rc = 99

							break;
						}
					}

					if (length(withdrawal) > 1)
						amount = sprintf("-%s", withdrawal)
					else
						amount = deposit

					if (length(date) == 0) date = lastdate

					text[++line] = sprintf("%s^%s^%s^%s", date, activity, desc2, amount)
					dbg2(sprintf(">%s^%s^%s^%s<", date, activity, desc2, amount))
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
			rc = 0

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

			writecsv()

			exit(rc)
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

# shellcheck disable=SC2010,SC2034
ls -1 "$IDIR" | grep -E '[Pp][Dd][Ff]$' | sed 's/ /^/g' | while read -r file junk; do
	infile=$(echo "$file" | sed 's/\^/ /g')
	outfile=$(echo "$file" | sed -e 's/\^/_/g' -e's/\.[Pp][Dd][Ff]$/.txt/')

	pdftotext -enc ASCII7 -layout -q "${IDIR}/$infile" "$ODIR/$outfile"

	if [ -f "$ODIR/$outfile" ]; then
		if [ $HEADER -eq 0 ]; then
			parse_visa "$ODIR/$outfile" 1
			# shellcheck disable=SC2030
			RC=$?

			if [ $RC -eq 1 ]; then
				parse_chequing "$ODIR/$outfile" 1
				# shellcheck disable=SC2030
				RC=$?
			fi

			[ $RC -eq 0 ] && HEADER=1
		else
			parse_visa "$ODIR/$outfile"
			# shellcheck disable=SC2181
			[ $? -ne 0 ] && parse_chequing "$ODIR/$outfile"
		fi
	fi
done

