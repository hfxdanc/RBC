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

    function ruler(s) {
        if (ENVIRON["DBG"] >= 2) {
            print "         1         2         3         4         5         6         7         8" > "/dev/stderr"
            print "12345678901234567890123456789012345678901234567890123456789012345678901234567890" > "/dev/stderr"
            print \$0 > "/dev/stderr"
        }
    }

    # ISO 18245:2003 with single code overrides from VISA/Mastercard documents
    function mcc_category(i) {
        j = strtonum(gensub(/^[0]*/, "", "g", i))
        
        if (j >= 1 && j <= 699)
            s = "Reserved"
        else if (j >= 700 && j <= 999)
            s = "Agricultural services"
        else if (j >= 1000 && j <= 1499)
            s = "Reserved"
        else if (j >= 1500 && j <= 2999)
            s = "Contracted services"
        else if (j >= 3000 && j <= 3350)
            s = "Airlines"
        else if (j >= 3351 && j <= 3500)
            s = "Automobile/Vehicle rentals"
        else if (j >= 3501 && j <= 3999)
            s = "Hotels and Motels"
        else if (j >= 4000 && j <= 4799)
            s = "Transportation"
        else if (j >= 4800 && j <= 4999)
            s = "Utilities"
        else if (j >= 5000 && j <= 5199)
            s = "Retail outlets"
        else if (j >= 5200 && j <= 5499)
            s = "Retail stores"
        else if (j >= 5500 && j <= 5599)
            s = "Automobiles and vehicles"
        else if (j >= 5600 && j <= 5699)
            s = "Clothing stores"
        else if (j >= 5700 && j <= 5999)
            s = "Miscellaneous stores"
        else if (j >= 6000 && j <= 7299)
            s = "Service providers"
        else if (j >= 7300 && j <= 7529)
            s = "Business services"
        else if (j >= 7530 && j <= 7799)
            s = "Repair services"
        else if (j >= 7800 && j <= 7999)
            s = "Amusement and entertainment"
        else if (j >= 8000 && j <= 8999)
            s = "Professional services and membership organizations"
        else if (j >= 9000 && j <= 9199)
            s = "Reservered for ISO use"
        else if (j >= 9200 && j <= 9402)
            s = "Government services"
        else if (j >= 9403 && j <= 9999)
            s = "Reserved"
        else
            s = ""

        switch (i) {
        case 2741:
        case 2791:
        case 2842:
        case 7829:
            s = "Wholesale distibuters and manufacturers"
            break
        case 4111:
        case 4121:
        case 4784:
        case 7523:
        case 7524:
            s = "Travel"
            break
        case 4829:
        case 5811:
            s = "Service providers"
            break
        case 5411:
            s = "Groceries"
            break
        case 5541:
        case 5542:
            s = "Gas/Service stations"
            break
        case 5812:
        case 5813:
        case 5814:
            s = "Restaurants"
            break
        case 5912:
            s = "Pharmacies/Drug stores"
            break
        case 5960:
        case 5962:
        case 5964:
        case 5965:
        case 5966:
        case 5967:
        case 5968:
        case 5969:
            s = "Mail/Telephone order providers"
            break
        case 7011:
            s = "Hotels and Motels"
            break
		case 7210:
		case 7211:
		case 7216:
		case 7217:
		case 7221:
		case 7230:
		case 7251:
		case 7261:
		case 7273:
		case 7276:
		case 7277:
		case 7278:
		case 7296:
		case 7297:
		case 7298:
		case 7299:
            s = "Personal service providers"
            break
		case 7512:
		case 7513:
		case 7519:
            s = "Automobile/Vehicle rentals"
            break
		case 9706:
            s = "Amusement and entertainment"
            break
        default:
        }

        return s
    }

%E%O%T%
)

