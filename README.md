# RBC
Scripts to parse RBC statements.

`parse_statements.sh <directory of .pdf statments> [outdir (.txt extracts)]`

Outputs: comma separated values on STDOUT

Environment variables:

`DBG=1` -> trace sh

`DBG=2` -> Debug VISA processing

`DBG=3` -> Debug Account processing

`RBCCSV=0` -> Use ISO standard date format (easier import into spreadsheet)

------

### MariaDB Configuration

#### Fedora

Create AD managed Service Account and Kerberos keytab

$ `sudo sh -c 'umask 0077; mkdir /var/lib/user/mysql'
$ sudo chown mysql:mysql /var/lib/user/mysql`

`$ adcli create-msa --domain=<DOMAIN> --host-keytab=/var/lib/user/mysql/mysql.keytab --login-user=<AD Administrator>`

 or if MSA should be created in a separate OU

`$ adcli create-msa --domain=<DOMAIN> --domain-OU='CN=Users,OU=Unix,DC=XXX,DC=XXX,DC=XXX' --host-keytab=/var/lib/user/mysql/mysql.keytab --login-user=<AD Administrator>`
