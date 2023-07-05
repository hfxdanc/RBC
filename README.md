# RBC

##### Scripts to parse RBC statements.

`parse_statements.sh <directory of .pdf statments> [outdir (.txt extracts)]`

Outputs: comma separated values on STDOUT

Environment variables:

`DBG=1` -> trace sh

`DBG=2` -> Debug VISA processing

`DBG=3` -> Debug Account processing

`RBCCSV=0` -> Use ISO standard date format (easier import into spreadsheet)

------

`make-mcc.sh [IN/OUT directory - default ./datadir]`

Downloads VISA/MasterCard sources from Internet to extract Merchant Category Code data (MCC)  and combine into single file.

Use: .`/make-mcc.sh | sort -u >datafiles/mcc.txt`

Outputs: comma separated values in `mcc.txt`

Environment variables:

`DBG=1` -> trace sh

`DBG=2` -> Debug processing

------

`mastercard_supplementry.sh`

Extract  additional MCC category information from MasterCard document.

Use:  `/bin/sh mastercard_supplementry.sh`

Outputs: comma separated values in `datafiles/mastercard_supplementry.txt`

------

##### Collection of data files for budget database

`datafiles/mcc.csv`

Opinionated manual cleanup of MCC data.

- prefer mixed case
- prefer better grammar

------

`datafiles/accounts.csv-example`

Banking account types and numbers to reference statement transactions.

------

`datafiles/budget_categories.csv`

List of personal budget categories extracted from various sources.

------

### MariaDB Configuration

#### Fedora

Create AD managed Service Account and Kerberos keytab

$ `sudo sh -c 'umask 0077; mkdir /var/lib/user/mysql'
$ sudo chown mysql:mysql /var/lib/user/mysql`

`$ adcli create-msa --domain=<DOMAIN> --host-keytab=/var/lib/user/mysql/mysql.keytab --login-user=<AD Administrator>`

 	or if MSA should be created in a separate OU

`$ adcli create-msa --domain=<DOMAIN> --domain-OU='CN=Users,OU=Unix,DC=XXX,DC=XXX,DC=XXX' --host-keytab=/var/lib/user/mysql/mysql.keytab --login-user=<AD Administrator>`