make_csv () {
	# shellcheck disable=SC3043
	local link="$1"
	# shellcheck disable=SC3043
	local file="$2"

	# shellcheck disable=SC2002
	cat "$file" | awk -v link="$link" -e "$AWK_FUNCTIONS" -e '
		function dbg2(s) { if (ENVIRON["DBG"] >= 2) printf("DBG \"%s\" : %s\n", s, $0) > "/dev/stderr" }

        BEGIN {
            lines = 0

            switch (toupper(link)) {
            case /VISA/:
                kind = 1
                break
            case /MASTERCARD/:
                kind = 2
                break
            default:
                kind = 0
            }

            dbg2(sprintf("kind=%s", kind))
        }

        {
            switch (kind) {
            case 1:
                if (split($0, a, /^[0-9][0-9][0-9][0-9]/, b) == 2) {
                    code = b[1]
                    details = trim(a[2])

                    dbg2(sprintf("code=.%s. category=>%s<", code, details))

                    if (match(details, /[[:space:]][[:space:]][[:space:]]+/) > 0) {
                        merchant[code] = substr(details, RSTART + RLENGTH)
                        details = substr(details, 1, RSTART - 1)

                        dbg2("VISA merchant")
                    }

                    if (length(details) > length(sub_category[code])) {
                        if (length(detail[code]) > 0)
                            dbg2("VISA sub-category replacement")

                        sub_category[code] = details
                    }

                    category[code] = mcc_category(code)
                }

                break
            case 2:
                if (split($0, a, /^[[:space:]]+[0-9][0-9][0-9][0-9]/, b) == 2) {
                    code = trim(b[1])

                    # MasterCard document cleanups
                    details = gensub(/[-]+/, "-", "g", trim(a[2]))
                    details = gensub(/2$/, "", 1, details)
                    details = gensub(/, and /, " and ", "g", details)
                    details = gensub(/-not elsewhere classified/, " (Not Elsewhere Classified)", 1, details)

                    if (code >=3000 && code <= 3350) 
                        details = gensub(/-[^-]*$/, "", 1, details)

                    dbg2(sprintf("code=.%s. details=>%s<", code, details))

                    switch (details) {
                    case /^[A-Z], [A-Z][[:space:]]/:
                    case /^[A-Z][[:space:]][[:space:]][[:space:]]/:
                        match(details, /[[:space:]][[:space:]][[:space:]]+/)
                        details = substr(details, RSTART + RLENGTH)

                        if (length(details) > length(codes[code])) {
                            if (length(codes[code]) > 0)
                                dbg2("MasterCard details replacement")

                            sub_category[code] = details
                        }

                        break
                    default:

                    }
                    category[code] = mcc_category(code)
                }

                break
            default:
            }
        }

        END {
            for (code in sub_category) 
                printf("\"%s\",\"%s\",\"%s\",\"%s\"\n", code, sub_category[code], category[code], merchant[code])

		}'

	return $?
}

#
#
#

DIR=$1
# shellcheck disable=SC2034
CITI="https://www.citibank.com/tts/solutions/commercial-cards/assets/docs/govt/Merchant-Category-Codes.pdf"
MASTERCARD="https://www.mastercard.us/content/dam/mccom/en-us/documents/rules/quick-reference-booklet-merchant-edition.pdf"
VISA="https://usa.visa.com/content/dam/VCOM/download/merchants/visa-merchant-data-standards-manual.pdf"

# shellcheck disable=SC2166
[ -z "$DIR" -o ! -d "$DIR" ] && DIR="./datafiles"

for link in "$MASTERCARD" "$VISA"; do
    file=$(basename "$link")
    outfile=$(echo "$file" | sed -e 's/\^/_/g' -e's/\.[Pp][Dd][Ff]$/.txt/')

    if [ ! -s "${DIR}/$file" ]; then
        curl --output-dir "$DIR" --output "$file" "$link"
    fi

    # shellcheck disable=SC2181
    if [ $? -eq 0 ]; then
        pdftotext -enc ASCII7 -layout -q "${DIR}/$file" "${DIR}/$outfile"

        make_csv "$link" "${DIR}/$outfile"
    else
        echo 1>&2 "Download of \"$link\" failed"
    fi
done
